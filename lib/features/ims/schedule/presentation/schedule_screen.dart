import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
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
  void _goToWeek(int target) {
    final current = _week;
    if (current == null) return; // 整学期视图不切周
    final clamped = clampTeachingWeek(target, lastWeek: _lastWeek);
    if (clamped == current) return;
    setState(() => _week = clamped);
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
        Expanded(child: _buildBody(horizontal)),
      ],
    );

    if (widget.showAppBar) {
      // 宽度够就排成一行（学年 + 学段 + 周次切换），窄宽度（手机竖屏）才两行
      // ——用户 2026-09-15 问「为什么学期选择和周数显示不在同一行」：此前是写死
      // 两行，桌面端白白浪费一行高度，现改为按可用宽度自适应。
      final oneRow = ScheduleTitleBar.fitsOneRow(
        context,
        compact: compact,
        isCurrentTerm: _isCurrentTerm,
        currentWeek: _currentWeek,
        // `week` 必须传：本周按钮在 `week == currentWeek` 时不渲染，
        // 不传会把它的宽度白算进去（用户 2026-09-15：「还有很大的空隙就换行」）。
        week: _week,
      );
      final range = _termPickerRange;
      return Scaffold(
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: 0,
          toolbarHeight: ScheduleTitleBar.toolbarHeight(
            oneRow: oneRow,
            compact: compact,
          ),
          // 用户 2026-09-15：标题栏不再显示「课表」，改为学期选择器 +
          // 周数选择 / 整学期切换（手机端字号收紧）。
          title: ScheduleTitleBar(
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
            onToggleView: () => setState(
              () => _week = _week == null ? (_currentWeek ?? 1) : null,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.event_repeat),
              tooltip: '调课管理',
              onPressed: _openRescheduleManager,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: _loadData,
            ),
          ],
        ),
        body: body,
      );
    }
    return body;
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
            onGoToWeek: _goToWeek,
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
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
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
                  '$_selectedYear-$_selectedSemester 学期课表尚未发布，'
                  '可稍后下拉或点右上角刷新',
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

    // 周视图 = 一页一周的翻页器（用户 2026-09-15：「像手机桌面翻页一样」）：
    // 相邻周并排在左右两侧随手指位移，松手按距离/速度 snap，首末周自然回弹。
    return WeekPager(
      weekCount: _lastWeek,
      week: week,
      enabled: _swipeEnabled(context),
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
          );
  }
}
