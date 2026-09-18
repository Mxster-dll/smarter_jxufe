import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/providers/public_query_profile_provider.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/providers/public_query_providers.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query_defaults.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_timetable.dart';
import 'package:smarter_jxufe/features/ims/public_query/presentation/free_time_view.dart';
import 'package:smarter_jxufe/features/ims/public_query/presentation/public_timetable_view.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/teaching_week.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/settings/domain/settings_section.dart';

/// 教务「公共查询」聚合页：按课程 / 教师 / 班级 / 教室查课表，
/// 并可把多个班级拉到一起**对照出共同空闲时间**。
///
/// 口径与坑见 `reverse_engineering/公共查询接口.md` 与
/// `domain/public_query.dart` 的文件头注释（尤其「报告端点只认 urlencoded」那条）。
class PublicQueryScreen extends ConsumerStatefulWidget {
  const PublicQueryScreen({super.key});

  @override
  ConsumerState<PublicQueryScreen> createState() => _PublicQueryScreenState();
}

class _PublicQueryScreenState extends ConsumerState<PublicQueryScreen> {
  PublicQueryKind _kind = PublicQueryKind.klass;
  PublicQueryTerm? _term;
  String _campus = '';
  String _grade = '';
  String _department = '';
  String _building = '';

  /// 专业代码（班级课表的「专业」过滤；`MsYXB_Specialty` 的 `code`）。
  String _major = '';

  /// 培养层次（`DM-PYCC`；实测是真过滤条件，`05`=本科、空串=不限）。
  String _trainLevel = '05';

  PublicQueryOption? _teacher;
  PublicQueryOption? _course;
  PublicQueryOption? _roomEntry;

  /// 班级课表选中的单个班级（看课表用）。
  PublicQueryOption? _class;

  /// 多班对照选中的班级（找共同无课时间用）——允许含 [_class] 之外的班。
  final List<PublicQueryOption> _compareClasses = [];

  int _week = 1;
  int _minPeriods = 1;
  bool _includeWeekend = false;
  bool _showAllResults = false;

  /// 账号默认筛选（打开页面时解析一次；切回「班级 / 教室」时用它补齐被清空的项）。
  PublicQueryAccountDefaults? _accountDefaults;

  @override
  void initState() {
    super.initState();
    final resolve = currentSchoolTerm(
      DateTime.now(),
      terms: ref.read(offlineSemesterTermsProvider),
    );
    _grade = '${resolve.xn}';
    final teachingWeek = resolveTeachingWeek(
      DateTime.now(),
      terms: ref.read(offlineSemesterTermsProvider),
    );
    if (teachingWeek != null &&
        teachingWeek.term.matches(xn: resolve.xn, xq: resolve.xq) &&
        teachingWeek.week > 0) {
      _week = teachingWeek.week;
    }
    // 打开页面即按当前账号预填筛选条件（校区 / 年级 / 学院 / 专业 / 班级）。
    // 口径见 `domain/public_query_defaults.dart`；用户 2026-09-14 裁定
    // 「每次打开页面都重置成账号默认」——手动改过的值不跨次保留。
    unawaited(_applyAccountDefaults());
  }

  PublicQueryTerm? _effectiveTerm(List<PublicQueryTerm> terms) {
    if (_term != null) return _term;
    if (terms.isEmpty) return null;
    final resolve = currentSchoolTerm(
      DateTime.now(),
      terms: ref.read(offlineSemesterTermsProvider),
    );
    for (final t in terms) {
      if (t.matches(resolve.xn, resolve.xq)) return t;
    }
    return terms.first;
  }

  PublicQueryRequest? _buildRequest({PublicQueryOption? overrideClass}) {
    final terms = ref.read(publicQueryTermsProvider).valueOrNull ?? const [];
    final term = _effectiveTerm(terms);
    if (term == null) return null;
    return _requestWith(
      term: term,
      campus: _campus,
      department: _department,
      major: _major,
      classCode: overrideClass?.code ?? _class?.code ?? '',
      teacherCode: _teacher?.code ?? '',
      courseCode: _course?.code ?? '',
      building: _building,
      room: _kind == PublicQueryKind.classroom ? (_roomEntry?.code ?? '') : '',
      grade: _grade,
    );
  }

  /// 显式参数的请求构造。
  ///
  /// 账号默认值解析要**试多个校区**（班级码必须与校区配套），拿不到页面上还没落地的
  /// 字段，故把构造逻辑抽到这里；[_buildRequest] 只是它「按当前页面状态」的包装。
  PublicQueryRequest _requestWith({
    required PublicQueryTerm term,
    PublicQueryKind? kind,
    String campus = '',
    String department = '',
    String major = '',
    String classCode = '',
    String teacherCode = '',
    String courseCode = '',
    String building = '',
    String room = '',
    String grade = '',
  }) => PublicQueryRequest(
    kind: kind ?? _kind,
    term: term,
    campusCode: campus,
    departmentCode: department,
    majorCode: major,
    classCode: classCode,
    teacherCode: teacherCode,
    courseCode: courseCode,
    buildingCode: building,
    roomCode: room,
    grade: grade.isEmpty ? '${term.xn}' : grade,
    trainLevel: _trainLevel,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 卡片底色 = 主题里的**纯白**（`colorScheme.surface`，见 AGENTS.md §3「主题纯白」口径）。
    // Material 的 Card 默认取 `surfaceContainerLow`（#FAFAFA，略灰），本页要求纯白；
    // 改在 `CardTheme` 而不是逐个 `Card(`：本页与两个子视图（课表卡 / 空闲网格卡）的
    // 卡片一次命中，且各卡自带的 `geCardShape` outline 细边框仍在 → 白卡压纯白底仍有分界。
    return Theme(
      data: Theme.of(context).copyWith(
        cardTheme: Theme.of(context).cardTheme.copyWith(color: scheme.surface),
      ),
      child: _buildScreen(context, scheme),
    );
  }

  /// 原导航栏里的「刷新学期列表」。
  ///
  /// 整页模式进 `AppBar.actions`；侧栏内嵌模式（面板首路由）由 `PaneBody` 下沉到
  /// 内容首行 —— 用户 2026-09-16 裁定：面板顶部不留 chrome（见 AGENTS.md §19）。
  List<Widget> _headerActions() => [
    IconButton(
      tooltip: '刷新学期列表',
      icon: const Icon(Icons.refresh),
      onPressed: () {
        ref.invalidate(publicQueryTermsProvider);
        ref.invalidate(publicQueryCampusesProvider);
      },
    ),
  ];

  Widget _buildScreen(BuildContext context, ColorScheme scheme) {
    final termsAsync = ref.watch(publicQueryTermsProvider);

    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('公共查询'),
        actions: _headerActions(),
        settingsSections: const [SettingsSection.imsSession],
      ),
      body: PaneBody(
        actions: _headerActions(),
        padding: EdgeInsets.zero,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 64),
          children: [
            _kindCard(context),
            const SizedBox(height: 12),
            termsAsync.when(
              loading: () => _loadingCard(context, '正在读取「已发布课表」的学年学期…'),
              error: (e, _) => _errorCard(
                context,
                '学期列表加载失败：$e',
                onRetry: () => ref.invalidate(publicQueryTermsProvider),
              ),
              data: (terms) {
                if (terms.isEmpty) {
                  return _infoCard(
                    context,
                    Icons.event_busy_outlined,
                    '目前还没有已发布的课表信息',
                    '教务没有任何「已发布课表」的学年学期，公共查询暂时查不到数据。',
                  );
                }
                final effective = _effectiveTerm(terms);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _termCard(context, terms, effective),
                    const SizedBox(height: 12),
                    _filterCard(context, effective),
                  ],
                );
              },
            ),
            if (_kind == PublicQueryKind.klass) ...[
              const SizedBox(height: 12),
              // ⚠️ 班级课表**也要**显示结果区（曾用 `_kind != klass` 挡掉 →
              // 选了班级查出来只看到对照卡、看不到那张班的课表，用户报「查到了但看不到课表」）。
              _resultSection(context, scheme),
              const SizedBox(height: 12),
              _compareCard(context),
            ],
            if (_kind == PublicQueryKind.klass &&
                _compareClasses.isNotEmpty) ...[
              const SizedBox(height: 12),
              _freeTimeSection(context),
            ],
            if (_kind != PublicQueryKind.klass) ...[
              const SizedBox(height: 12),
              _resultSection(context, scheme),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------- 账号默认值 ----------------

  /// 解析账号默认筛选（学籍缓存 + 「我的校区」偏好 + 教务各层列表）。
  ///
  /// 任一步取不到只影响对应那一项（其余照填）；连学籍和校区偏好都没有 → 返回 null。
  ///
  /// 口径要点（详见 `domain/public_query_defaults.dart`）：
  /// - 年级用**学籍入学年**（`2025` 级），不是学年——学院/专业/班级列表都按 `nj` 分档；
  /// - 班级列表必须用**与班级配套的校区**取；「我的校区」对不上时逐个校区再试。
  Future<PublicQueryAccountDefaults?> _resolveAccountDefaults() async {
    final profile = await _loadProfile();
    if (!mounted || profile == null) return null;

    final terms = await _loadOptions(ref.read(publicQueryTermsProvider.future));
    if (!mounted) return null;
    final term = _effectiveTerm(terms);
    final grade = publicQueryGradeOf(
      profile.enrollYear,
      term?.xn ?? DateTime.now().year,
    );

    final campuses = await _loadOptions(
      ref.read(publicQueryCampusesProvider.future),
    );
    if (!mounted) return null;
    final colleges = await _loadOptions(
      ref.read(publicQueryCollegesProvider(grade).future),
    );
    if (!mounted) return null;
    final college = matchPublicQueryOption(colleges, profile.college);
    final majors = college == null
        ? const <PublicQueryOption>[]
        : await _loadOptions(
            ref.read(
              publicQueryMajorsProvider('$grade|${college.code}').future,
            ),
          );
    if (!mounted) return null;
    final major = matchPublicQueryOption(majors, profile.major);

    var campus = matchPublicQueryOption(campuses, profile.campusName);
    PublicQueryOption? klass;
    if (term != null && profile.className.isNotEmpty) {
      // 找班级分三步（班级码必须与校区配套，校区错了列表里没有这个班）：
      // ① 先按「我的校区」取；② 没命中就逐个校区试；③ 都没命中才退回「不限校区」。
      if (campus != null) {
        klass = await _findClassIn(
          term: term,
          grade: grade,
          campusCode: campus.code,
          collegeCode: college?.code ?? '',
          majorCode: major?.code ?? '',
          className: profile.className,
        );
        if (!mounted) return null;
      }
      if (klass == null) {
        for (final candidate in campuses) {
          if (candidate.code == campus?.code) continue;
          final found = await _findClassIn(
            term: term,
            grade: grade,
            campusCode: candidate.code,
            collegeCode: college?.code ?? '',
            majorCode: major?.code ?? '',
            className: profile.className,
          );
          if (!mounted) return null;
          if (found == null) continue;
          klass = found;
          campus = candidate;
          break;
        }
      }
      if (klass == null) {
        // 最后一步：不带校区过滤还能查到就填班级，但**校区留空**（不猜 ——
        // 报告允许 `selXQ` 空 + `selBJ` 精确查，班级与校区的配套关系没能确认）。
        final found = await _findClassIn(
          term: term,
          grade: grade,
          campusCode: '',
          collegeCode: college?.code ?? '',
          majorCode: major?.code ?? '',
          className: profile.className,
        );
        if (!mounted) return null;
        if (found != null) {
          klass = found;
          campus = null;
        }
      }
    }
    return PublicQueryAccountDefaults(
      grade: grade,
      campus: campus,
      college: college,
      major: major,
      klass: klass,
    );
  }

  /// 在指定校区下取班级列表并匹配学籍班级名（取不到 / 匹配不上返回 null）。
  Future<PublicQueryOption?> _findClassIn({
    required PublicQueryTerm term,
    required String grade,
    required String campusCode,
    required String collegeCode,
    required String majorCode,
    required String className,
  }) async {
    if (className.trim().isEmpty) return null;
    final options = await _loadOptions(
      ref.read(
        publicQueryComboBoxProvider(
          _requestWith(
            term: term,
            kind: PublicQueryKind.klass,
            campus: campusCode,
            department: collegeCode,
            major: majorCode,
            grade: grade,
          ),
        ).future,
      ),
    );
    return matchPublicQueryOption(options, className);
  }

  /// 账号侧匹配输入（学籍缓存 + 「我的校区」偏好，见
  /// `data/providers/public_query_profile_provider.dart`）。
  ///
  /// 取不到（未登录 / 未同步学籍 / 存储不可用）返回 null → 不做任何预填。
  Future<PublicQueryAccountProfile?> _loadProfile() async {
    try {
      final profile = await ref.read(publicQueryAccountProfileProvider.future);
      return profile.isEmpty ? null : profile;
    } catch (_) {
      return null;
    }
  }

  /// 打开页面时解析并**覆盖**筛选条件（用户裁定：每次进入都重置成账号默认）。
  Future<void> _applyAccountDefaults() async {
    final resolved = await _resolveAccountDefaults();
    if (!mounted || resolved == null) return;
    _accountDefaults = resolved;
    _restoreAccountDefaults(_kind);
  }

  /// 把已解析的账号默认值填进页面状态。
  ///
  /// [kind] 决定填哪些：校区对班级/教室两类都用；学院/专业/班级只属于班级课表
  /// （它们与教师课表的「部门」共用 `_department`，代码不可混用）。
  /// 只填「解析到了的」项，解析不到的保持原样。
  void _restoreAccountDefaults(PublicQueryKind kind) {
    final defaults = _accountDefaults;
    if (defaults == null) return;
    final usesCampus =
        kind == PublicQueryKind.klass || kind == PublicQueryKind.classroom;
    if (!usesCampus) return;
    setState(() {
      if (defaults.grade.isNotEmpty) _grade = defaults.grade;
      if (defaults.campus != null) {
        _campus = defaults.campus!.code;
        _building = '';
      }
      if (kind == PublicQueryKind.klass) {
        if (defaults.college != null) _department = defaults.college!.code;
        if (defaults.major != null) _major = defaults.major!.code;
        _class = defaults.klass;
      }
    });
  }

  // ---------------- 类别 ----------------

  Widget _kindCard(BuildContext context) {
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
              text: '查询方式',
              accent: fp(context).cardAccent,
            ),
            const SizedBox(height: 10),
            // 四个分段在 1280 宽下用全称会被裁剪 → 用短标签（值 = 完整标题在结果区展示）
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<PublicQueryKind>(
                segments: [
                  for (final k in PublicQueryKind.values)
                    ButtonSegment(
                      value: k,
                      label: Text(
                        k.shortTitle,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
                selected: {_kind},
                showSelectedIcon: false,
                onSelectionChanged: (values) {
                  setState(() {
                    _kind = values.first;
                    _showAllResults = false;
                    // 类别专属选择一律清空：`_department` 在班级课表是「学院」、
                    // 在教师课表是「部门」，两套代码不可混用（留着必然查空）。
                    _department = '';
                    _major = '';
                    _class = null;
                    _compareClasses.clear();
                    _teacher = null;
                    _course = null;
                    _roomEntry = null;
                  });
                  // 切回「班级 / 教室」时把账号默认值补回来（上面刚清空过专属选择）。
                  _restoreAccountDefaults(values.first);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _termCard(
    BuildContext context,
    List<PublicQueryTerm> terms,
    PublicQueryTerm? effective,
  ) {
    return Card(
      elevation: 0,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Icon(
              Icons.event_note_outlined,
              size: 20,
              color: fp(context).cardAccent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<PublicQueryTerm>(
                  isExpanded: true,
                  value: effective,
                  items: [
                    for (final t in terms)
                      DropdownMenuItem(value: t, child: Text(t.name)),
                  ],
                  onChanged: (v) => setState(() {
                    _term = v;
                    _teacher = null;
                    _course = null;
                    _class = null;
                    _roomEntry = null;
                    _compareClasses.clear();
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 过滤条件 ----------------

  Widget _filterCard(BuildContext context, PublicQueryTerm? term) {
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
              accent: fp(context).cardAccent,
            ),
            const SizedBox(height: 8),
            ..._filterRows(context, term),
          ],
        ),
      ),
    );
  }

  List<Widget> _filterRows(BuildContext context, PublicQueryTerm? term) {
    final campuses = ref.watch(publicQueryCampusesProvider);
    switch (_kind) {
      case PublicQueryKind.course:
        return [
          _pickerRow(
            context,
            icon: Icons.menu_book_outlined,
            label: '课程',
            value: _course?.displayName ?? '',
            hint: '选择课程',
            onTap: term == null ? null : () => _pickFromComboBox(context, term),
          ),
          _hint(context, '课程课表按「课程」汇总全校该课程的所有上课安排（含教师、班级、教室）。'),
        ];
      case PublicQueryKind.teacher:
        return [
          _pickerRow(
            context,
            icon: Icons.account_balance_outlined,
            label: '部门（可选）',
            value: _departmentLabel(context),
            hint: '不限部门',
            onTap: () => _pickDepartment(context),
          ),
          _pickerRow(
            context,
            icon: Icons.person_outline,
            label: '教师',
            value: _teacher?.name ?? '',
            hint: '选择教师',
            onTap: term == null ? null : () => _pickFromComboBox(context, term),
          ),
          _hint(context, '教师课表 = 该教师本学期承担的全部教学任务与时间地点。'),
        ];
      case PublicQueryKind.klass:
        final colleges = ref.watch(publicQueryCollegesProvider(_grade));
        // 专业列表按「年级 + 学院」取；没选学院时不发请求（`dwh` 为空没意义）。
        final majors = _department.isEmpty
            ? AsyncValue<List<PublicQueryOption>>.data(
                const <PublicQueryOption>[],
              )
            : ref.watch(publicQueryMajorsProvider('$_grade|$_department'));
        return [
          _campusRow(context, campuses),
          _gradeRow(context, term),
          _trainLevelRow(context),
          _collegeRow(context, colleges),
          _majorRow(context, majors),
          _pickerRow(
            context,
            icon: Icons.groups_outlined,
            label: '班级（可选）',
            // 用 displayName 剥掉 `[2508090D52]` 前缀（与课程 / 教室行一致；
            // 账号预填的班级会直接显示在这里，别把内部班级码暴露出来）。
            value: _class?.displayName ?? '',
            hint: '选择班级',
            onTap: term == null ? null : () => _pickFromComboBox(context, term),
          ),
          _hint(
            context,
            '四档过滤任选其一即可查：班级 > 专业 > 学院 > 校区（越靠前越精确）。'
            '选了校区请确保班级属于该校区，否则教务会返回「没有检索到记录」。',
          ),
        ];
      case PublicQueryKind.classroom:
        return [
          _campusRow(context, campuses),
          _buildingRow(context),
          _pickerRow(
            context,
            icon: Icons.meeting_room_outlined,
            label: '教室（可选）',
            value: _roomEntry?.displayName ?? '',
            hint: '不选 = 整栋楼 / 整个校区',
            onTap: term == null || _campus.isEmpty
                ? null
                : () => _pickFromComboBox(context, term),
          ),
          _hint(context, '不选具体教室时返回所选楼房（或整个校区）全部教室的课表，数据较多、耗时略长。'),
        ];
    }
  }

  Widget _campusRow(
    BuildContext context,
    AsyncValue<List<PublicQueryOption>> campuses,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: campuses.when(
        loading: () => _rowShell(
          context,
          icon: Icons.location_city_outlined,
          label: '校区',
          child: const Text('加载中…'),
        ),
        error: (e, _) => _rowShell(
          context,
          icon: Icons.location_city_outlined,
          label: '校区',
          child: Text(
            '加载失败',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        data: (list) => _rowShell(
          context,
          icon: Icons.location_city_outlined,
          label: '校区',
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: list.any((o) => o.code == _campus) ? _campus : '',
              items: [
                const DropdownMenuItem(value: '', child: Text('全部 / 不限')),
                for (final o in list)
                  DropdownMenuItem(value: o.code, child: Text(o.displayName)),
              ],
              onChanged: (v) => setState(() {
                _campus = v ?? '';
                _building = '';
                _class = null;
                _roomEntry = null;
                _compareClasses.clear();
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _gradeRow(BuildContext context, PublicQueryTerm? term) {
    final base = term?.xn ?? DateTime.now().year;
    final years = [for (var y = base; y >= base - 4; y--) '$y'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _rowShell(
        context,
        icon: Icons.school_outlined,
        label: '年级',
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: years.contains(_grade) ? _grade : years.first,
            items: [
              for (final y in years)
                DropdownMenuItem(value: y, child: Text('$y 级')),
            ],
            onChanged: (v) => setState(() {
              _grade = v ?? years.first;
              // 学院 / 专业列表都按年级（`nj`）取，年级一变必须清空下游选择。
              _department = '';
              _major = '';
              _class = null;
              _compareClasses.clear();
            }),
          ),
        ),
      ),
    );
  }

  /// 培养层次（`MsCodeset` + `DM-PYCC`）。实测 `05`=本科命中、`02`=统招本科查空、空=不限。
  Widget _trainLevelRow(BuildContext context) {
    final list =
        ref.watch(publicQueryTrainLevelsProvider).valueOrNull ??
        const <PublicQueryOption>[];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _rowShell(
        context,
        icon: Icons.workspace_premium_outlined,
        label: '培养层次',
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: _trainLevel,
            items: [
              const DropdownMenuItem(value: '', child: Text('不限')),
              for (final o in list)
                DropdownMenuItem(value: o.code, child: Text(o.displayName)),
              // 列表还没回来（或取不到）时给当前值兜一个条目，否则 DropdownButton 会断言失败
              if (_trainLevel.isNotEmpty &&
                  !list.any((o) => o.code == _trainLevel))
                DropdownMenuItem(
                  value: _trainLevel,
                  child: Text('层次 $_trainLevel'),
                ),
            ],
            onChanged: (v) => setState(() {
              _trainLevel = v ?? '';
              _showAllResults = false;
            }),
          ),
        ),
      ),
    );
  }

  /// 学院（班级课表的 `selYXB`，选项值 = 学院代码 `dwh`）。
  Widget _collegeRow(
    BuildContext context,
    AsyncValue<List<PublicQueryOption>> colleges,
  ) => _pickerRow(
    context,
    icon: Icons.account_balance_outlined,
    label: '学院（可选）',
    value: _labelOf(colleges.valueOrNull, _department),
    hint: '不限学院',
    onTap: () => _pickCollege(context),
  );

  /// 专业（班级课表的 `selZY`，选项值 = 专业代码 `zydm`）；未选学院时不可点。
  Widget _majorRow(
    BuildContext context,
    AsyncValue<List<PublicQueryOption>> majors,
  ) => _pickerRow(
    context,
    icon: Icons.menu_book_outlined,
    label: '专业（可选）',
    value: _labelOf(majors.valueOrNull, _major),
    hint: _department.isEmpty ? '先选学院' : '不限专业',
    onTap: _department.isEmpty ? null : () => _pickMajor(context),
  );

  /// 在候选列表里把代码翻成显示名；查不到就回退显示代码本身。
  String _labelOf(List<PublicQueryOption>? list, String code) {
    if (code.isEmpty) return '';
    for (final o in list ?? const <PublicQueryOption>[]) {
      if (o.code == code) return o.displayName;
    }
    return code;
  }

  PublicQueryOption? _optionOf(List<PublicQueryOption> list, String code) {
    for (final o in list) {
      if (o.code == code) return o;
    }
    return null;
  }

  Widget _buildingRow(BuildContext context) {
    if (_campus.isEmpty) {
      return _hint(context, '选择校区后可按楼房缩小范围（不选楼房则查该校区全部教室）。');
    }
    final buildings = ref.watch(publicQueryBuildingsProvider(_campus));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: buildings.when(
        loading: () => _rowShell(
          context,
          icon: Icons.apartment_outlined,
          label: '楼房',
          child: const Text('加载中…'),
        ),
        error: (e, _) => _rowShell(
          context,
          icon: Icons.apartment_outlined,
          label: '楼房',
          child: Text(
            '加载失败',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        data: (list) => _rowShell(
          context,
          icon: Icons.apartment_outlined,
          label: '楼房',
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: list.any((o) => o.code == _building) ? _building : '',
              items: [
                const DropdownMenuItem(value: '', child: Text('全部楼房')),
                for (final o in list)
                  DropdownMenuItem(value: o.code, child: Text(o.displayName)),
              ],
              onChanged: (v) => setState(() {
                _building = v ?? '';
                _roomEntry = null;
              }),
            ),
          ),
        ),
      ),
    );
  }

  String _departmentLabel(BuildContext context) {
    if (_department.isEmpty) return '';
    final list =
        ref.read(publicQueryDepartmentsProvider).valueOrNull ?? const [];
    for (final o in list) {
      if (o.code == _department) return o.displayName;
    }
    return _department;
  }

  Future<void> _pickDepartment(BuildContext context) async {
    final list = await _loadOptions(
      ref.read(publicQueryDepartmentsProvider.future),
    );
    if (!context.mounted) return;
    if (list.isEmpty) {
      _toast('部门列表暂时取不到');
      return;
    }
    final picked = await _pickOption(context, '选择部门', list, null);
    if (picked == null) return;
    setState(() {
      _department = picked.code;
      _teacher = null;
    });
  }

  /// 选学院（列表按年级 `nj` 取）。换学院必须清掉专业与班级——专业列表由学院决定。
  Future<void> _pickCollege(BuildContext context) async {
    final list = await _loadOptions(
      ref.read(publicQueryCollegesProvider(_grade).future),
    );
    if (!context.mounted) return;
    if (list.isEmpty) {
      _toast('该年级没有取到学院列表，请换年级后重试');
      return;
    }
    final picked = await _pickOption(
      context,
      '选择学院',
      list,
      _optionOf(list, _department),
    );
    if (picked == null) return;
    setState(() {
      _department = picked.code;
      _major = '';
      _class = null;
      _compareClasses.clear();
      _showAllResults = false;
    });
  }

  /// 选专业（列表按「年级 + 学院」取，`MsYXB_Specialty`）。
  Future<void> _pickMajor(BuildContext context) async {
    if (_department.isEmpty) {
      _toast('请先选择学院');
      return;
    }
    final list = await _loadOptions(
      ref.read(publicQueryMajorsProvider('$_grade|$_department').future),
    );
    if (!context.mounted) return;
    if (list.isEmpty) {
      _toast('该学院在该年级没有取到专业列表');
      return;
    }
    final picked = await _pickOption(
      context,
      '选择专业',
      list,
      _optionOf(list, _major),
    );
    if (picked == null) return;
    setState(() {
      _major = picked.code;
      _class = null;
      _compareClasses.clear();
      _showAllResults = false;
    });
  }

  Future<void> _pickFromComboBox(
    BuildContext context,
    PublicQueryTerm term,
  ) async {
    final request = _buildRequest()?.copyWith(term: term);
    if (request == null) return;
    // 教室走 `MsSchoolArea_LF_JS` 下拉（CombBox 的 jxap_combbox_js 在按楼房过滤时恒空）
    final future = _kind == PublicQueryKind.classroom
        ? ref.read(publicQueryClassroomsProvider('$_campus|$_building').future)
        : ref.read(publicQueryComboBoxProvider(request).future);
    final list = await _loadOptions(future);
    if (!context.mounted) return;
    if (list.isEmpty) {
      _toast(switch (_kind) {
        PublicQueryKind.klass => '该条件下没有班级：换年级 / 学院 / 专业，或清空这些过滤',
        PublicQueryKind.classroom => '该校区下没有取到教室列表：请先选校区',
        _ => '候选项为空，请调整筛选条件后重试',
      });
      return;
    }
    final picked = await _pickOption(
      context,
      switch (_kind) {
        PublicQueryKind.course => '选择课程',
        PublicQueryKind.teacher => '选择教师',
        PublicQueryKind.klass => '选择班级',
        PublicQueryKind.classroom => '选择教室',
      },
      list,
      switch (_kind) {
        PublicQueryKind.course => _course,
        PublicQueryKind.teacher => _teacher,
        PublicQueryKind.klass => _class,
        PublicQueryKind.classroom => _roomEntry,
      },
    );
    if (picked == null) return;
    setState(() {
      switch (_kind) {
        case PublicQueryKind.course:
          _course = picked;
        case PublicQueryKind.teacher:
          _teacher = picked;
        case PublicQueryKind.klass:
          _class = picked;
        case PublicQueryKind.classroom:
          _roomEntry = picked;
      }
      _showAllResults = false;
    });
  }

  // ---------------- 结果 ----------------

  Widget _resultSection(BuildContext context, ColorScheme scheme) {
    final request = _buildRequest();
    if (request == null) {
      return _infoCard(context, Icons.hourglass_empty, '等待学期信息', '学期列表还没就绪。');
    }
    if (!request.ready) {
      return _infoCard(
        context,
        Icons.filter_alt_outlined,
        '还差筛选条件',
        switch (_kind) {
          PublicQueryKind.course => '请先选择要查询的课程。',
          PublicQueryKind.teacher => '请先选择教师。',
          PublicQueryKind.klass => '请先选择校区与班级。',
          PublicQueryKind.classroom => '请先选择校区。',
        },
      );
    }
    final async = ref.watch(publicQueryReportProvider(request));
    return async.when(
      loading: () => _loadingCard(context, '正在向教务查询课表…（教室课表数据量大，可能需要十几秒）'),
      error: (e, _) => _errorCard(
        context,
        '查询失败：$e',
        onRetry: () => ref.invalidate(publicQueryReportProvider(request)),
      ),
      data: (result) {
        if (result.isEmpty) {
          return _infoCard(
            context,
            Icons.search_off,
            '没有检索到记录',
            '教务返回空结果。常见原因：所选班级与校区不匹配、该学期课表尚未发布，'
                '或这门课/这位教师本学期没有排课。',
          );
        }
        final all = result.timetables;
        final shown = _showAllResults ? all : all.take(20).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '查询到 ${all.length} 个${_kind.ownerLabel}的课表'
                      '${all.length > shown.length ? '（先显示前 ${shown.length} 个）' : ''}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final t in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PublicTimetableCard(timetable: t),
              ),
            if (all.length > shown.length)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showAllResults = true),
                  icon: const Icon(Icons.unfold_more, size: 18),
                  label: Text('显示其余 ${all.length - shown.length} 个'),
                ),
              ),
          ],
        );
      },
    );
  }

  // ---------------- 多班对照找无课时间 ----------------

  Widget _compareCard(BuildContext context) {
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
              text: '多班对照 · 找共同无课时间',
              accent: fp(context).cardAccent,
              trailing: TextButton.icon(
                onPressed: _kind == PublicQueryKind.klass
                    ? () => _pickCompareClasses(context)
                    : null,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加班级'),
              ),
            ),
            if (_compareClasses.isEmpty)
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
                  for (final c in _compareClasses)
                    InputChip(
                      label: Text(c.displayName),
                      onDeleted: () =>
                          setState(() => _compareClasses.remove(c)),
                    ),
                ],
              ),
            if (_compareClasses.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _rowShell(
                      context,
                      icon: Icons.calendar_view_week_outlined,
                      label: '教学周',
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
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
                          isExpanded: true,
                          value: _minPeriods,
                          items: [
                            for (var n = 1; n <= 4; n++)
                              DropdownMenuItem(value: n, child: Text('$n 节')),
                          ],
                          onChanged: (v) =>
                              setState(() => _minPeriods = v ?? 1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _includeWeekend,
                onChanged: (v) => setState(() => _includeWeekend = v),
                title: const Text('把周末也算进来'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _freeTimeSection(BuildContext context) {
    // 每个班一个请求（provider family 会各自缓存）
    final columns = <PublicScheduleColumn>[];
    var loading = 0;
    for (final c in _compareClasses) {
      final request = _buildRequest(overrideClass: c);
      if (request == null) continue;
      final async = ref.watch(publicQueryReportProvider(request));
      final result = async.valueOrNull;
      if (result == null) {
        loading++;
        continue;
      }
      columns.add(
        PublicScheduleColumn(
          owner: c.displayName,
          slots: slotsOfTimetables(
            result.timetables,
            ownerOf: (_) => c.displayName,
          ),
        ),
      );
    }
    if (columns.isEmpty) {
      return _loadingCard(context, '正在拉取 ${_compareClasses.length} 个班的课表…');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '还有 $loading 个班的课表在加载…',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        FreeTimeView(
          columns: columns,
          week: _week,
          maxPeriod: 12,
          includeWeekend: _includeWeekend,
          minPeriods: _minPeriods,
          periodStarts: const {},
        ),
      ],
    );
  }

  Future<void> _pickCompareClasses(BuildContext context) async {
    final term = _effectiveTerm(
      ref.read(publicQueryTermsProvider).valueOrNull ?? const [],
    );
    if (term == null) return;
    // 校区不再是硬条件：年级 / 学院 / 专业任一非空也能列出班级（实测都可查）。
    if (_campus.isEmpty && _department.isEmpty && _major.isEmpty) {
      _toast('先选「校区」或「学院」或「专业」，再添加要对照的班级');
      return;
    }
    final request = _buildRequest()?.copyWith(term: term);
    if (request == null) return;
    final list = await _loadOptions(
      ref.read(publicQueryComboBoxProvider(request).future),
    );
    if (!context.mounted) return;
    if (list.isEmpty) {
      _toast('该条件下没有班级：换年级 / 学院 / 专业，或选校区');
      return;
    }
    final picked = await _pickOptions(context, '选择要对照的班级（可多选）', list);
    if (picked.isEmpty) return;
    setState(() {
      for (final o in picked) {
        if (!_compareClasses.any((c) => c.code == o.code)) {
          _compareClasses.add(o);
        }
      }
    });
  }

  // ---------------- 通用小组件 ----------------

  Widget _rowShell(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
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
    );
  }

  Widget _pickerRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String hint,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _rowShell(
          context,
          icon: icon,
          label: label,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value.isEmpty ? hint : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: value.isEmpty ? scheme.onSurfaceVariant : null,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hint(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _loadingCard(BuildContext context, String text) => Card(
    elevation: 0,
    shape: geCardShape(context),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );

  Widget _errorCard(
    BuildContext context,
    String text, {
    required VoidCallback onRetry,
  }) => Card(
    elevation: 0,
    shape: geCardShape(context),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 20,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onRetry, child: const Text('重试')),
          ),
        ],
      ),
    ),
  );

  Widget _infoCard(
    BuildContext context,
    IconData icon,
    String title,
    String message,
  ) => Card(
    elevation: 0,
    shape: geCardShape(context),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 等一个列表落地（失败返回空表，由调用方提示 / 留空）。
  ///
  /// 泛型是为了让账号默认值解析也能复用它（学期列表不是 `PublicQueryOption`）。
  Future<List<T>> _loadOptions<T>(Future<List<T>> future) async {
    try {
      return await future;
    } catch (_) {
      return const [];
    }
  }

  Future<PublicQueryOption?> _pickOption(
    BuildContext context,
    String title,
    List<PublicQueryOption> options,
    PublicQueryOption? selected,
  ) async {
    final picked = await _pickOptions(context, title, options, single: true);
    return picked.isEmpty ? null : picked.first;
  }

  /// 可搜索的选择面板（长列表：教师 5000+ / 课程 1000+ / 班级 1000+）。
  Future<List<PublicQueryOption>> _pickOptions(
    BuildContext context,
    String title,
    List<PublicQueryOption> options, {
    bool single = false,
  }) async {
    final result = await showModalBottomSheet<List<PublicQueryOption>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) =>
          _OptionSheet(title: title, options: options, single: single),
    );
    return result ?? const [];
  }
}

/// 可搜索的选择面板。
class _OptionSheet extends StatefulWidget {
  final String title;
  final List<PublicQueryOption> options;
  final bool single;

  const _OptionSheet({
    required this.title,
    required this.options,
    required this.single,
  });

  @override
  State<_OptionSheet> createState() => _OptionSheetState();
}

class _OptionSheetState extends State<_OptionSheet> {
  final _controller = TextEditingController();
  final _selected = <String>{};
  String _keyword = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<PublicQueryOption> get _filtered {
    final key = _keyword.trim().toLowerCase();
    if (key.isEmpty) return widget.options;
    return widget.options
        .where(
          (o) =>
              o.name.toLowerCase().contains(key) ||
              o.code.toLowerCase().contains(key),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = _filtered;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.title}（共 ${widget.options.length} 项'
                    '${list.length == widget.options.length ? '' : ' · 命中 ${list.length}'}）',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!widget.single)
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () {
                            final picked = widget.options
                                .where((o) => _selected.contains(o.code))
                                .toList();
                            Navigator.of(context).pop(picked);
                          },
                    child: Text('确定（${_selected.length}）'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _controller,
              autofocus: false,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: '输入名称或代码搜索',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _keyword = v),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      '没有匹配项',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final o = list[i];
                      final checked = _selected.contains(o.code);
                      return ListTile(
                        dense: true,
                        selected: checked,
                        leading: widget.single
                            ? null
                            : Checkbox(
                                value: checked,
                                onChanged: (_) => setState(() {
                                  if (checked) {
                                    _selected.remove(o.code);
                                  } else {
                                    _selected.add(o.code);
                                  }
                                }),
                              ),
                        title: Text(o.displayName),
                        subtitle: o.bracketCode.isEmpty
                            ? null
                            : Text(
                                o.bracketCode,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                        onTap: () => Navigator.of(
                          context,
                        ).pop(widget.single ? [o] : null),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
