import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/providers/reschedule_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule_engine.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/reschedule_editor_sheet.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/reschedule_list_screen.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_grid_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_horizontal_view.dart';
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
      // 学籍只用来取学号；学年学期由 currentSchoolTerm 决定（见 initState）。
      if (info != null) _serialNo = info!.serialNo;
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
    final body = Column(
      children: [
        _buildFilters(context),
        const SizedBox(height: 8),
        Expanded(child: _buildBody()),
      ],
    );

    if (widget.showAppBar) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('课程表'),
          centerTitle: true,
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

  Widget _buildFilters(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          AcademicYearPicker(
            startYear: 2018,
            endYear: 2030,
            initialYear: _selectedYear,
            onChanged: (y) {
              setState(() => _selectedYear = y);
              _syncTermContext(resetWeek: true);
              _loadData();
            },
          ),
          _semesterDropdown(context),
          _weekSwitcher(context),
        ],
      ),
    );
  }

  Widget _semesterDropdown(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedSemester,
        isDense: true,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        items: const [
          DropdownMenuItem(value: '0', child: Text('第一学期')),
          DropdownMenuItem(value: '1', child: Text('第二学期')),
          DropdownMenuItem(value: '2', child: Text('第二阶段')),
        ],
        onChanged: (v) {
          if (v != null) {
            setState(() => _selectedSemester = v);
            _syncTermContext(resetWeek: true);
            _loadData();
          }
        },
      ),
    );
  }

  /// 周次切换：`‹ 第 N 周 ›`，右侧按钮在「周视图 / 整学期」间切换。
  Widget _weekSwitcher(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = _week;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '上一周',
          visualDensity: VisualDensity.compact,
          onPressed: w == null
              ? null
              : () => setState(() => _week = w > 1 ? w - 1 : 1),
          icon: const Icon(Icons.chevron_left, size: 20),
        ),
        GestureDetector(
          onTap: () => setState(() => _week = _currentWeek ?? 1),
          child: Text(
            w == null ? '整学期' : '第 $w 周',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ),
        IconButton(
          tooltip: '下一周',
          visualDensity: VisualDensity.compact,
          onPressed: w == null ? null : () => setState(() => _week = w + 1),
          icon: const Icon(Icons.chevron_right, size: 20),
        ),
        if (_isCurrentTerm && _currentWeek != null && w != _currentWeek)
          TextButton(
            onPressed: () => setState(() => _week = _currentWeek),
            child: const Text('本周'),
          ),
        IconButton(
          tooltip: w == null ? '切换到周视图' : '切换到整学期视图',
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(
            () => _week = w == null ? (_currentWeek ?? 1) : null,
          ),
          icon: Icon(
            w == null ? Icons.view_week : Icons.grid_view,
            size: 18,
          ),
        ),
      ],
    );
  }

  void _toggleView() => setState(() => _isHorizontal = !_isHorizontal);

  Widget _buildBody() {
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

    // 切换按钮内置在课表左上角格子中
    return _isHorizontal
        ? ScheduleHorizontalView(
            entries: _entries!,
            reschedules: _reschedules,
            week: _week,
            weekMonday: _weekMonday,
            onTapClass: _onTapClass,
            onTapEmptySlot: _onTapEmptySlot,
            onToggle: _toggleView,
            isHorizontal: _isHorizontal,
          )
        : ScheduleGridView(
            entries: _entries!,
            reschedules: _reschedules,
            week: _week,
            weekMonday: _weekMonday,
            onTapClass: _onTapClass,
            onTapEmptySlot: _onTapEmptySlot,
            onToggle: _toggleView,
            isHorizontal: _isHorizontal,
          );
  }
}
