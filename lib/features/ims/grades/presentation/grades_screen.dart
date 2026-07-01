import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/grades/data/providers/grades_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grade.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_query_params.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_result.dart';
import 'package:smarter_jxufe/shared/widgets/academic_year_picker.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/time_limit.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/grades_viewmodel.dart';

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
          Flexible(fit: FlexFit.loose, child: _buildGradeTable(context, ref)),
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
    final showPicker = state.timeLimit != TimeLimit.sinceEnrollment;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          Wrap(
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
              if (state.timeLimit == TimeLimit.semester)
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
              _toggle(
                context,
                '仅未通过',
                state.onlyNotPassed,
                vm.toggleOnlyNotPassed,
              ),
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
          if (showPicker)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AcademicYearPicker(
                startYear: 2018,
                endYear: 2030,
                initialYear: state.academicYear,
                onChanged: vm.setAcademicYear,
              ),
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
          : _buildGradeTableWidget(
              context,
              result.grades,
              showSemester: state.timeLimit != TimeLimit.semester,
            ),
    );
  }

  Widget _buildGradeTableWidget(
    BuildContext context,
    List<Grade> grades, {
    required bool showSemester,
  }) {
    final theme = Theme.of(context);

    List<String> buildHeaders(bool isNarrow) {
      final h = isNarrow
          ? <String>['课程名称', '学分', '分数']
          : <String>[
              '课程代码',
              '课程名称',
              '学分',
              '类别',
              '性质',
              '考核',
              '成绩',
              '绩点',
              '学分绩点',
            ];
      if (showSemester) h.add('学期');
      return h;
    }

    Map<int, TableColumnWidth> buildColumnWidths(bool isNarrow) {
      if (isNarrow) {
        final w = <int, TableColumnWidth>{
          0: const FixedColumnWidth(180),
          1: const FixedColumnWidth(56),
          2: const FixedColumnWidth(68),
        };
        if (showSemester) w[3] = const FixedColumnWidth(56);
        return w;
      }
      final w = <int, TableColumnWidth>{
        0: const FixedColumnWidth(88),
        1: const FixedColumnWidth(200),
        2: const FixedColumnWidth(56),
        3: const FixedColumnWidth(140),
        4: const FixedColumnWidth(56),
        5: const FixedColumnWidth(56),
        6: const FixedColumnWidth(68),
        7: const FixedColumnWidth(60),
        8: const FixedColumnWidth(80),
      };
      if (showSemester) w[9] = const FixedColumnWidth(52);
      return w;
    }

    List<Widget> buildHeaderCells(bool isNarrow) {
      final headers = buildHeaders(isNarrow);
      return headers
          .map(
            (h) => Text(
              h,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onError,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          )
          .toList();
    }

    List<List<Widget>> buildDataRows(bool isNarrow) {
      return grades.map((g) {
        final cells = isNarrow
            ? <Widget>[
                Text(g.courseName, style: const TextStyle(fontSize: 12)),
                Text(g.credit, textAlign: TextAlign.center),
                Text(g.score, textAlign: TextAlign.center),
              ]
            : <Widget>[
                Text(g.courseCode, style: const TextStyle(fontSize: 11)),
                Text(g.courseName, style: const TextStyle(fontSize: 12)),
                Text(g.credit, textAlign: TextAlign.center),
                Text(g.category, style: const TextStyle(fontSize: 11)),
                Text(g.nature, textAlign: TextAlign.center),
                Text(g.examType, textAlign: TextAlign.center),
                Text(g.score, textAlign: TextAlign.center),
                Text(g.gradePoint, textAlign: TextAlign.center),
                Text(g.creditGradePoint, textAlign: TextAlign.center),
              ];
        if (showSemester) {
          cells.add(Text(g.semester, textAlign: TextAlign.center));
        }
        return cells;
      }).toList();
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 600;
            return _StickyHeaderTable(
              headerCells: buildHeaderCells(isNarrow),
              dataRows: buildDataRows(isNarrow),
              headerBgColor: theme.colorScheme.error,
              columnWidths: buildColumnWidths(isNarrow),
            );
          },
        ),
      ),
    );
  }
}

/// 固定表头表格：表头始终可见，内容区可垂直滚动，横向滚动同步。
class _StickyHeaderTable extends StatefulWidget {
  final List<Widget> headerCells;
  final List<List<Widget>> dataRows;
  final Color headerBgColor;
  final Map<int, TableColumnWidth> columnWidths;

  const _StickyHeaderTable({
    required this.headerCells,
    required this.dataRows,
    required this.headerBgColor,
    required this.columnWidths,
  });

  @override
  State<_StickyHeaderTable> createState() => _StickyHeaderTableState();
}

class _StickyHeaderTableState extends State<_StickyHeaderTable> {
  final ScrollController _headerH = ScrollController();
  final ScrollController _bodyH = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _headerH.addListener(_syncHeaderToBody);
    _bodyH.addListener(_syncBodyToHeader);
  }

  void _syncHeaderToBody() {
    if (_syncing) return;
    _syncing = true;
    if (_bodyH.hasClients && _bodyH.offset != _headerH.offset) {
      _bodyH.jumpTo(_headerH.offset);
    }
    _syncing = false;
  }

  void _syncBodyToHeader() {
    if (_syncing) return;
    _syncing = true;
    if (_headerH.hasClients && _headerH.offset != _bodyH.offset) {
      _headerH.jumpTo(_bodyH.offset);
    }
    _syncing = false;
  }

  @override
  void dispose() {
    _headerH.dispose();
    _bodyH.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderSide = BorderSide(
      color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
      width: 0.5,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 固定表头（带悬浮阴影）
        Container(
          padding: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: widget.headerBgColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _headerH,
            child: Table(
              columnWidths: widget.columnWidths,
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  children: widget.headerCells
                      .map(
                        (cell) => TableCell(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                            child: cell,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
        // 表体
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _bodyH,
              child: Table(
                columnWidths: widget.columnWidths,
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder(horizontalInside: borderSide),
                children: [
                  for (int i = 0; i < widget.dataRows.length; i++)
                    TableRow(
                      decoration: i.isOdd
                          ? BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.4),
                            )
                          : null,
                      children: widget.dataRows[i]
                          .map(
                            (cell) => TableCell(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                child: cell,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
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
