/// 「找无课时间」页 —— 从公共查询页里**独立出来**的共同空闲时间查询。
///
/// 用户 2026-09-19：「查无课时间的功能应该独立出来」→ 独立页面 + 首页磁贴。
/// 从前它是公共查询页里的一张内联卡（`_compareCard`），**只在「班级」类别下出现**，
/// 切到教室/教师/课程就整块消失；现在任何入口进来都是同一套完整流程。
///
/// 口径：
/// - 选 2 个以上班级 → 算出「这些班同时都没有课」的连续时段（引擎 = `domain/free_time.dart`）；
/// - 每换一个条件只在本页重算，**课表按班级各缓存一次**（provider family），不再重复请求；
/// - 筛选条件（校区 / 年级 / 学院 / 专业 / 培养层次）只用来**缩小「添加班级」的候选列表**，
///   真正决定结果的是「已选班级 + 教学周 + 最短连续 + 是否含周末」。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/providers/public_query_profile_provider.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/providers/public_query_providers.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query_defaults.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_timetable.dart';
import 'package:smarter_jxufe/features/ims/public_query/presentation/free_time_view.dart';
import 'package:smarter_jxufe/features/ims/public_query/presentation/public_query_option_sheet.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/teaching_week.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';
import 'package:smarter_jxufe/design/settings_section.dart';

/// 对照班级数的上限（再多也没有实际意义：3 个班同时空的时间很少，还会拉一堆报表）。
const int kFreeTimeMaxClasses = 6;

class FreeTimeScreen extends ConsumerStatefulWidget {
  const FreeTimeScreen({super.key, this.now});

  /// 注入「今天」，用于「周次默认当下教学周」的确定性断言（生产不传 = 真实时间）。
  final DateTime? now;

  @override
  ConsumerState<FreeTimeScreen> createState() => _FreeTimeScreenState();
}

class _FreeTimeScreenState extends ConsumerState<FreeTimeScreen> {
  late final DateTime _now = widget.now ?? DateTime.now();

  PublicQueryTerm? _term;
  String _campus = '';
  String _grade = '';
  String _department = '';
  String _major = '';
  String _trainLevel = '05';

  /// 参与对照的班级（多选，顺序即添加顺序）。
  final List<PublicQueryOption> _classes = [];

  late int _week;
  int _minPeriods = 1;
  bool _includeWeekend = false;

  /// 账号默认预填只做一次（之后尊重用户选择）。
  bool _profileApplied = false;

  late final PageAutoRefresher _refresher;

  @override
  void initState() {
    super.initState();
    final terms = ref.read(offlineSemesterTermsProvider);
    final teachingWeek = resolveTeachingWeek(_now, terms: terms);
    _week = teachingWeek != null && teachingWeek.week > 0
        ? teachingWeek.week
        : 1;
    _refresher = PageAutoRefresher(onRefresh: _refreshAll)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresher.subscribeRoute(context);
  }

  @override
  void dispose() {
    _refresher.dispose();
    super.dispose();
  }

  // ---------------- 数据 ----------------

  PublicQueryTerm? _effectiveTerm(List<PublicQueryTerm> terms) {
    if (_term != null) return _term;
    if (terms.isEmpty) return null;
    final resolve = currentSchoolTerm(_now, terms: ref.read(offlineSemesterTermsProvider));
    for (final t in terms) {
      if (t.matches(resolve.xn, resolve.xq)) return t;
    }
    return terms.first;
  }

  /// 「添加班级」用的候选列表请求（筛选条件只影响这个列表）。
  PublicQueryRequest? _comboRequest(PublicQueryTerm? term) {
    if (term == null) return null;
    if (_campus.isEmpty && _department.isEmpty && _major.isEmpty) return null;
    return PublicQueryRequest(
      kind: PublicQueryKind.klass,
      term: term,
      campusCode: _campus,
      departmentCode: _department,
      majorCode: _major,
      grade: _grade.isEmpty ? '${term.xn}' : _grade,
      trainLevel: _trainLevel,
    );
  }

  /// 某一个班的课表请求。
  PublicQueryRequest _classRequest(PublicQueryOption klass, PublicQueryTerm term) =>
      PublicQueryRequest(
        kind: PublicQueryKind.klass,
        term: term,
        campusCode: _campus,
        departmentCode: _department,
        majorCode: _major,
        classCode: klass.code,
        grade: _grade.isEmpty ? '${term.xn}' : _grade,
        trainLevel: _trainLevel,
      );

  /// 页面级刷新：条件类列表 + 已选班级的课表（顺序无关紧要，都是独立 provider）。
  void _refreshAll() {
    invalidateIfLoaded(ref, publicQueryTermsProvider);
    invalidateIfLoaded(ref, publicQueryCampusesProvider);
    invalidateIfLoaded(ref, publicQueryCollegesProvider(_grade));
    if (_department.isNotEmpty) {
      invalidateIfLoaded(ref, publicQueryMajorsProvider('$_grade|$_department'));
    }
    final term = _effectiveTerm(
      ref.read(publicQueryTermsProvider).valueOrNull ?? const [],
    );
    if (term == null) return;
    for (final klass in _classes) {
      invalidateIfLoaded(ref, publicQueryReportProvider(_classRequest(klass, term)));
    }
  }

  /// 账号默认预填（校区 / 年级 / 学院 / 专业）。
  ///
  /// 与公共查询页的 `_resolveAccountDefaults` 同口径（`publicQueryAccountProfileProvider`
  /// + `matchPublicQueryOption`），但**刻意不跨校区找班级**：本页班级由用户自己多选，
  /// 预填只帮他把范围缩到自己学院/专业，添加班级时列表里就是本专业的班。
  ///
  /// ⚠ 与「我的校区」预填同一个坑：**列表拿到才落闸**，否则首帧列表还没回来就白填一次。
  void _applyProfileDefaults({
    required PublicQueryAccountProfile? profile,
    required PublicQueryTerm? term,
    required List<PublicQueryOption> campuses,
    required bool campusesLoading,
    required List<PublicQueryOption> colleges,
    required bool collegesLoading,
    required List<PublicQueryOption> majors,
    required bool majorsRequested,
    required bool majorsLoading,
  }) {
    if (_profileApplied || profile == null || profile.isEmpty || term == null) {
      return;
    }
    // 预填是「校区 → 年级 → 学院 → 专业」四级依赖链：**每一级都要等它的列表落地**
    // 才能匹配，否则会拿空列表当「匹配不上」而提前落闸（实测：年级一改，
    // 学院 provider 换了 key 会短暂回到 loading，那时落闸就把专业永久漏掉）。
    if (campusesLoading || campuses.isEmpty) {
      _retryDefaultsNextFrame(loading: campusesLoading);
      return;
    }
    if (_campus.isEmpty) {
      final campus = matchPublicQueryOption(campuses, profile.campusName);
      if (campus != null) _campus = campus.code;
    }
    _grade = publicQueryGradeOf(profile.enrollYear, term.xn);
    if (collegesLoading) {
      _retryDefaultsNextFrame(loading: true);
      return;
    }
    final college = matchPublicQueryOption(colleges, profile.college);
    if (college != null) _department = college.code;
    // 这一帧刚填上「学院」时，专业 provider 的请求**还没发出去**（majorsAsync 为 null）
    // → 必须补一帧，否则会拿着空列表当成「匹配不上」而永久漏掉专业。
    if (_department.isNotEmpty && (!majorsRequested || majorsLoading)) {
      _retryDefaultsNextFrame(loading: true);
      return;
    }
    final major = matchPublicQueryOption(majors, profile.major);
    if (major != null) _major = major.code;
    _profileApplied = true;
  }

  /// 预填还差一级列表没回来 → 补一次重建（**只在 loading 时补**：
  /// provider 报错时直接落闸，免得每帧都重建）。
  void _retryDefaultsNextFrame({required bool loading}) {
    if (!loading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Future<List<T>> _loadOptions<T>(Future<List<T>> future) async {
    try {
      return await future;
    } catch (_) {
      return const [];
    }
  }

  // ---------------- 界面 ----------------

  @override
  Widget build(BuildContext context) {
    final termsAsync = ref.watch(publicQueryTermsProvider);
    final campusesAsync = ref.watch(publicQueryCampusesProvider);
    final terms = termsAsync.valueOrNull ?? const <PublicQueryTerm>[];
    final campuses = campusesAsync.valueOrNull ?? const <PublicQueryOption>[];
    final term = _effectiveTerm(terms);

    final collegesAsync = ref.watch(publicQueryCollegesProvider(_grade));
    final majorsAsync = _department.isEmpty
        ? null
        : ref.watch(publicQueryMajorsProvider('$_grade|$_department'));
    final colleges = collegesAsync.valueOrNull ?? const <PublicQueryOption>[];
    final majors = majorsAsync?.valueOrNull ?? const <PublicQueryOption>[];
    _applyProfileDefaults(
      profile: ref.watch(publicQueryAccountProfileProvider).valueOrNull,
      term: term,
      campuses: campuses,
      campusesLoading: campusesAsync.isLoading,
      colleges: colleges,
      collegesLoading: collegesAsync.isLoading,
      majors: majors,
      majorsRequested: majorsAsync != null,
      majorsLoading: majorsAsync?.isLoading ?? false,
    );

    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('找无课时间'),
        actions: _headerActions(),
        settingsSections: const [SettingsSection.imsSession, SettingsSection.publicQuery],
      ),
      body: PaneBody(
        actions: _headerActions(),
        padding: EdgeInsets.zero,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 64),
          children: [
            _classesCard(context, term),
            const SizedBox(height: 12),
            _filterCard(context, term, campuses, colleges, majors),
            const SizedBox(height: 12),
            _whenCard(context),
            const SizedBox(height: 12),
            ..._resultSection(context, term),
          ],
        ),
      ),
    );
  }

  List<Widget> _headerActions() => [
    IconButton(
      tooltip: '刷新课表数据',
      icon: const Icon(Icons.refresh),
      onPressed: _refreshAll,
    ),
  ];

  /// 「要对照的班级」卡：已选班级胶囊 + 添加入口。
  Widget _classesCard(BuildContext context, PublicQueryTerm? term) {
    return Card(
      elevation: 0,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            geCardTitle(
              context,
              text: '要对照的班级',
              accent: fp(context).cardAccent,
              trailing: TextButton.icon(
                key: const Key('freeTimeAddClass'),
                onPressed: _classes.length >= kFreeTimeMaxClasses
                    ? null
                    : () => _pickClasses(context, term),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加班级'),
              ),
            ),
            if (_classes.isEmpty)
              _hint(
                context,
                '把要一起排时间的几个班加进来（先按校区 / 学院 / 专业缩小范围，可跨班多选），'
                '会算出「这些班同时都没有课」的连续时段。',
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in _classes)
                    InputChip(
                      key: Key('freeTimeClassChip-${c.code}'),
                      label: Text(c.displayName),
                      onDeleted: () => setState(() => _classes.remove(c)),
                    ),
                ],
              ),
            if (_classes.length >= kFreeTimeMaxClasses)
              _hint(context, '最多对照 $kFreeTimeMaxClasses 个班 —— 再多就没有共同的空档了。'),
          ],
        ),
      ),
    );
  }

  /// 「筛选条件」卡：只影响「添加班级」的候选列表。
  Widget _filterCard(
    BuildContext context,
    PublicQueryTerm? term,
    List<PublicQueryOption> campuses,
    List<PublicQueryOption> colleges,
    List<PublicQueryOption> majors,
  ) {
    final years = [
      for (var y = (term?.xn ?? _now.year); y >= (term?.xn ?? _now.year) - 4; y--)
        '$y',
    ];
    return Card(
      elevation: 0,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            geCardTitle(
              context,
              text: '筛选条件',
              accent: fp(context).publicQuery,
            ),
            const SizedBox(height: 8),
            _rowShell(
              context,
              icon: Icons.event_note_outlined,
              label: '学期',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<PublicQueryTerm>(
                  key: const Key('freeTimeTerm'),
                  isExpanded: true,
                  value: term,
                  items: [
                    for (final t in ref
                            .watch(publicQueryTermsProvider)
                            .valueOrNull ??
                        const <PublicQueryTerm>[])
                      DropdownMenuItem(value: t, child: Text(t.name)),
                  ],
                  onChanged: (v) => setState(() {
                    _term = v;
                    _classes.clear();
                  }),
                ),
              ),
            ),
            _rowShell(
              context,
              icon: Icons.location_city_outlined,
              label: '校区',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('freeTimeCampus'),
                  isExpanded: true,
                  value: campuses.any((o) => o.code == _campus) ? _campus : '',
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部 / 不限')),
                    for (final o in campuses)
                      DropdownMenuItem(value: o.code, child: Text(o.displayName)),
                  ],
                  onChanged: (v) => setState(() {
                    _campus = v ?? '';
                    _classes.clear();
                  }),
                ),
              ),
            ),
            _rowShell(
              context,
              icon: Icons.school_outlined,
              label: '年级',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('freeTimeGrade'),
                  isExpanded: true,
                  value: years.contains(_grade) ? _grade : years.first,
                  items: [
                    for (final y in years)
                      DropdownMenuItem(value: y, child: Text('$y 级')),
                  ],
                  onChanged: (v) => setState(() {
                    _grade = v ?? years.first;
                    // 学院 / 专业都按年级取，年级一变必须清空下游。
                    _department = '';
                    _major = '';
                    _classes.clear();
                  }),
                ),
              ),
            ),
            _rowShell(
              context,
              icon: Icons.account_balance_outlined,
              label: '学院',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('freeTimeCollege'),
                  isExpanded: true,
                  value: colleges.any((o) => o.code == _department) ? _department : '',
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部 / 不限')),
                    for (final o in colleges)
                      DropdownMenuItem(value: o.code, child: Text(o.displayName)),
                  ],
                  onChanged: (v) => setState(() {
                    _department = v ?? '';
                    _major = '';
                    _classes.clear();
                  }),
                ),
              ),
            ),
            _rowShell(
              context,
              icon: Icons.local_library_outlined,
              label: '专业',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('freeTimeMajor'),
                  isExpanded: true,
                  value: majors.any((o) => o.code == _major) ? _major : '',
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部 / 不限')),
                    for (final o in majors)
                      DropdownMenuItem(value: o.code, child: Text(o.displayName)),
                  ],
                  onChanged: (v) => setState(() {
                    _major = v ?? '';
                    _classes.clear();
                  }),
                ),
              ),
            ),
            _rowShell(
              context,
              icon: Icons.workspace_premium_outlined,
              label: '培养层次',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('freeTimeTrainLevel'),
                  isExpanded: true,
                  value: _trainLevel,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('不限')),
                    for (final o
                        in ref
                                .watch(publicQueryTrainLevelsProvider)
                                .valueOrNull ??
                            const <PublicQueryOption>[])
                      DropdownMenuItem(value: o.code, child: Text(o.displayName)),
                    // 列表还没回来（或取不到）时给当前值兜一个条目，否则 DropdownButton 会断言失败。
                    if (_trainLevel.isNotEmpty &&
                        !(ref
                                    .watch(publicQueryTrainLevelsProvider)
                                    .valueOrNull ??
                                const <PublicQueryOption>[])
                            .any((o) => o.code == _trainLevel))
                      DropdownMenuItem(value: _trainLevel, child: const Text('本科')),
                  ],
                  onChanged: (v) => setState(() {
                    _trainLevel = v ?? '';
                    _classes.clear();
                  }),
                ),
              ),
            ),
            _hint(
              context,
              '这里只决定「添加班级」时能挑到哪些班（班级码与校区配套，选错校区会列不出班）。',
            ),
          ],
        ),
      ),
    );
  }

  /// 「时间条件」卡：周次 / 最短连续 / 含周末。
  Widget _whenCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            geCardTitle(
              context,
              text: '时间条件',
              accent: fp(context).publicQuery,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _rowShell(
                    context,
                    icon: Icons.calendar_view_week_outlined,
                    label: '教学周',
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        key: const Key('freeTimeWeek'),
                        isExpanded: true,
                        value: _week,
                        items: [
                          for (var w = 1; w <= 20; w++)
                            DropdownMenuItem(value: w, child: Text('第 $w 周')),
                        ],
                        onChanged: (v) => setState(() => _week = v ?? 1),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _rowShell(
                    context,
                    icon: Icons.timelapse_outlined,
                    label: '最短连续',
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        key: const Key('freeTimeMinPeriods'),
                        isExpanded: true,
                        value: _minPeriods,
                        items: [
                          for (var n = 1; n <= 4; n++)
                            DropdownMenuItem(value: n, child: Text('$n 节')),
                        ],
                        onChanged: (v) => setState(() => _minPeriods = v ?? 1),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              key: const Key('freeTimeIncludeWeekend'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _includeWeekend,
              onChanged: (v) => setState(() => _includeWeekend = v),
              title: const Text('把周末也算进来'),
            ),
          ],
        ),
      ),
    );
  }

  /// 结果区：各班的课表拉齐后交给 `FreeTimeView` 画周网格 + 空闲时段清单。
  List<Widget> _resultSection(BuildContext context, PublicQueryTerm? term) {
    if (_classes.isEmpty) {
      return [
        _noticeCard(
          context,
          Icons.group_add_outlined,
          '还没有选班级',
          '点上面「添加班级」挑 2 个以上班级，就能看到它们共同没有课的时间。',
        ),
      ];
    }
    if (term == null) {
      return [_loadingCard(context, '正在读取「已发布课表」的学年学期…')];
    }

    final columns = <PublicScheduleColumn>[];
    final failed = <String>[];
    var loading = 0;
    for (final klass in _classes) {
      final async = ref.watch(publicQueryReportProvider(_classRequest(klass, term)));
      final result = async.valueOrNull;
      if (result == null) {
        if (async.hasError) {
          failed.add(klass.displayName);
        } else {
          loading++;
        }
        continue;
      }
      columns.add(
        PublicScheduleColumn(
          owner: klass.displayName,
          slots: slotsOfTimetables(result.timetables, ownerOf: (_) => klass.displayName),
        ),
      );
    }

    return [
      if (loading > 0)
        _loadingCard(context, '正在拉取 $loading 个班的课表…（已就绪 ${columns.length} 个）'),
      if (failed.isNotEmpty)
        _noticeCard(
          context,
          Icons.error_outline,
          '${failed.length} 个班的课表没取到',
          '${failed.join('、')}：教务没返回数据（或会话失效）。点右上角刷新重试。',
        ),
      if (columns.isEmpty && loading == 0 && failed.isEmpty)
        _noticeCard(context, Icons.search_off, '没有可对照的班级', '这些班本学期可能没有排课。'),
      if (columns.isNotEmpty) ...[
        if (loading > 0 || failed.isNotEmpty) const SizedBox(height: 12),
        FreeTimeView(
          columns: columns,
          week: _week,
          maxPeriod: 12,
          includeWeekend: _includeWeekend,
          minPeriods: _minPeriods,
          periodStarts: const {},
        ),
      ],
    ];
  }

  // ---------------- 交互 ----------------

  Future<void> _pickClasses(BuildContext context, PublicQueryTerm? term) async {
    if (term == null) {
      _toast('学期还没读出来，稍等一下或点右上角刷新');
      return;
    }
    final request = _comboRequest(term);
    if (request == null) {
      _toast('先选「校区」或「学院」或「专业」，再添加要对照的班级');
      return;
    }
    final list = await _loadOptions(
      ref.read(publicQueryComboBoxProvider(request).future),
    );
    if (!context.mounted) return;
    if (list.isEmpty) {
      _toast('该条件下没有班级：换年级 / 学院 / 专业，或选校区');
      return;
    }
    final picked = await pickPublicQueryOptions(
      context,
      title: '选择要对照的班级（可多选）',
      options: list,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final o in picked) {
        if (_classes.length >= kFreeTimeMaxClasses) break;
        if (!_classes.any((c) => c.code == o.code)) _classes.add(o);
      }
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  // ---------------- 通用小组件 ----------------

  Widget _rowShell(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _hint(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        height: 1.5,
        color: AppColors.textMuted(context),
      ),
    ),
  );

  Widget _loadingCard(BuildContext context, String text) => Card(
    elevation: 0,
    shape: geCardShape(context),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted(context),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _noticeCard(
    BuildContext context,
    IconData icon,
    String title,
    String body,
  ) => Card(
    elevation: 0,
    shape: geCardShape(context),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textMuted(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AppColors.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
