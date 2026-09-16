/// 「网上选课」Tab —— 选课状态卡 + 检索条件 + 可选课程列表。
///
/// 检索栏按教务原页面 `student/wsxk.zx.html`（S2020202）复刻（2026-09-15）：
/// 课程范围（`kcfw`）/ 院(系)部（`sel_yxb`，仅「跨学期」显示）/ 年级专业（`njzy`）/
/// 课程（`kcmc`）/ 课程类别（`lbgl`）/ 课程属性（`kcsx`）/ 限未选满（`xwxmkc`）/ 检索。
/// 其中**类别与属性是客户端过滤**（原页面同样如此，见 `domain/selection_filters.dart`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/course_selection_repository.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/datasources/course_selection_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/providers/course_selection_providers.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_filters.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_models.dart';
import 'package:smarter_jxufe/features/ims/course_selection/presentation/course_section_sheet.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

/// 原页面 `QryData()` 里那句 `alert("需选定年级/专业！")` 的原文。
const String kSelectionNeedGradeMajorText = '需选定年级/专业！';

/// 原页面里会隐藏「年级/专业」的两个课程范围码（`changeCourseRange()`）。
const Set<String> kSelectionScopesWithoutGradeMajor = {'zxggrx', 'tspyggrx'};

/// 只有这个范围才显示「院(系)/部」。
const String kSelectionScopeCrossTerm = 'zxknj';

class SelectionOnlineView extends ConsumerStatefulWidget {
  const SelectionOnlineView({
    super.key,
    required this.channel,
    required this.onChannelChanged,
  });

  final SelectionChannel channel;
  final ValueChanged<SelectionChannel> onChannelChanged;

  @override
  ConsumerState<SelectionOnlineView> createState() =>
      _SelectionOnlineViewState();
}

class _SelectionOnlineViewState extends ConsumerState<SelectionOnlineView> {
  final TextEditingController _keywordController = TextEditingController();

  /// 已生效的检索条件（改「课程」输入框要点「检索」，其余控件即时生效）。
  String? _scope;
  String _keyword = '';
  String _njzy = '';
  String _department = '';
  bool _onlyWithVacancy = true;

  /// 客户端过滤（原页面 `ctyQryData` / `ctyQryData2`，不发请求、即时生效）。
  String _categoryKey = '';
  String _attribute = '';

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  /// 课程范围选项：优先教务下发的 `kcfw`/`kcfwmc`（原页面最终的形态），
  /// 取不到才回退 `MsKcfw` 下拉。
  List<CourseScope> _scopes(
    SelectionSession session,
    List<CourseScope> fallback,
  ) {
    final codes = session.scopeCodes;
    if (codes.isEmpty) return fallback;
    final names = session.scopeNames;
    return [
      for (var i = 0; i < codes.length; i++)
        CourseScope(
          code: codes[i],
          name: (i < names.length && names[i].isNotEmpty) ? names[i] : codes[i],
        ),
    ];
  }

  bool _showsGradeMajor(String scope) =>
      !kSelectionScopesWithoutGradeMajor.contains(scope);

  bool _showsDepartment(String scope) => scope == kSelectionScopeCrossTerm;

  /// 点「检索」（原页面 `btnQry` → `initQry=0` → `QryData()`）。
  void _search(String scope) {
    if (scope == kSelectionScopeCrossTerm && _njzy.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kSelectionNeedGradeMajorText)),
      );
      return;
    }
    setState(() => _keyword = _keywordController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final channel = widget.channel;
    final sessionAsync = ref.watch(selectionSessionProvider(channel));
    final session = sessionAsync.valueOrNull ?? SelectionSession.unknown;
    final scopesAsync = ref.watch(selectionScopeOptionsProvider(channel));
    final scopes = _scopes(session, scopesAsync.valueOrNull ?? const []);
    final scope = _scope ?? (scopes.isNotEmpty ? scopes.first.code : '');
    final effectiveScope = scope.isEmpty ? 'zxbnj' : scope;
    final gradeMajorOptions = _gradeMajorOptions(channel, effectiveScope);
    final gradeMajorLoading = _gradeMajorLoading(channel, effectiveScope);
    // 原页面 `njzy` 默认就是**本专业那一项**（下拉里唯一一项，等于已选）——
    // 教务接口在非跨学期范围只回这一条（实测 `2025|4405`）→ 我们也默认选中它，
    // 让「提交的 njzy」与「界面显示的年级/专业」一致。
    final njzy = (_njzy.isEmpty && gradeMajorOptions.isNotEmpty)
        ? gradeMajorOptions.first.code
        : _njzy;
    final query = OptionalCourseQuery(
      channel: channel,
      scope: effectiveScope,
      keyword: _keyword,
      njzy: njzy,
      department: _department,
      onlyWithVacancy: _onlyWithVacancy,
    );
    final coursesAsync = ref.watch(optionalCoursesProvider(query));
    final quotaAsync = ref.watch(selectionQuotaProvider(channel));

    final all = coursesAsync.valueOrNull?.courses ?? const <OptionalCourse>[];
    final filters = reconcileOptionalCourseFilters(
      all,
      categoryKey: _categoryKey,
      attribute: _attribute,
    );
    final filtered = filterOptionalCourses(
      all,
      categoryKey: filters.categoryKey,
      attribute: filters.attribute,
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(selectionSessionProvider(channel));
        ref.invalidate(selectionScopeOptionsProvider(channel));
        ref.invalidate(selectionDepartmentOptionsProvider(channel));
        ref.invalidate(selectionGradeMajorOptionsProvider);
        ref.invalidate(selectionQuotaProvider(channel));
        ref.invalidate(optionalCoursesProvider);
        await ref.read(optionalCoursesProvider(query).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 72),
        children: [
          _channelSwitch(channel),
          const SizedBox(height: 12),
          _statusCard(context, sessionAsync, session, quotaAsync.valueOrNull),
          const SizedBox(height: 12),
          _filterCard(
            context,
            channel: channel,
            scopes: scopes,
            scope: effectiveScope,
            courses: all,
            njzy: njzy,
            gradeMajorOptions: gradeMajorOptions,
            gradeMajorLoading: gradeMajorLoading,
            scheme: scheme,
          ),
          const SizedBox(height: 12),
          coursesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => _errorCard(context, '$error'),
            data: (result) => _courseList(
              context,
              result,
              filtered,
              session,
              channel,
              filters: filters,
            ),
          ),
        ],
      ),
    );
  }

  Widget _channelSwitch(SelectionChannel channel) {
    return SegmentedButton<SelectionChannel>(
      segments: const [
        ButtonSegment(
          value: SelectionChannel.plan,
          label: Text('按开课计划'),
          icon: Icon(Icons.list_alt_outlined, size: 18),
        ),
        ButtonSegment(
          value: SelectionChannel.crossGrade,
          label: Text('外年级/专业'),
          icon: Icon(Icons.public_outlined, size: 18),
        ),
      ],
      selected: {channel},
      showSelectedIcon: false,
      onSelectionChanged: (values) => widget.onChannelChanged(values.first),
    );
  }

  Widget _statusCard(
    BuildContext context,
    AsyncValue<SelectionSession> sessionAsync,
    SelectionSession session,
    SelectionQuota? quota,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final accent = FeaturePalette.cardAccent;
    return Card(
      elevation: 0,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(
              context,
              text: '选课状态',
              accent: accent,
              trailing: sessionAsync.isLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _openPill(context, session),
            ),
            const SizedBox(height: 10),
            if (session.xnxqDesc.isNotEmpty)
              Text(
                session.xnxqDesc,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (session.lcmc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  session.lcmc,
                  style: TextStyle(fontSize: 12.5, color: scheme.outline),
                ),
              ),
            if (session.windowLabel.isNotEmpty)
              _infoRow(
                context,
                Icons.event_available_outlined,
                session.windowLabel,
              ),
            if (session.dailyLabel.isNotEmpty)
              _infoRow(
                context,
                Icons.schedule_outlined,
                '每日 ${session.dailyLabel}',
              ),
            if (quota != null &&
                (quota.usedCredits != null || quota.totalCredits != null))
              _quotaRow(context, quota),
            if (session.kcfwmc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '可选范围：${session.kcfwmc}',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ),
            if (!session.ok && session.message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  session.message,
                  style: TextStyle(fontSize: 12.5, color: scheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _openPill(BuildContext context, SelectionSession session) {
    final scheme = Theme.of(context).colorScheme;
    final open = session.open;
    final color = open ? FeaturePalette.cardAccent : scheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        open ? '选课开放中' : '不在选课时间',
        style: TextStyle(
          fontSize: 11.5,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: scheme.outline),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
  }

  Widget _quotaRow(BuildContext context, SelectionQuota quota) {
    final scheme = Theme.of(context).colorScheme;
    final used = quota.usedCredits ?? 0;
    // ⚠ `zxf` / `zdxf` 是教务的**指定学分**（培养方案应修），**不是**选课上限：
    // 实测该生 zxf=25.5 而已选也是 25.5，但选课结果页写的「学分上限」是 26
    //（可选 0.5）→ 这里绝不能写成「上限 25.5」（2026-09-14 订正）。
    final limit = quota.specifiedCredits ?? quota.totalCredits;
    final ratio = (limit == null || limit <= 0)
        ? null
        : (used / limit).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '已选 ${geFmt(used)} 学分',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (quota.usedCount != null)
                Text(
                  ' · ${quota.usedCount!.round()} 门',
                  style: TextStyle(fontSize: 12.5, color: scheme.outline),
                ),
              const Spacer(),
              if (limit != null)
                Text(
                  '应修 ${geFmt(limit)}',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
            ],
          ),
          if (ratio != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(FeaturePalette.cardAccent),
                ),
              ),
            ),
          if (quota.feeText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                quota.feeText,
                style: TextStyle(fontSize: 11.5, color: scheme.outline),
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- 检索条件

  /// 年级/专业选项（`njzy`；原页面用 `CKDList` 级联拉，这里走同端点）。
  List<CourseScope> _gradeMajorOptions(SelectionChannel channel, String scope) {
    if (!_showsGradeMajor(scope)) return const [];
    return ref
            .watch(
              selectionGradeMajorOptionsProvider(
                GradeMajorQuery(
                  channel: channel,
                  scope: scope,
                  department: _department,
                ),
              ),
            )
            .valueOrNull ??
        const [];
  }

  bool _gradeMajorLoading(SelectionChannel channel, String scope) =>
      _showsGradeMajor(scope) &&
      ref
          .watch(
            selectionGradeMajorOptionsProvider(
              GradeMajorQuery(
                channel: channel,
                scope: scope,
                department: _department,
              ),
            ),
          )
          .isLoading;

  Widget _filterCard(
    BuildContext context, {
    required SelectionChannel channel,
    required List<CourseScope> scopes,
    required String scope,
    required List<OptionalCourse> courses,
    required String njzy,
    required List<CourseScope> gradeMajorOptions,
    required bool gradeMajorLoading,
    required ColorScheme scheme,
  }) {
    final categoryOptions = optionalCourseCategoryOptions(courses);
    final attributeOptions = optionalCourseAttributeOptions(courses);
    // 只在真的显示时取数（原页面也是这样：只有 `zxknj` 才调 `getkkxYxb()`）。
    final departmentAsync = _showsDepartment(scope)
        ? ref.watch(selectionDepartmentOptionsProvider(channel))
        : null;
    final departmentOptions =
        departmentAsync?.valueOrNull ?? const <CourseScope>[];

    return Card(
      elevation: 0,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(
              context,
              text: '检索条件',
              accent: FeaturePalette.cardAccent,
            ),
            const SizedBox(height: 8),
            // ── 课程范围（原页面 `select#kcfw`，切换即自动检索）
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final item in scopes)
                  ChoiceChip(
                    label: Text(item.name),
                    selected: item.code == scope,
                    onSelected: (_) => _applyScope(item.code),
                  ),
              ],
            ),
            if (scopes.isEmpty)
              Text(
                '课程范围加载中…',
                style: TextStyle(fontSize: 12.5, color: scheme.outline),
              ),
            // ── 院(系)/部（原页面 `span#sp_yxb` + `select#sel_yxb`，仅「跨学期」显示）
            if (_showsDepartment(scope))
              _dropdown(
                context,
                label: '院(系)/部',
                hint: departmentOptions.isEmpty
                    ? ((departmentAsync?.isLoading ?? false)
                          ? '（加载中…）'
                          : '（无可选项）')
                    : '（不限）',
                value: departmentOptions.any((e) => e.code == _department)
                    ? _department
                    : '',
                items: [
                  for (final item in departmentOptions)
                    DropdownMenuItem(value: item.code, child: Text(item.name)),
                ],
                onChanged: (value) => setState(() {
                  _department = value ?? '';
                  _njzy = '';
                }),
              ),
            // ── 年级/专业（原页面 `select#njzy`，`zxggrx`/`tspyggrx` 时隐藏）
            if (_showsGradeMajor(scope))
              _dropdown(
                context,
                label: '年级/专业',
                hint: gradeMajorOptions.isEmpty
                    ? (gradeMajorLoading ? '（加载中…）' : '（无可选项）')
                    : '（本专业）',
                value: gradeMajorOptions.any((e) => e.code == njzy) ? njzy : '',
                items: [
                  for (final item in gradeMajorOptions)
                    DropdownMenuItem(value: item.code, child: Text(item.name)),
                ],
                onChanged: gradeMajorOptions.isEmpty
                    ? null
                    : (value) => setState(() => _njzy = value ?? ''),
              ),
            // ── 课程（原页面 `input#kcmc`，title 原文照抄）
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _keywordController,
                      maxLength: 20,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        isDense: true,
                        counterText: '',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        hintText: '课程代码（前缀匹配）或课程名称（模糊匹配）',
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _search(scope),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed: () => _search(scope),
                      style: FilledButton.styleFrom(
                        backgroundColor: FeaturePalette.cardAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      child: const Text('检索'),
                    ),
                  ),
                ],
              ),
            ),
            // ── 课程类别 / 课程属性（原页面 `#lbgl` / `#kcsx`，客户端过滤）
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _dropdown(
                      context,
                      label: '课程类别',
                      dense: true,
                      hint: categoryOptions.isEmpty ? '（无）' : '（全部）',
                      value: categoryOptions.any((e) => e.key == _categoryKey)
                          ? _categoryKey
                          : '',
                      items: [
                        for (final item in categoryOptions)
                          DropdownMenuItem(
                            value: item.key,
                            child: Text(item.label),
                          ),
                      ],
                      onChanged: categoryOptions.isEmpty
                          ? null
                          : (value) =>
                                setState(() => _categoryKey = value ?? ''),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _dropdown(
                      context,
                      label: '课程属性',
                      dense: true,
                      hint: attributeOptions.isEmpty ? '（无）' : '（全部）',
                      value: attributeOptions.contains(_attribute)
                          ? _attribute
                          : '',
                      items: [
                        for (final item in attributeOptions)
                          DropdownMenuItem(value: item, child: Text(item)),
                      ],
                      onChanged: attributeOptions.isEmpty
                          ? null
                          : (value) => setState(() => _attribute = value ?? ''),
                    ),
                  ),
                ],
              ),
            ),
            // ── 限未选满的课程（原页面 `input#xwxmkc`，默认勾选）
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _onlyWithVacancy,
              onChanged: (value) =>
                  setState(() => _onlyWithVacancy = value ?? false),
              title: const Text('限未选满的课程', style: TextStyle(fontSize: 13)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '「课程类别 / 课程属性」在已取回的列表内筛选，不发新请求',
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 换课程范围 = 原页面 `changeCourseRange()`：立刻重查，并清空年级/专业
  /// （原页面会把 `njzy` 的选项清空重建）。
  void _applyScope(String code) {
    setState(() {
      _scope = code;
      _njzy = '';
      // 院系部只在「跨学期」有 UI；离开时清掉，避免残留把结果筛空。
      if (!_showsDepartment(code)) _department = '';
      _categoryKey = '';
      _attribute = '';
    });
  }

  Widget _dropdown(
    BuildContext context, {
    required String label,
    required String hint,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
    bool dense = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return DropdownButtonFormField<String>(
      initialValue: value.isEmpty ? null : value,
      isDense: true,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(fontSize: dense ? 12 : 13, color: scheme.outline),
        border: const OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: dense ? 8 : 12,
        ),
      ),
      style: TextStyle(fontSize: dense ? 12.5 : 13.5, color: scheme.onSurface),
      items: items,
      onChanged: onChanged,
    );
  }

  // ------------------------------------------------------------- 可选课程

  Widget _courseList(
    BuildContext context,
    ({List<OptionalCourse> courses, int? total}) result,
    List<OptionalCourse> filtered,
    SelectionSession session,
    SelectionChannel channel, {
    required ({String categoryKey, String attribute}) filters,
  }) {
    final scheme = Theme.of(context).colorScheme;
    if (filtered.isEmpty) {
      final filteredOut = result.courses.isNotEmpty;
      return Card(
        elevation: 0,
        shape: geCardShape(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
          child: Column(
            children: [
              Text(
                filteredOut
                    ? '当前「课程类别 / 课程属性」筛选下没有课程'
                    : (session.open ? '没有检索到记录！' : '不在选课时间，暂无可选课程'),
                style: TextStyle(fontSize: 13, color: scheme.outline),
              ),
              if (filteredOut)
                TextButton(
                  onPressed: () => setState(() {
                    _categoryKey = '';
                    _attribute = '';
                  }),
                  child: const Text('清除类别/属性筛选'),
                )
              else if (session.open && _onlyWithVacancy)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '已勾选「限未选满的课程」，取消勾选可看到已选满的课程',
                    style: TextStyle(fontSize: 11.5, color: scheme.outline),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final total = result.total ?? result.courses.length;
    final countText = filtered.length == result.courses.length
        ? '可选课程（$total）'
        : '可选课程（${filtered.length}/$total）';
    return Card(
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: geCardTitle(
              context,
              text: countText,
              accent: FeaturePalette.cardAccent,
            ),
          ),
          for (final course in filtered)
            _courseTile(context, course, session, channel),
        ],
      ),
    );
  }

  Widget _courseTile(
    BuildContext context,
    OptionalCourse course,
    SelectionSession session,
    SelectionChannel channel,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final details = <String>[
      if (course.courseCode.isNotEmpty) course.courseCode,
      if (course.credits != null) '${geFmt(course.credits!)} 学分',
      if (course.totalHours != null) '${course.totalHours} 学时',
      if (course.attribute.isNotEmpty) course.attribute,
      if (course.category.isNotEmpty) course.category,
      if (course.selectionMethod.isNotEmpty) course.selectionMethod,
    ];
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      title: Text(
        course.name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          details.join(' · '),
          style: TextStyle(fontSize: 12, color: scheme.outline),
        ),
      ),
      trailing: course.alreadySelected
          ? Text(
              '已选',
              style: TextStyle(
                fontSize: 12.5,
                color: FeaturePalette.cardAccent,
                fontWeight: FontWeight.w600,
              ),
            )
          : TextButton(
              onPressed: () => showCourseSectionSheet(
                context: context,
                ref: ref,
                channel: channel,
                course: course,
                session: session,
              ),
              child: const Text('选择'),
            ),
    );
  }

  Widget _errorCard(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '加载失败',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.error,
              ),
            ),
            const SizedBox(height: 6),
            Text(message, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => ref.invalidate(optionalCoursesProvider),
                child: const Text('重试'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
