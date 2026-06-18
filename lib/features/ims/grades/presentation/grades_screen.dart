import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/grades/data/providers/grades_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grade.dart';

/// 成绩页面。
class GradesScreen extends ConsumerStatefulWidget {
  final bool showAppBar;

  const GradesScreen({super.key, this.showAppBar = true});

  @override
  ConsumerState<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends ConsumerState<GradesScreen> {
  TimeLimit _timeLimit = TimeLimit.semester;
  bool _showRawGrade = false;
  bool _selectMajor = true;
  bool _selectMinor = true;
  bool _selectWeiZhuan = true;
  bool _onlyNotPassed = false;
  String _semesterXq = '0';

  @override
  Widget build(BuildContext context) {
    return _wrapWithScaffold(
      Column(
        children: [
          _buildFilters(),
          Expanded(child: _buildGradeTable()),
        ],
      ),
    );
  }

  Widget _wrapWithScaffold(Widget child) {
    if (widget.showAppBar) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('成绩'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: _refresh,
            ),
          ],
        ),
        body: child,
      );
    }
    return child;
  }

  void _refresh() {
    ref.invalidate(_gradesProvider);
  }

  /// 主修/辅修/微专 至少选一个。
  void _onCategoryToggle(String category) {
    final count =
        (_selectMajor ? 1 : 0) +
        (_selectMinor ? 1 : 0) +
        (_selectWeiZhuan ? 1 : 0);
    setState(() {
      switch (category) {
        case 'major':
          if (_selectMajor && count <= 1) return;
          _selectMajor = !_selectMajor;
        case 'minor':
          if (_selectMinor && count <= 1) return;
          _selectMinor = !_selectMinor;
        case 'weizhuan':
          if (_selectWeiZhuan && count <= 1) return;
          _selectWeiZhuan = !_selectWeiZhuan;
      }
    });
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _dropdown<TimeLimit>(
            value: _timeLimit,
            items: TimeLimit.values,
            label: (t) => t.label,
            onChanged: (v) => setState(() => _timeLimit = v!),
          ),
          _dropdown<String>(
            value: _semesterXq,
            items: const ['0', '1', '2'],
            label: (s) => s == '0'
                ? '第一学期'
                : s == '1'
                ? '第二学期'
                : '第二阶段',
            onChanged: (v) => setState(() => _semesterXq = v!),
          ),
          _toggle('主修', _selectMajor, () => _onCategoryToggle('major')),
          _toggle('辅修', _selectMinor, () => _onCategoryToggle('minor')),
          _toggle('微专', _selectWeiZhuan, () => _onCategoryToggle('weizhuan')),
          _toggle(
            '仅未通过',
            _onlyNotPassed,
            () => setState(() => _onlyNotPassed = !_onlyNotPassed),
          ),
          _toggle(
            _showRawGrade ? '原始成绩' : '有效成绩',
            _showRawGrade,
            () => setState(() => _showRawGrade = !_showRawGrade),
            activeColor: Colors.red,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: '刷新',
            onPressed: _refresh,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) label,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        items: items
            .map((t) => DropdownMenuItem(value: t, child: Text(label(t))))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _toggle(
    String label,
    bool active,
    VoidCallback onTap, {
    Color? activeColor,
  }) {
    final color = active
        ? (activeColor ?? Theme.of(context).colorScheme.error)
        : Theme.of(context).colorScheme.surface;
    final fg = active
        ? Theme.of(context).colorScheme.onError
        : Theme.of(context).colorScheme.onSurface;
    return ActionChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: fg)),
      backgroundColor: color,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildGradeTable() {
    final resultAsync = ref.watch(_gradesProvider(_buildParams()));

    return resultAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$e', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(_gradesProvider),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
      data: (result) => result.grades.isEmpty
          ? const Center(child: Text('暂无成绩数据'))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildGradeTableWidget(result.grades),
                  if (result.summaries.isNotEmpty)
                    _buildSummaryTable(result.summaries),
                ],
              ),
            ),
    );
  }

  Widget _buildGradeTableWidget(List<Grade> grades) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicWidth(
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(theme.colorScheme.error),
              headingTextStyle: TextStyle(
                color: theme.colorScheme.onError,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              dataTextStyle: const TextStyle(fontSize: 13),
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('课程代码')),
                DataColumn(label: Text('课程名称')),
                DataColumn(label: Text('学分')),
                DataColumn(label: Text('类别')),
                DataColumn(label: Text('性质')),
                DataColumn(label: Text('考核')),
                DataColumn(label: Text('成绩')),
                DataColumn(label: Text('绩点')),
                DataColumn(label: Text('学分绩点')),
              ],
              rows: [
                for (final g in grades)
                  DataRow(
                    cells: [
                      DataCell(
                        Text(
                          g.courseCode,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      DataCell(
                        Text(
                          g.courseName,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      DataCell(Text(g.credit)),
                      DataCell(
                        Text(g.category, style: const TextStyle(fontSize: 11)),
                      ),
                      DataCell(Text(g.nature)),
                      DataCell(Text(g.examType)),
                      DataCell(Text(g.score)),
                      DataCell(Text(g.gradePoint)),
                      DataCell(Text(g.creditGradePoint)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryTable(List<GradeSummary> summaries) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicWidth(
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(theme.colorScheme.error),
              headingTextStyle: TextStyle(
                color: theme.colorScheme.onError,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              dataTextStyle: const TextStyle(fontSize: 12),
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('类别')),
                DataColumn(label: Text('环节数')),
                DataColumn(label: Text('学分')),
                DataColumn(label: Text('获得学分')),
                DataColumn(label: Text('绩点')),
                DataColumn(label: Text('学分绩点')),
                DataColumn(label: Text('平均绩点')),
              ],
              rows: summaries.map((s) {
                final isTotal = s.category == '合计';
                return DataRow(
                  color: isTotal
                      ? WidgetStateProperty.all(
                          theme.colorScheme.errorContainer,
                        )
                      : null,
                  cells: [
                    DataCell(
                      Text(
                        s.category,
                        style: TextStyle(
                          fontWeight: isTotal
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    DataCell(Text(s.courseCount)),
                    DataCell(Text(s.credit)),
                    DataCell(Text(s.earnedCredit)),
                    DataCell(Text(s.earnedGradePoint)),
                    DataCell(Text(s.earnedCreditGradePoint)),
                    DataCell(Text(s.avgGradePoint)),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  GradesQueryParams _buildParams() => GradesQueryParams(
    enrollYear: '2025',
    timeLimit: _timeLimit,
    showRawGrade: _showRawGrade,
    selectMajor: _selectMajor,
    selectMinor: _selectMinor,
    selectWeiZhuan: _selectWeiZhuan,
    onlyNotPassed: _onlyNotPassed,
    semesterXq: _timeLimit == TimeLimit.semester ? _semesterXq : null,
    academicYear: _timeLimit != TimeLimit.sinceEnrollment ? '2025' : null,
    academicYearNext: _timeLimit != TimeLimit.sinceEnrollment ? '2026' : null,
  );
}

final _gradesProvider = FutureProvider.family<GradesResult, GradesQueryParams>((
  ref,
  params,
) async {
  final repo = await ref.watch(gradesRepositoryProvider.future);
  final result = await repo.getGrades(params);
  return result.fold(
    (failure) => throw Exception(failure.message ?? '获取成绩失败'),
    (gradesResult) => gradesResult,
  );
});
