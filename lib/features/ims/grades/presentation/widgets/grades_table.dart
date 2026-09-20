/// 成绩页「成绩明细表」零件（2026-09-20 从 `grades_screen.dart` 外提 · 架构审查 ⑥）。
///
/// 原 `_GradesScreenState._buildGradeTableWidget`（275 行）—— 提取成 StatelessWidget；
/// `excludedCourses` / `retakeScores` 块内只读，`onRetakeTap` 原是 State 方法
/// `_onRetakeTap(Grade)`，改由调用方注入。原同文件的顶层私有类 `_StickyHeaderTable`
/// 随块一起搬并**改为公开名** `GradesStickyHeaderTable`（`_` 是库私有，跨文件不可见；
/// 全仓无其它引用，已核实）。块内局部函数 `buildHeaders` / `buildDataRows` /
/// `_computeIntrinsicWidths` 原样留在 `build` 里。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/breakpoints.dart';
import 'package:smarter_jxufe/design/status_palette.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_importance.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grade.dart';

class GradesTable extends StatelessWidget {
  const GradesTable({
    super.key,
    required this.grades,
    required this.showSemester,
    required this.avgScore,
    required Map<String, CourseImportance>? importanceMap,
    required this.sortKey,
    required this.sortAsc,
    required this.onSort,
    required this.excludedCourses,
    required this.retakeScores,
    required this.onRetakeTap,
  }) : _importanceMap = importanceMap;

  final List<Grade> grades;
  final bool showSemester;
  final double avgScore;

  /// ⚠ **私有字段**（构造参数仍是公开名）：公有字段不参与 Dart 的类型提升，
  /// 块内 `if (importanceMap == null) …` 之后按下标取用会报 `unchecked_use_of_nullable_value`。
  final Map<String, CourseImportance>? _importanceMap;
  final String? sortKey;
  final bool sortAsc;
  final ValueChanged<String> onSort;
  final Set<String> excludedCourses;
  final Map<String, String> retakeScores;
  final void Function(Grade grade) onRetakeTap;

  @override
  Widget build(BuildContext context) {
    List<String> buildHeaders(bool isNarrow) {
      final h = isNarrow
          ? <String>['课程名称', '学分', '分数', '贡献']
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
              '贡献',
            ];
      if (showSemester && !isNarrow) h.add('学期');
      return h;
    }

    List<String> buildSortKeys(bool isNarrow) {
      final keys = isNarrow
          ? <String>['courseName', 'credit', 'score', 'contribution']
          : <String>[
              'courseCode',
              'courseName',
              'credit',
              'category',
              'nature',
              'examType',
              'score',
              'gradePoint',
              'creditGradePoint',
              'contribution',
            ];
      if (showSemester && !isNarrow) keys.add('semester');
      return keys;
    }

    Map<int, double> computeIntrinsicWidths(bool isNarrow) {
      final headers = buildHeaders(isNarrow);
      final painter = TextPainter(textDirection: TextDirection.ltr);
      final w = <int, double>{};

      // 用表头文字估算
      for (int i = 0; i < headers.length; i++) {
        painter
          ..text = TextSpan(
            text: headers[i],
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          )
          ..layout();
        w[i] = painter.width + 28; // padding + margin
      }

      // 抽几个数据行做抽样，取更大者
      if (!isNarrow) {
        final fieldGetters = showSemester
            ? <String Function(Grade)>[
                (g) => g.courseCode,
                (g) => g.courseName,
                (g) => g.credit,
                (g) => g.category,
                (g) => g.nature,
                (g) => g.examType,
                (g) => g.score,
                (g) => g.gradePoint,
                (g) => g.creditGradePoint,
                (g) => '', // 贡献
                (g) => g.semester,
              ]
            : <String Function(Grade)>[
                (g) => g.courseCode,
                (g) => g.courseName,
                (g) => g.credit,
                (g) => g.category,
                (g) => g.nature,
                (g) => g.examType,
                (g) => g.score,
                (g) => g.gradePoint,
                (g) => g.creditGradePoint,
                (g) => '',
              ];

        final sample = grades.length > 5 ? grades.sublist(0, 5) : grades;
        for (int i = 0; i < headers.length; i++) {
          double maxCell = 0;
          for (final g in sample) {
            final text = fieldGetters[i](g);
            painter
              ..text = TextSpan(
                text: text,
                style: const TextStyle(fontSize: 12),
              )
              ..layout();
            if (painter.width > maxCell) maxCell = painter.width;
          }
          final cellW = maxCell + 28;
          if (cellW > w[i]!) w[i] = cellW;
        }
      }

      return w;
    }

    List<Widget> buildHeaderCells(bool isNarrow) {
      final headers = buildHeaders(isNarrow);
      final keys = buildSortKeys(isNarrow);
      return List.generate(headers.length, (i) {
        final active = sortKey == keys[i];
        return GestureDetector(
          onTap: () => onSort(keys[i]),
          behavior: HitTestBehavior.opaque,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(right: active ? 14 : 0),
                child: Text(
                  headers[i],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.onErrorFill(context),
                    fontWeight: FontWeight.bold,
                    fontSize: active ? 11 : 13,
                  ),
                ),
              ),
              if (active)
                Positioned(
                  right: 0,
                  child: Icon(
                    sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 12,
                    color: AppColors.onErrorFill(context),
                  ),
                ),
            ],
          ),
        );
      });
    }

    List<List<Widget>> buildDataRows(bool isNarrow) {
      return grades.map((g) {
        final isExcluded = excludedCourses.contains(g.courseName);
        final hasRetake = retakeScores.containsKey(g.courseCode);
        final displayScore = hasRetake ? retakeScores[g.courseCode]! : g.score;
        final s = double.tryParse(displayScore) ?? 0;
        final c = double.tryParse(g.credit) ?? 0;
        final contrib = (s - avgScore) * c;
        final contribWidget = Text(
          isExcluded ? '' : contrib.toStringAsFixed(1),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: !isExcluded && contrib < 0
                ? AppColors.critical(context)
                : null,
          ),
        );

        final scoreWidget = GestureDetector(
          onTap: () => onRetakeTap(g),
          child: Text.rich(
            TextSpan(
              text: displayScore,
              children: [
                if (hasRetake)
                  TextSpan(
                    text: '*',
                    style: TextStyle(
                      // 深红「重修」标记：浅色原值不变，深色按 `AppColors.tone` 提亮。
                      color: AppColors.tone(context, StatusPalette.retake),
                    ),
                  ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        );

        final cells = isNarrow
            ? <Widget>[
                Text(g.courseName, style: const TextStyle(fontSize: 12)),
                Text(g.credit, textAlign: TextAlign.center),
                scoreWidget,
                contribWidget,
              ]
            : <Widget>[
                Text(g.courseCode, style: const TextStyle(fontSize: 11)),
                Text(g.courseName, style: const TextStyle(fontSize: 12)),
                Text(g.credit, textAlign: TextAlign.center),
                Text(g.category, style: const TextStyle(fontSize: 11)),
                Text(
                  hasRetake ? '重修' : g.nature,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: hasRetake
                        ? AppColors.tone(context, StatusPalette.retake)
                        : null,
                  ),
                ),
                Text(g.examType, textAlign: TextAlign.center),
                scoreWidget,
                Text(g.gradePoint, textAlign: TextAlign.center),
                Text(g.creditGradePoint, textAlign: TextAlign.center),
                contribWidget,
              ];
        if (showSemester && !isNarrow) {
          cells.add(Text(g.semester, textAlign: TextAlign.center));
        }
        return cells;
      }).toList();
    }

    final rowBackgrounds = _importanceMap != null
        ? grades
              .map(
                (g) => _importanceMap[g.courseCode] == CourseImportance.core
                    ? AppColors.criticalFill(context)
                    : null,
              )
              .toList()
        : null;

    return Padding(
      padding: const EdgeInsets.all(4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < Breakpoints.narrow;
            final headers = buildHeaders(isNarrow);
            final nCols = headers.length;

            // ── 宽度算法：固有宽度 + d ──
            final intrinsicWidths = computeIntrinsicWidths(isNarrow);
            double intrinsicSum = 0;
            for (int i = 0; i < nCols; i++) {
              intrinsicSum += intrinsicWidths[i]!;
            }
            final extraPerCol = (constraints.maxWidth - intrinsicSum) / nCols;
            final colWidths = <int, TableColumnWidth>{};
            for (int i = 0; i < nCols; i++) {
              colWidths[i] = FixedColumnWidth(
                intrinsicWidths[i]! + (extraPerCol > 0 ? extraPerCol : 0),
              );
            }

            return GradesStickyHeaderTable(
              headerCells: buildHeaderCells(isNarrow),
              dataRows: buildDataRows(isNarrow),
              headerBgColor: AppColors.errorFill(context),
              columnWidths: colWidths,
              rowBackgrounds: rowBackgrounds,
              availableWidth: constraints.maxWidth,
              availableHeight: constraints.maxHeight,
            );
          },
        ),
      ),
    );
  }
}

/// 固定表头表格：表头始终可见，内容区可垂直滚动，横向滚动同步。
class GradesStickyHeaderTable extends StatefulWidget {
  final List<Widget> headerCells;
  final List<List<Widget>> dataRows;
  final Color headerBgColor;
  final Map<int, TableColumnWidth> columnWidths;
  final List<Color?>? rowBackgrounds;
  final double availableWidth;
  final double availableHeight;

  const GradesStickyHeaderTable({
    super.key,
    required this.headerCells,
    required this.dataRows,
    required this.headerBgColor,
    required this.columnWidths,
    this.rowBackgrounds,
    required this.availableWidth,
    required this.availableHeight,
  });

  @override
  State<GradesStickyHeaderTable> createState() => GradesStickyHeaderTableState();
}


class GradesStickyHeaderTableState extends State<GradesStickyHeaderTable> {
  final ScrollController _headerH = ScrollController();
  final ScrollController _bodyH = ScrollController();
  bool _syncing = false;

  static const _headerHt = 50.0;
  static const _rowHt = 40.0;

  double get _intrinsicBodyHeight => widget.dataRows.length * _rowHt;

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
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: widget.availableWidth),
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
            ), // ConstrainedBox (header)
          ),
        ),
        // 表体：min(固有高度, 可用高度 - 表头高度)
        LayoutBuilder(
          builder: (context, constraints) {
            final maxH = widget.availableHeight - _headerHt;
            final bodyH = _intrinsicBodyHeight < maxH
                ? _intrinsicBodyHeight
                : maxH;
            return SizedBox(
              height: bodyH,
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _bodyH,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: widget.availableWidth,
                    ),
                    child: Table(
                      columnWidths: widget.columnWidths,
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      border: TableBorder(horizontalInside: borderSide),
                      children: [
                        for (int i = 0; i < widget.dataRows.length; i++)
                          TableRow(
                            decoration:
                                widget.rowBackgrounds != null &&
                                    widget.rowBackgrounds![i] != null
                                ? BoxDecoration(
                                    color: widget.rowBackgrounds![i],
                                  )
                                : i.isOdd
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
            );
          },
        ),
      ],
    );
  }
}
