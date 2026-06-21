import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/grades/data/providers/grades_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grade.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grade_summary.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_query_params.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_result.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/time_limit.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/grades_viewmodel.dart';

  // TODO 拆分futureBuilder （最细到每一个表格单元格）
class GradesScreen extends ConsumerWidget {
  final bool showAppBar;

  const GradesScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _wrapWithScaffold(
      context,
      ref,
      Column(
        children: [
          _buildFilters(context, ref),
          Expanded(child: _buildGradeTable(context, ref)),
        ],
      ),
    );
  }

  Widget _wrapWithScaffold(BuildContext context, WidgetRef ref, Widget child) {
    if (showAppBar) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('成绩'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: () => ref.invalidate(_gradesProvider),
            ),
          ],
        ),
        body: child,
      );
    }
    return child;
  }

  Widget _buildFilters(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(gradesViewModelProvider.notifier);
    final state = ref.watch(gradesViewModelProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _dropdown<TimeLimit>(
            context,
            value: state.timeLimit,
            items: TimeLimit.values,
            label: (t) => t.label,
            onChanged: (v) => vm.setTimeLimit(v!),
          ),
          _dropdown<String>(
            context,
            value: state.semesterXq,
            items: const ['0', '1', '2'],
            label: (s) => s == '0'
                ? '第一学期'
                : s == '1'
                ? '第二学期'
                : '第二阶段',
            onChanged: (v) => vm.setSemesterXq(v!),
          ),
          _toggle(
            context,
            '主修',
            state.selectMajor,
            () => vm.toggleCategory('major'),
          ),
          _toggle(
            context,
            '辅修',
            state.selectMinor,
            () => vm.toggleCategory('minor'),
          ),
          _toggle(
            context,
            '微专',
            state.selectWeiZhuan,
            () => vm.toggleCategory('weizhuan'),
          ),
          _toggle(context, '仅未通过', state.onlyNotPassed, vm.toggleOnlyNotPassed),
          _toggle(
            context,
            state.showRawGrade ? '原始成绩' : '有效成绩',
            state.showRawGrade,
            vm.toggleShowRawGrade,
            activeColor: Colors.red,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: '刷新',
            onPressed: () => ref.invalidate(_gradesProvider),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>(
    BuildContext context, {
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
    BuildContext context,
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

  Widget _buildGradeTable(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gradesViewModelProvider);
    final resultAsync = ref.watch(_gradesProvider(state.params));

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
                  _buildGradeTableWidget(context, result.grades),
                  if (result.summaries.isNotEmpty)
                    _buildSummaryTable(context, result.summaries),
                ],
              ),
            ),
    );
  }

  Widget _buildGradeTableWidget(BuildContext context, List<Grade> grades) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 600;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: IntrinsicWidth(
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    theme.colorScheme.error,
                  ),
                  headingTextStyle: TextStyle(
                    color: theme.colorScheme.onError,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  dataTextStyle: const TextStyle(fontSize: 13),
                  columnSpacing: 16,
                  columns: isNarrow
                      ? const [
                          DataColumn(label: Text('课程名称')),
                          DataColumn(label: Text('学分')),
                          DataColumn(label: Text('分数')),
                        ]
                      : const [
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
                        cells: isNarrow
                            ? [
                                DataCell(
                                  Text(
                                    g.courseName,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                DataCell(Text(g.credit)),
                                DataCell(Text(g.score)),
                              ]
                            : [
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
                                  Text(
                                    g.category,
                                    style: const TextStyle(fontSize: 11),
                                  ),
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryTable(
    BuildContext context,
    List<GradeSummary> summaries,
  ) {
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
