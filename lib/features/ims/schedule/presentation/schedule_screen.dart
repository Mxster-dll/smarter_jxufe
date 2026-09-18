import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/settings/domain/settings_section.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_display_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/reschedule_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule_engine.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_view_mode.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/term_weeks.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/reschedule_editor_sheet.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/reschedule_list_screen.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_body_area.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_grid_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_horizontal_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_title_bar.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/week_pager.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/school_calendar_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/teaching_week.dart';
import 'package:smarter_jxufe/shared/widgets/academic_year_picker.dart';

/// 课表页相关的三节：教务会话（课表数据）+ 上课实况窗（入口在设置页）
/// + 课表显示（周六 / 周日 / 表格线开关，用户 2026-09-17 要求）。
///
/// **两条链路共用同一份清单**：整页模式的导航栏（`paneAppBar` 自动追加齿轮）
/// 与侧栏内嵌模式的工具条（`PaneBody.settingsSections`，用户 2026-09-17
/// 「课表页的设置按钮不见了」——内嵌模式没有 AppBar，从前这个入口整个消失）。
const List<SettingsSection> scheduleSettingsSections = <SettingsSection>[
  SettingsSection.imsSession,
  SettingsSection.liveClass,
  SettingsSection.schedule,
];

class ScheduleScreen extends ConsumerStatefulWidget {
  final bool showAppBar;

  const ScheduleScreen({super.key, this.showAppBar = true});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  List<ScheduleEntry>? _entries;
  String? _error;
  bool _isLoading = true;
  bool _isHorizontal = false;

  /// 正在查看的学年 / 学期。
  ///
  /// **不再用学籍的入学年**：入学年只说明该生哪一级，跟「此刻该看哪个学期」
  /// 无关（2025 级学生 2026 年 9 月要看的也是 2026-2027 第一学期）。
  late int _selectedYear;
  late String _selectedSemester;
  String _serialNo = '';

  /// 学籍入学年（`StudentInfo.enrollYear`，如 2025）。
  ///
  /// **只用作手机端学期选择器的范围起点**（用户 2026-09-15：「范围设为入学年份-
  /// 当前学年」）——绝不当「当前学年」用，见 §9 的历史 bug。
  int? _enrollYear;

  // ─── 调课 ─────────────────────────────────────────────────────

  late final RescheduleStore _rescheduleStore;
  List<Reschedule> _reschedules = const [];

  /// 展示的教学周；null = 整学期模板视图。
  int? _week;

  /// 是否已按「当前教学周」初始化过默认周次。
  bool _weekInitialized = false;

  /// 「平滑跳转」请求序号：长按周数回本周时 +1，让分页器横划过去而不是瞬移
  /// （口径见 [WeekPager.smoothRequest]）。只有这一个入口会 +1。
  int _smoothWeekRequest = 0;

  /// 正在查看的学期是否就是当下学期（决定默认周次与表头日期是否有意义）。
  bool _isCurrentTerm = false;

  /// 当下学期的「第 1 教学周的周一」（用于把周次换算成日期）。
  DateTime? _firstMonday;

  /// 当下的教学周（开学前或非当前学期时为 null）。
  int? _currentWeek;

  RescheduleTerm get _term =>
      RescheduleTerm(_selectedYear.toString(), _selectedSemester);

  /// 正在看的学期尚未开学（第 0 周，或假期里看下学期课表）。
  ///
  /// 此时课表为空是正常的 —— 提示「课表还没出来」而不是「暂无课表数据」。
  bool get _termNotStarted => _isCurrentTerm && _currentWeek == null;

  /// 当前展示周的周一。
  DateTime? get _weekMonday {
    final w = _week;
    final fm = _firstMonday;
    if (w == null || fm == null) return null;
    return fm.add(Duration(days: (w - 1) * 7));
  }

  /// 本学期最后教学周（教务校历周次表 → 课表周次 → 兜底），见 `term_weeks.dart`。
  ///
  /// 用户 2026-09-15：「第一周和最后一周不允许再滑动，具体第一周和最后一周的
  /// 界定教务系统应该有接口……你找找然后复用」—— 第 1 周来自
  /// `resolveTeachingWeek`（已在用），最后一周复用同源的教务校历
  /// `schoolCalendarProvider((xn:, xq:))` 的周次表，不写死。
  int get _lastWeek {
    final xq = int.tryParse(_selectedSemester) ?? 0;
    final calendar = ref
        .read(schoolCalendarProvider((xn: _selectedYear, xq: xq)))
        .valueOrNull;
    return resolveLastTeachingWeek(
      calendar: calendar,
      entries: _entries ?? const [],
    );
  }

  /// 切到指定教学周；越界一律夹在 `[1, _lastWeek]`（首/末周不再动）。
  ///
  /// [smooth] = true 时**要求分页器横划过去**（哪怕跨十几周）—— 只有「长按周数
  /// 回本周」这条路径这么请求（用户 2026-09-17：「长按周数返回本周要显示横划
  /// 动画」）；弹窗选周 / 切学期仍是直接跳（定位语义，别让整屏不相干的周次掠过）。
  /// 实现见 `WeekPager.smoothRequest`：这里只把请求序号 +1。
  void _goToWeek(int target, {bool smooth = false}) {
    final current = _week;
    if (current == null) return; // 整学期视图不切周
    final clamped = clampTeachingWeek(target, lastWeek: _lastWeek);
    if (clamped == current) return;
    setState(() {
      _week = clamped;
      if (smooth) _smoothWeekRequest++;
    });
  }

  // ─── 移动端左右滑动切周（翻页手感在 WeekPager 内）──────────────

  /// 是否手机式输入（手机平台恒真；桌面窄窗口也允许滑动切周）。
  bool _swipeEnabled(BuildContext context) {
    if (_week == null) return false; // 整学期视图无周可切
    final size = MediaQuery.sizeOf(context);
    return scheduleMobileInput(
      platform: Theme.of(context).platform,
      width: size.width,
      height: size.height,
    );
  }

  /// 某一教学周的周一（分页器一页一周，每页各算各的日期）。
  DateTime? _mondayOfWeek(int week) =>
      _firstMonday?.add(Duration(days: (week - 1) * 7));

  /// 分页器手势翻到的周（用户 2026-09-15：滑动切周要像手机桌面翻页）。
  void _onPagerWeekChanged(int week) {
    if (week == _week) return;
    setState(() => _week = week);
  }

  @override
  void initState() {
    super.initState();
    // 首帧就要定在「当下学期」：_selectedYear 若等学籍异步返回后再纠正，
    // AcademicYearPicker 的 initState 已定格旧年份，界面显示不会跟着变。
    final term = currentSchoolTerm(
      DateTime.now(),
      terms: ref.read(offlineSemesterTermsProvider),
    );
    _selectedYear = term.xn;
    _selectedSemester = '${term.xq}';

    _rescheduleStore = ref.read(rescheduleStoreProvider);
    _rescheduleStore.addListener(_onReschedulesChanged);
    _initFromStudentInfo();
  }

  @override
  void dispose() {
    _rescheduleStore.removeListener(_onReschedulesChanged);
    super.dispose();
  }

  void _onReschedulesChanged() {
    if (!mounted) return;
    setState(() => _reschedules = _rescheduleStore.recordsOf(_term));
  }

  Future<void> _initFromStudentInfo() async {
    try {
      final studentInfoRepo = await ref.read(
        studentInfoRepositoryProvider.future,
      );
      StudentInfo? info;
      studentInfoRepo.getCachedStudentInfo().fold((_) {}, (i) => info = i);
      // 学籍只用来取教务 xh（= <xh>，即 serialNo）——教务自己的页面就是这么填的；
      // 学年学期由 currentSchoolTerm 决定（见 initState）。
      if (info != null) {
        _serialNo = info!.serialNo;
        // 入学年只喂给学期选择器的范围起点（当前学年仍由 currentSchoolTerm 给）。
        _enrollYear = int.tryParse(info!.enrollYear.trim());
      }
    } catch (_) {}
    _syncTermContext(resetWeek: true);
    if (!mounted) return;
    _loadData();
  }

  /// 重新解析「当下学期 / 当前教学周」上下文，并（按需）把展示周次拉回当下。
  ///
  /// 周次口径（用户 2026-09 裁定）：
  /// - 开学后（第 ≥1 教学周）→ 实际周数；
  /// - 开学前（第 0 周）或假期里看下一学期 → 整学期视图（`_week = null`）；
  /// - 查历史学期同理给整学期视图（周次无日期含义，用户仍可自己切）。
  void _syncTermContext({bool resetWeek = false}) {
    final terms = ref.read(offlineSemesterTermsProvider);
    final now = DateTime.now();
    final cur = currentSchoolTerm(now, terms: terms);
    final isCurrent =
        cur.xn == _selectedYear && '${cur.xq}' == _selectedSemester;

    DateTime? firstMonday;
    int? currentWeek;
    if (isCurrent) {
      // 直接算而不经 teachingWeekProvider：后者是容器级缓存，跨学期边界
      // （应用长驻）会拿到旧值；这里每次进入/切换都按当时时间重算。
      final tw = resolveTeachingWeek(now, terms: terms);
      if (tw != null && tw.term.matches(xn: cur.xn, xq: cur.xq)) {
        firstMonday = tw.firstMonday;
        if (tw.week >= 1) currentWeek = tw.week;
      }
    }

    if (!mounted) return;
    setState(() {
      _isCurrentTerm = isCurrent;
      _firstMonday = firstMonday;
      _currentWeek = currentWeek;
      if (resetWeek || !_weekInitialized) {
        _week = currentWeek;
        _weekInitialized = true;
      }
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_serialNo.isEmpty) throw Exception('未获取到学籍信息');

      // 调课记录：纯本地，先load（失败也不该拦住课表）
      await _rescheduleStore.ensureLoaded(_term);
      if (!mounted) return;
      setState(() => _reschedules = _rescheduleStore.recordsOf(_term));

      final repository = await ref.read(scheduleRepositoryProvider.future);
      final data = await repository.getSchedule(
        year: _selectedYear.toString(),
        semester: _selectedSemester,
        studentId: _serialNo,
      );
      if (!mounted) return;
      setState(() {
        _entries = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ─── 调课交互 ─────────────────────────────────────────────────

  Future<void> _onTapClass(EffectiveClass c) async {
    final existing = c.reschedule;
    await showRescheduleEditor(
      context,
      term: _term,
      store: _rescheduleStore,
      entries: _entries ?? const [],
      existing: existing,
      origin: existing == null
          ? RescheduleOrigin.of(c.entry, c.classTime)
          : null,
      initialWeek: _week ?? _currentWeek ?? 1,
      currentWeek: _currentWeek,
    );
  }

  Future<void> _onTapEmptySlot(DayOfWeek day, int period) async {
    await showRescheduleEditor(
      context,
      term: _term,
      store: _rescheduleStore,
      entries: _entries ?? const [],
      asExtra: true,
      initialWeek: _week ?? _currentWeek ?? 1,
      currentWeek: _currentWeek,
      initialDay: day,
      initialStartPeriod: period,
      initialEndPeriod: period,
    );
  }

  Future<void> _openRescheduleManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RescheduleListScreen(
          term: _term,
          entries: _entries ?? const [],
          currentWeek: _currentWeek,
        ),
      ),
    );
  }

  // ─── 构建 ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final platform = Theme.of(context).platform;
    // 手机端（Android / iOS）恒按手机排版；桌面端按窗口宽度（口径见
    // `domain/schedule_view_mode.dart`，别在页面里另写一套判断）。
    final compact = scheduleCompactLayout(
      platform: platform,
      width: size.width,
    );
    // 手机：按设备横竖屏自动选视图（用户 2026-09-15：「移动端取消切换横置/
    // 竖置按钮，而是适应屏幕是横屏还是竖屏」）；桌面：听用户的 `_isHorizontal`。
    final horizontal =
        scheduleViewModeFor(
          platform: platform,
          width: size.width,
          height: size.height,
          manualHorizontal: _isHorizontal,
        ) ==
        ScheduleViewMode.horizontal;

    final body = Column(
      children: [
        // 标题栏（AppBar）已承载学期/周次选择时，正文不再重复一条筛选栏，
        // 课表可用的高度也更充裕。
        if (!widget.showAppBar) ...[
          _buildFilters(context),
          const SizedBox(height: 8),
        ],
        // 正文（课表网格）让开底部系统导航栏：课表恒适应高度，被导航栏盖住的
        // 那一截会让最后一节 / 最后一天看不见（见 `ScheduleBodyArea`）。
        // 只包正文、不包上面的筛选栏（它在顶部，与导航栏无关）。
        Expanded(child: ScheduleBodyArea(child: _buildBody(horizontal))),
      ],
    );

    if (widget.showAppBar) {
      // 手机端不再放刷新按钮（用户 2026-09-16：「移动端，课表页取消刷新按钮，
      // 改为下拉页面刷新」）——改成 `RefreshIndicator`，见 `_wrapRefresh`。
      //
      // 视图切换按钮（整学期 / 周视图）也在这里：用户 2026-09-16「切换整学期/
      // 周视图的按钮和调课按钮放到一起，而不是居中」——从前它在标题栏中间那组里。
      // 三个按钮统一走 `scheduleBarAction`（紧凑款）：用户 2026-09-16
      // 「标题栏右侧按钮过大」。
      final actions = <Widget>[
        scheduleBarAction(
          icon: _week == null ? Icons.view_week : Icons.grid_view,
          tooltip: _week == null ? '切换到周视图' : '切换到整学期视图',
          compact: compact,
          onPressed: () =>
              setState(() => _week = _week == null ? (_currentWeek ?? 1) : null),
        ),
        scheduleBarAction(
          icon: Icons.event_repeat,
          tooltip: '调课管理',
          compact: compact,
          onPressed: _openRescheduleManager,
        ),
        if (!compact)
          scheduleBarAction(
            icon: Icons.refresh,
            tooltip: '刷新',
            compact: false,
            onPressed: _loadData,
          ),
      ];
      // 行宽记账要 +1：设置按钮会追加在 `actions` 末尾 —— 整页模式由 `paneAppBar`
      // 追加，侧栏内嵌模式由 `PaneBody.settingsSections` 在工具条行尾追加（两档都恰好
      // 一个，见 `scheduleSettingsSections`）。少算一个就会把标题栏的可用宽度
      // 多算 40px、该换行时不换行。
      final barActionCount = actions.length + 1;
      // 宽度够就排成一行（学期 + 周次），窄宽度（手机竖屏）才两行 —— 用户
      // 2026-09-15 问「为什么学期选择和周数显示不在同一行」：此前是写死两行，
      // 桌面端白白浪费一行高度，现改为按可用宽度自适应。`actionCount` 必须
      // 跟着 `actions.length` 走（2026-09-16 用户：「感觉不知道哪个组件的边距
      // 特别大，导致标题栏总是换行，但是标题栏其实是可以装下那么多内容的」——
      // 从前 chrome 写死 2 个按钮，手机端只有 1 个却白扣 48px）。
      final oneRow = ScheduleTitleBar.fitsOneRow(
        context,
        compact: compact,
        isCurrentTerm: _isCurrentTerm,
        currentWeek: _currentWeek,
        // `week` 必须传：整学期视图下周次控件不渲染（用户 2026-09-16：「整学期
        // 视图下，不要显示『整学期』字样」），不传会把它的宽度白算进去。
        week: _week,
        actionCount: barActionCount,
      );
      final range = _termPickerRange;
      // 用户 2026-09-15：标题栏不再显示「课表」，改为学期选择器 +
      // 周数选择（手机端字号收紧）。
      final titleBar = ScheduleTitleBar(
        selectedYear: _selectedYear,
        selectedSemester: _selectedSemester,
        week: _week,
        currentWeek: _currentWeek,
        isCurrentTerm: _isCurrentTerm,
        compact: compact,
        pickerStartYear: range.startYear,
        pickerEndYear: range.endYear,
        onYearChanged: _onYearChanged,
        onSemesterChanged: _onSemesterChanged,
        onTermPicked: _onTermPicked,
        onGoToWeek: _goToWeek,
        // 长按周数回本周：请求分页器**横划**过去（用户 2026-09-17）。
        onReturnToCurrentWeek: (week) => _goToWeek(week, smooth: true),
        lastWeek: _lastWeek,
        mondayOf: _mondayOfWeek,
        actionCount: barActionCount,
      );
      final barHeight = ScheduleTitleBar.toolbarHeight(
        oneRow: oneRow,
        compact: compact,
      );
      return Scaffold(
        // 本页导航栏里装的**就是**学期 / 周次选择器（不是「课表」标题）。侧栏内嵌
        // 模式（面板首路由）下整条导航栏不画，选择器与两个按钮一起下沉到内容首行
        // —— 用户 2026-09-16 裁定：面板顶部不留 chrome（见 §19）。
        appBar: paneAppBar(
          context,
          centerTitle: false,
          titleSpacing: 0,
          toolbarHeight: barHeight,
          title: titleBar,
          actions: actions,
          settingsSections: scheduleSettingsSections,
        ),
        body: PaneBody(
          leading: _paneTitleBar(titleBar, barActionCount),
          actions: actions,
          // 侧栏内嵌模式不画导航栏 → 齿轮只能由这行工具条自己补（见
          // `scheduleSettingsSections` 的注释）。
          settingsSections: scheduleSettingsSections,
          // 高度交给内容自己撑：标题栏内部的单行/两行判定要用**真实行宽**
          // （见 `_paneTitleBar`），外部按窗口宽算出来的高度可能与实际不符。
          height: null,
          padding: EdgeInsets.zero,
          child: _wrapRefresh(compact, body),
        ),
      );
    }
    return body;
  }

  /// 手机端 = 下拉刷新（用户 2026-09-16：「移动端，课表页取消刷新按钮，改为
  /// 下拉页面刷新」）；桌面端保留右上角刷新按钮，不做下拉。
  ///
  /// 下拉容器放在**最外层**（`_refreshable`），内层课表的滚动视图保持默认
  /// physics：ⓐ 课表铺满一屏时内层 `maxScrollExtent == 0`、默认 physics 的
  /// `shouldAcceptUserOffset` 为 false → 内层不注册拖动识别器，竖直拖动落到
  /// 外层那个恒可滚动的视图上 → `RefreshIndicator` 收到 depth 0 的通知；
  /// ⓑ **绝不能给内层加 `AlwaysScrollableScrollPhysics`** —— 实测会让分页板的
  /// 翻页阈值从 0.5 页放大到 1 页（探针：−220px 不翻页、−400px 才翻），等于
  /// 把「横滑切周」弄坏。
  Widget _wrapRefresh(bool compact, Widget child) {
    if (!compact) return child;
    return RefreshIndicator(onRefresh: _loadData, child: _refreshable(child));
  }

  /// 把内容包成可下拉的：固定成一屏大小，再套一个恒可滚动
  /// （[AlwaysScrollableScrollPhysics]）的滚动视图 —— 内容本身不滚动，但下拉
  /// 手势能触发外层 `RefreshIndicator`（它要求子树里存在可滚动的滚动视图）。
  Widget _refreshable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: child,
        ),
      ),
    );
  }

  /// 内嵌面板时给课表标题栏喂**真实行宽**。
  ///
  /// `ScheduleTitleBar` 自己按 `MediaQuery.sizeOf(context).width - chromeWidth` 判单行
  /// 还是两行（`schedule_title_bar.dart` 的 `fitsOneRow` / `chromeWidth = 152`），而内嵌
  /// 时那里量到的是**整个窗口宽**、不是面板行宽（面板 = 窗口 − 侧栏 232 − 分隔线 1）。
  /// 行内的可用宽度恰好是 `constraints.maxWidth`（两个按钮已经占掉行尾），把
  /// `chromeWidth` 加回去正好抵消它内部那次减法 → 判定口径回到真实行宽，窄窗口不会
  /// 「判定单行却放不下」。整页（非内嵌）模式下本方法构造的 widget 根本不会挂载。
  Widget _paneTitleBar(Widget titleBar, int actionCount) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          // `Size` 没有 copyWith，只能整只重建（宽度 = 真实行宽 + chrome）。
          data: media.copyWith(
            size: Size(
              constraints.maxWidth +
                  ScheduleTitleBar.chromeWidthFor(actionCount: actionCount),
              media.size.height,
            ),
          ),
          child: titleBar,
        );
      },
    );
  }

  void _onYearChanged(int year) {
    setState(() => _selectedYear = year);
    _syncTermContext(resetWeek: true);
    _loadData();
  }

  void _onSemesterChanged(String value) {
    setState(() => _selectedSemester = value);
    _syncTermContext(resetWeek: true);
    _loadData();
  }

  /// 手机端学期码选择器的学年范围（入学年 ~ 当前学年，见 `schoolTermPickerRange`），
  /// 并夹在 `ScheduleTitleBar.firstYear/lastYear` 内。
  ({int startYear, int endYear}) get _termPickerRange {
    final current = currentSchoolTerm(
      DateTime.now(),
      terms: ref.read(offlineSemesterTermsProvider),
    );
    final raw = schoolTermPickerRange(
      enrollYear: _enrollYear,
      currentYear: current.xn,
    );
    final start = raw.startYear
        .clamp(ScheduleTitleBar.firstYear, ScheduleTitleBar.lastYear)
        .toInt();
    final end = raw.endYear
        .clamp(ScheduleTitleBar.firstYear, ScheduleTitleBar.lastYear)
        .toInt();
    return (startYear: start, endYear: end < start ? start : end);
  }

  /// 手机端从学期码阵列里选中一个学期（学年 + 学段一起改）。
  void _onTermPicked(({int xn, int xq}) term) {
    if (term.xn == _selectedYear && '${term.xq}' == _selectedSemester) return;
    setState(() {
      _selectedYear = term.xn;
      _selectedSemester = '${term.xq}';
    });
    _syncTermContext(resetWeek: true);
    _loadData();
  }

  Widget _buildFilters(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          AcademicYearPicker(
            startYear: ScheduleTitleBar.firstYear,
            endYear: ScheduleTitleBar.lastYear,
            initialYear: _selectedYear,
            onChanged: _onYearChanged,
          ),
          ScheduleSemesterSelector(
            selectedSemester: _selectedSemester,
            compact: false,
            onChanged: _onSemesterChanged,
          ),
          ScheduleWeekSwitcher(
            week: _week,
            currentWeek: _currentWeek,
            isCurrentTerm: _isCurrentTerm,
            compact: false,
            lastWeek: _lastWeek,
            mondayOf: _mondayOfWeek,
            onGoToWeek: _goToWeek,
            onReturnToCurrentWeek: (week) => _goToWeek(week, smooth: true),
            onToggleView: () => setState(
              () => _week = _week == null ? (_currentWeek ?? 1) : null,
            ),
          ),
        ],
      ),
    );
  }

  void _toggleView() => setState(() => _isHorizontal = !_isHorizontal);

  Widget _buildBody(bool horizontal) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.critical(context),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('加载失败: $_error', textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_entries == null || _entries!.isEmpty) {
      // 尚未开学的学期（开学前第 0 周 / 假期里看下一学期）课表为空是正常的
      final pending = _termNotStarted;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                pending ? Icons.hourglass_empty : Icons.event_busy,
                size: 48,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                pending ? '课表还没出来' : '暂无课表数据',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (pending) ...[
                const SizedBox(height: 8),
                Text(
                  '$_selectedYear-$_selectedSemester 学期课表尚未发布，可稍后下拉刷新',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // 切换按钮内置在课表左上角格子中；手机端按横竖屏自动选视图 → 不渲染按钮。
    final showToggle = !scheduleAutoViewByOrientation(
      Theme.of(context).platform,
    );

    // 整学期视图（`_week == null`）= 单一模板页，没有「相邻周」可言 → 不分页。
    final week = _week;
    if (week == null) {
      return _buildWeekView(
        week: null,
        horizontal: horizontal,
        showToggle: showToggle,
      );
    }

    // 竖版周视图 = 分页板：顶部表头静止、左侧节数列拖动时淡出、只有主体翻页
    // （用户 2026-09-16 要求）—— 分页在 ScheduleGridView 内部完成，
    // 这样表头 / 节数列才能留在分页器外面。
    if (!horizontal) {
      return _buildWeekView(
        week: week,
        horizontal: false,
        showToggle: showToggle,
      );
    }

    // 横版 = 一页一周的翻页器（用户 2026-09-15：「像手机桌面翻页一样」）：
    // 相邻周并排在左右两侧随手指位移，松手按距离/速度 snap，首末周自然回弹。
    // （横版的「表头」是左侧节次列，与课格同在一行，暂不拆静态头。）
    // 下拉刷新由屏幕最外层的 `_refreshable` 负责，这里不再自己包滚动视图。
    return WeekPager(
      weekCount: _lastWeek,
      week: week,
      enabled: _swipeEnabled(context),
      // 长按周数回本周要横划过去（横版只有这一处分页器）。
      smoothRequest: _smoothWeekRequest,
      onWeekChanged: _onPagerWeekChanged,
      pageBuilder: (context, w) => _buildWeekView(
        week: w,
        horizontal: horizontal,
        showToggle: showToggle,
      ),
    );
  }

  /// 渲染某一教学周（或整学期模板，`week == null`）的课表视图。
  Widget _buildWeekView({
    required int? week,
    required bool horizontal,
    required bool showToggle,
  }) {
    final weekMonday = week == null ? _weekMonday : _mondayOfWeek(week);
    // 作息表（节次格里显示上下课时间）：实时优先，未回来时先用缓存/内置兜底
    // ——两层都是免登录数据，见 live_class_providers.dart。
    final periods =
        ref.watch(currentPeriodTableProvider).valueOrNull ??
        ref.watch(cachedPeriodTableProvider).valueOrNull;
    // 周六 / 周日是否显示、是否显示表格线（设置页「课表」节，用户 2026-09-17 要求）。
    final display = ref.watch(scheduleDisplayPrefsStoreProvider).prefs;
    return horizontal
        ? ScheduleHorizontalView(
            entries: _entries!,
            reschedules: _reschedules,
            week: week,
            weekMonday: weekMonday,
            onTapClass: _onTapClass,
            onTapEmptySlot: _onTapEmptySlot,
            onToggle: _toggleView,
            isHorizontal: horizontal,
            showToggle: showToggle,
            periods: periods,
            showSaturday: display.showSaturday,
            showSunday: display.showSunday,
            showGridLines: display.showGridLines,
          )
        : ScheduleGridView(
            entries: _entries!,
            reschedules: _reschedules,
            week: week,
            weekMonday: weekMonday,
            onTapClass: _onTapClass,
            onTapEmptySlot: _onTapEmptySlot,
            onToggle: _toggleView,
            isHorizontal: horizontal,
            showToggle: showToggle,
            periods: periods,
            showSaturday: display.showSaturday,
            showSunday: display.showSunday,
            showGridLines: display.showGridLines,
            // 竖版周视图内部分页（表头静态 + 节数列拖动淡出）；
            // 整学期模板没有相邻周 → 不分页。
            pagerWeekCount: week == null ? null : _lastWeek,
            pagerEnabled: week != null && _swipeEnabled(context),
            // 长按周数回本周要**横划过去**（见 `_goToWeek(smooth:)`）。
            pagerSmoothRequest: _smoothWeekRequest,
            onPagerWeekChanged: _onPagerWeekChanged,
            mondayOfWeek: _mondayOfWeek,
          );
  }
}
