import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule_engine.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/reschedule_marks.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_grid_view.dart';

/// 横版课表：12 列（节次）× 7 行（星期）
///
/// - 12 列 = 第1节至第12节
/// - 7 行 = 周一至周日
/// - 课程可横向跨列（如3-5节跨3列）
///
/// 与 [ScheduleGridView] 一样支持周视图与调课覆盖层。
class ScheduleHorizontalView extends StatelessWidget {
  final List<ScheduleEntry> entries;
  final List<Reschedule> reschedules;

  /// 展示的教学周；null = 整学期模板。
  final int? week;

  /// 该教学周的周一（用于行首显示日期）。
  final DateTime? weekMonday;

  final ValueChanged<EffectiveClass>? onTapClass;
  final void Function(DayOfWeek day, int period)? onTapEmptySlot;
  final VoidCallback? onToggle;
  final bool isHorizontal;

  /// 是否渲染左上角的「横/竖版切换」按钮。
  ///
  /// 手机端按设备横竖屏**自动**选视图（用户 2026-09-15：「移动端取消切换横置/
  /// 竖置按钮，而是适应屏幕是横屏还是竖屏」）→ 手机端传 `false`，桌面端保留。
  final bool showToggle;

  /// 作息时间表（节次 → 上下课钟点）；表头格里显示「上课时间 / 节次 / 下课时间」
  /// （用户 2026-09-16 裁定）。null 或缺该节次时退回只显示节次。
  final PeriodTable? periods;

  const ScheduleHorizontalView({
    super.key,
    required this.entries,
    this.reschedules = const [],
    this.week,
    this.weekMonday,
    this.onTapClass,
    this.onTapEmptySlot,
    this.onToggle,
    this.isHorizontal = true,
    this.showToggle = true,
    this.periods,
  });

  // ─── 布局常量 ─────────────────────────────────────────────────

  static const _dayLabelWidth = 36.0;
  static const _headerHeight = 40.0;
  static const _borderWidth = 0.5;

  /// 单元格内容按行高取舍的阈值（**恒适应高度**后行高可能很小，见 [build]）。
  ///
  /// 这些阈值是「不溢出」的硬约束：字号 11/9 时单行约 13/11px，
  /// 累加高度超过行高就会触发 RenderFlex overflow（用户 2026-09-15：
  /// 「横版课表永远适应宽度和高度」→ 只能靠取舍内容而不是裁剪/滚动）。
  static const _twoLineNameHeight = 56.0;
  static const _twoLineClassroomHeight = 46.0;
  static const _teacherHeight = 70.0;

  // ─── 调色板 ───────────────────────────────────────────────────

  static const _coursePalette = [
    Color(0xFFE3F2FD),
    Color(0xFFFFF3E0),
    Color(0xFFE8F5E9),
    Color(0xFFFCE4EC),
    Color(0xFFF3E5F5),
    Color(0xFFE0F7FA),
    Color(0xFFFFF8E1),
    Color(0xFFEFEBE9),
    Color(0xFFE8EAF6),
    Color(0xFFF1F8E9),
    Color(0xFFFFEBEE),
    Color(0xFFEDE7F6),
  ];

  static const _textPalette = [
    Color(0xFF1565C0),
    Color(0xFFE65100),
    Color(0xFF2E7D32),
    Color(0xFFC62828),
    Color(0xFF6A1B9A),
    Color(0xFF00838F),
    Color(0xFFF9A825),
    Color(0xFF4E342E),
    Color(0xFF283593),
    Color(0xFF558B2F),
    Color(0xFFB71C1C),
    Color(0xFF4527A0),
  ];

  // ─── 构建 ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = _buildGrid();
        // 整学期视图不展开单次调课，改为在原课位上出角标
        final onceMarks = week == null
            ? onceMarksBySlot(reschedules)
            : const <String, int>{};
        // 手机（短边 < 620）左右无边距、字号收紧；桌面保留 12。
        // 用**短边**判手机：手机横屏时宽度已经很大，按宽度会误判成桌面。
        final shortestSide = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final compact = shortestSide < ScheduleGridView.compactBreakpoint;
        final hPadding = compact ? 0.0 : 12.0;
        final vPadding = compact ? 6.0 : 12.0;

        // **恒适应宽度**（用户 2026-09-15：「横版课表永远适应宽度和高度」）：
        // 12 个节次等分可用宽度 → 永不横向滚动。
        final rawCellWidth =
            (constraints.maxWidth - hPadding * 2 - _dayLabelWidth) / 12;
        final cellWidth = rawCellWidth > 0 ? rawCellWidth : 1.0;
        // **恒适应高度**：7 行平分「表头 + 上下内边距」之外的剩余高度，
        // 不再 clamp 到最小行高（否则小窗口必然纵向溢出）。
        final rawRowHeight =
            (constraints.maxHeight - vPadding * 2 - _headerHeight) / 7;
        final rowHeight = rawRowHeight > 0 ? rawRowHeight : 1.0;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: hPadding,
            vertical: vPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderRow(cellWidth: cellWidth),
              ...List.generate(
                7,
                (day) => _buildDayRow(
                  day,
                  grid[day],
                  rowHeight: rowHeight,
                  cellWidth: cellWidth,
                  onceMarks: onceMarks,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── 表头行 ───────────────────────────────────────────────────

  /// 表头格里的小字钟点（上=上课、下=下课）；红底白字故用 `white70`。
  Widget _headerTimeText(String value) => Text(
    value,
    style: const TextStyle(
      color: Colors.white70,
      fontSize: 8,
      height: 1.2,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  );

  Widget _buildHeaderRow({required double cellWidth}) {
    return SizedBox(
      height: _headerHeight,
      child: Row(
        children: [
          // 左上角：切换横/竖版按钮（手机端自动按横竖屏切换，故不渲染）
          if (showToggle)
            GestureDetector(
              onTap: onToggle,
              child: Container(
                width: _dayLabelWidth,
                height: _headerHeight,
                alignment: Alignment.center,
                child: Icon(
                  isHorizontal ? Icons.view_day : Icons.view_week,
                  color: const Color(0xFFC62828),
                  size: 18,
                ),
              ),
            )
          else
            SizedBox(width: _dayLabelWidth, height: _headerHeight),
          // 12 节次表头：上课时间 / 节次 / 下课时间（用户 2026-09-16 裁定）
          ...List.generate(12, (i) {
            final period = i + 1;
            final slot = periods?.periodOf(period);
            return Container(
              key: Key('schedulePeriodHeaderCell-$period'),
              width: cellWidth,
              height: _headerHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFC62828),
                border: Border(
                  right: BorderSide(color: Colors.white24, width: _borderWidth),
                ),
              ),
              child: slot == null
                  ? Text(
                      '$period',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Column(
                      // 时间贴格子上下两端，节数居中（用户 2026-09-16：「时间显示在
                      // 格子两端，而不是紧贴节数号」）。
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _headerTimeText(slot.start),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              '$period',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: _headerTimeText(slot.end),
                        ),
                      ],
                    ),
            );
          }),
        ],
      ),
    );
  }

  // ─── 一天行 ───────────────────────────────────────────────────

  Widget _buildDayRow(
    int day,
    Map<int, List<EffectiveClass>> dayData, {
    required double rowHeight,
    required double cellWidth,
    required Map<String, int> onceMarks,
  }) {
    final isWeekend = day >= 5;

    // 被跨列占用的节次
    final occupied = <int, bool>{};
    final cells = <Widget>[];

    for (int period = 1; period <= 12; period++) {
      if (occupied[period] == true) continue;

      final slots = dayData[period];
      if (slots == null || slots.isEmpty) {
        cells.add(
          _buildEmptyCell(
            day: day,
            period: period,
            isWeekend: isWeekend,
            height: rowHeight,
            cellWidth: cellWidth,
          ),
        );
        continue;
      }

      final span = slots.first.classTime.periodSpan;
      for (int p = period + 1; p < period + span && p <= 12; p++) {
        occupied[p] = true;
      }

      cells.add(
        _buildCourseCell(
          slots: slots,
          span: span,
          day: day,
          period: period,
          height: rowHeight,
          cellWidth: cellWidth,
          onceMarks: onceMarks,
        ),
      );
    }

    return SizedBox(
      height: rowHeight,
      child: Row(
        children: [
          _buildDayLabel(day, isWeekend, height: rowHeight),
          ...cells,
        ],
      ),
    );
  }

  // ─── 星期标签 ─────────────────────────────────────────────────

  Widget _buildDayLabel(int day, bool isWeekend, {required double height}) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final date = weekMonday?.add(Duration(days: day));
    return Container(
      width: _dayLabelWidth,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isWeekend ? Colors.blueGrey.shade50 : Colors.grey.shade50,
        border: Border(
          right: BorderSide(color: Colors.grey.shade300, width: _borderWidth),
          bottom: BorderSide(color: Colors.grey.shade200, width: _borderWidth),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            names[day],
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isWeekend ? Colors.blueGrey : Colors.grey.shade800,
            ),
          ),
          if (date != null)
            Text(
              '${date.month}/${date.day}',
              style: TextStyle(fontSize: 8, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }

  // ─── 空节次格子 ───────────────────────────────────────────────

  Widget _buildEmptyCell({
    required int day,
    required int period,
    required bool isWeekend,
    required double height,
    required double cellWidth,
  }) {
    final cell = Container(
      width: cellWidth,
      height: height,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.grey.shade200, width: _borderWidth),
          bottom: BorderSide(color: Colors.grey.shade200, width: _borderWidth),
        ),
        color: isWeekend ? Colors.grey.shade100 : null,
      ),
    );
    if (onTapEmptySlot == null) return cell;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTapEmptySlot!(DayOfWeek.values[day], period),
      child: cell,
    );
  }

  // ─── 课程格子（横向跨列）──────────────────────────────────────

  Widget _buildCourseCell({
    required List<EffectiveClass> slots,
    required int span,
    required int day,
    required int period,
    required double height,
    required double cellWidth,
    required Map<String, int> onceMarks,
  }) {
    final first = slots.first;
    final entry = first.entry;
    final classTime = first.classTime;
    final mark = first.mark;

    final colorIndex = entry.courseCode.hashCode.abs() % _coursePalette.length;
    var bgColor = _coursePalette[colorIndex];
    var textColor = _textPalette[colorIndex];

    switch (mark) {
      case EffectiveMark.movedAway:
        bgColor = Colors.grey.shade50;
        textColor = Colors.grey.shade600;
      case EffectiveMark.cancelled:
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade600;
      case EffectiveMark.extra:
        if (first.reschedule?.courseCode.isEmpty ?? true) {
          bgColor = const Color(0xFFE8F5E9);
          textColor = FeaturePalette.makeUpClass;
        }
      case EffectiveMark.normal:
      case EffectiveMark.moved:
        break;
    }

    final width = cellWidth * span;
    // 内容按行高取舍：行高被压缩（手机横屏）时少显示几行，绝不溢出。
    final nameLines = height >= _twoLineNameHeight ? 2 : 1;
    final classroomLines = height >= _twoLineClassroomHeight ? 2 : 1;
    final showTeacher = height >= _teacherHeight && (span >= 3 || width >= 180);
    final badge =
        rescheduleBadge(mark) ??
        rescheduleOnceBadge(
          onceMarks[classSlotKey(entry.courseCode, classTime)] ?? 0,
        );

    final card = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          left: mark == EffectiveMark.moved
              ? const BorderSide(color: FeaturePalette.reschedule, width: 2)
              : BorderSide.none,
          right: BorderSide(color: Colors.grey.shade300, width: _borderWidth),
          bottom: BorderSide(color: Colors.grey.shade300, width: _borderWidth),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        entry.courseName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          height: 1.2,
                          decoration:
                              mark == EffectiveMark.cancelled ||
                                  mark == EffectiveMark.movedAway
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: nameLines,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (badge != null) ...[const SizedBox(width: 4), badge],
                  ],
                ),
                if (mark == EffectiveMark.movedAway) ...[
                  const SizedBox(height: 2),
                  Text(
                    '已调至 ${rescheduleTargetShort(first.reschedule)}',
                    style: TextStyle(
                      fontSize: 9,
                      color: textColor,
                      height: 1.25,
                    ),
                    maxLines: classroomLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else if (mark == EffectiveMark.cancelled) ...[
                  const SizedBox(height: 2),
                  Text(
                    '本次停课',
                    style: TextStyle(fontSize: 9, color: textColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else ...[
                  if (showTeacher) ...[
                    const SizedBox(height: 2),
                    Text(
                      first.teacherName,
                      style: TextStyle(
                        fontSize: 9,
                        color: textColor.withAlpha(180),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // 教室放不下一行就换行（用户 2026-09-15：「课程教室不能在一行
                  // 显示时，自动换行」）—— 行高不够时才退化为省略。
                  Text(
                    classTime.classroom,
                    style: TextStyle(
                      fontSize: 9,
                      color: textColor.withAlpha(160),
                      height: 1.2,
                    ),
                    maxLines: classroomLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // 单节行高放不下第 4 行，只在跨节格子里显示来源
                  if (mark == EffectiveMark.moved && span >= 2)
                    Text(
                      '调自 ${rescheduleOriginShort(first.reschedule)}',
                      style: const TextStyle(
                        fontSize: 8,
                        color: FeaturePalette.reschedule,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ],
            ),
          ),
          // 周次信息只在**整学期视图**显示（周视图已按周过滤，周次是冗余信息；
          // 用户 2026-09-15 裁定，口径同 ScheduleGridView）。
          if (week == null &&
              span >= 2 &&
              mark != EffectiveMark.cancelled &&
              mark != EffectiveMark.movedAway)
            Text(
              '${classTime.startWeek}-${classTime.endWeek}周',
              style: TextStyle(fontSize: 8, color: textColor.withAlpha(130)),
              textAlign: TextAlign.right,
            ),
        ],
      ),
    );

    if (onTapClass == null) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTapClass!(first),
      child: card,
    );
  }

  // ─── 数据预处理 ───────────────────────────────────────────────

  List<Map<int, List<EffectiveClass>>> _buildGrid() {
    final grid = List.generate(7, (_) => <int, List<EffectiveClass>>{});

    final classes = effectiveClasses(
      entries: entries,
      reschedules: reschedules,
      week: week,
    );

    for (final c in classes) {
      final day = c.dayIndex - 1;
      final period = c.startPeriod;

      grid[day].putIfAbsent(period, () => []);
      grid[day][period]!.add(c);
    }

    return grid;
  }
}
