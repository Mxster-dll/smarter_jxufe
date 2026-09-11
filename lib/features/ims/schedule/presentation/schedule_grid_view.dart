import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule_engine.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/reschedule_marks.dart';

/// 7×12 课表网格组件
///
/// - 7 列 = 周一至周日
/// - 12 行 = 第1节至第12节
/// - 课程可纵向跨行（如3-5节跨3行）
/// - 相同时段多门课（单双周冲突）垂直平分该格
///
/// [week] 为空时是**整学期模板**（把各周次叠加显示，保持历史行为），
/// 非空时是**周视图**：按该教学周过滤课次，并完整应用调课/停课/补课。
class ScheduleGridView extends StatelessWidget {
  final List<ScheduleEntry> entries;

  /// 本学期调课记录。
  final List<Reschedule> reschedules;

  /// 展示的教学周；null = 整学期模板。
  final int? week;

  /// 该教学周的周一（用于表头显示日期）。
  final DateTime? weekMonday;

  /// 点某一节课（原课/调课/停课/补课格都可点）。
  final ValueChanged<EffectiveClass>? onTapClass;

  /// 点空白格子（用于「在这里补一节课」）：参数为星期几(1-7)与起始节次。
  final void Function(DayOfWeek day, int period)? onTapEmptySlot;

  final VoidCallback? onToggle;
  final bool isHorizontal;

  const ScheduleGridView({
    super.key,
    required this.entries,
    this.reschedules = const [],
    this.week,
    this.weekMonday,
    this.onTapClass,
    this.onTapEmptySlot,
    this.onToggle,
    this.isHorizontal = false,
  });

  // ─── 布局常量 ─────────────────────────────────────────────────

  static const _periodLabelWidth = 36.0;
  static const _headerHeight = 40.0;
  static const _cellMinHeight = 56.0;
  static const _borderWidth = 0.5;

  // ─── 调色板 ───────────────────────────────────────────────────

  static const _coursePalette = [
    Color(0xFFE3F2FD), // 浅蓝
    Color(0xFFFFF3E0), // 浅橙
    Color(0xFFE8F5E9), // 浅绿
    Color(0xFFFCE4EC), // 浅粉
    Color(0xFFF3E5F5), // 浅紫
    Color(0xFFE0F7FA), // 浅青
    Color(0xFFFFF8E1), // 浅黄
    Color(0xFFEFEBE9), // 浅棕
    Color(0xFFE8EAF6), // 靛蓝
    Color(0xFFF1F8E9), // 浅黄绿
    Color(0xFFFFEBEE), // 浅红
    Color(0xFFEDE7F6), // 深紫
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
    final grid = _buildGrid();
    // 整学期视图不展开单次调课，改为在原课位上出角标
    final onceMarks = week == null
        ? onceMarksBySlot(reschedules)
        : const <String, int>{};

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth - 24; // 减去 padding
        // 列宽自适应屏幕，最小 80dp 保证可读，最大 160dp
        final colWidth = ((viewportWidth - _periodLabelWidth) / 7).clamp(
          80.0,
          160.0,
        );
        final totalWidth = _periodLabelWidth + 7 * colWidth;
        final fitsWidth = totalWidth <= viewportWidth;

        final gridContent = SizedBox(
          width: fitsWidth ? viewportWidth : totalWidth,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPeriodLabelColumn(),
                ...List.generate(
                  7,
                  (day) => _buildDayColumn(
                    day,
                    grid[day],
                    colWidth: colWidth,
                    onceMarks: onceMarks,
                  ),
                ),
              ],
            ),
          ),
        );

        if (fitsWidth) {
          // 占满屏幕宽度，无需水平滚动
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: gridContent,
          );
        }
        // 内容超出 → 水平滚动
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: totalWidth, child: gridContent),
          ),
        );
      },
    );
  }

  // ─── 左侧节次标签 ─────────────────────────────────────────────

  Widget _buildPeriodLabelColumn() {
    return Column(
      children: [
        // 左上角：切换横/竖版按钮
        GestureDetector(
          onTap: onToggle,
          child: Container(
            width: _periodLabelWidth,
            height: _headerHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.shade200,
                  width: _borderWidth,
                ),
              ),
            ),
            child: Icon(
              isHorizontal ? Icons.view_day : Icons.view_week,
              color: const Color(0xFFC62828),
              size: 18,
            ),
          ),
        ),
        // 12 节标签
        ...List.generate(12, (i) {
          final period = i + 1;
          return Container(
            width: _periodLabelWidth,
            height: _cellMinHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: Colors.grey.shade300,
                  width: _borderWidth,
                ),
                bottom: BorderSide(
                  color: Colors.grey.shade200,
                  width: _borderWidth,
                ),
              ),
              color: period == 5 ? Colors.grey.shade100 : null,
            ),
            child: Text(
              '$period',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }),
      ],
    );
  }

  // ─── 一天列 ───────────────────────────────────────────────────

  Widget _buildDayColumn(
    int day,
    Map<int, List<EffectiveClass>> dayData, {
    required double colWidth,
    required Map<String, int> onceMarks,
  }) {
    // 预计算每个节次是否被上方跨行课程占用
    final occupied = <int, bool>{};
    final widgets = <Widget>[];

    // 表头
    widgets.add(_buildDayHeader(day, colWidth: colWidth));

    // 逐节次构建
    for (int period = 1; period <= 12; period++) {
      if (occupied[period] == true) continue;

      final slots = dayData[period];
      if (slots == null || slots.isEmpty) {
        widgets.add(
          _buildEmptyCell(day: day, period: period, colWidth: colWidth),
        );
        continue;
      }

      // 取第一个 slot 决定跨行数（同一课程相同时段不同教室的情况暂取第一个）
      final span = slots.first.classTime.periodSpan;

      // 标记后续节次为已占用
      for (int p = period + 1; p < period + span && p <= 12; p++) {
        occupied[p] = true;
      }

      widgets.add(
        _buildCourseCell(
          slots: slots,
          span: span,
          day: day,
          period: period,
          colWidth: colWidth,
          onceMarks: onceMarks,
        ),
      );
    }

    return SizedBox(width: colWidth, child: Column(children: widgets));
  }

  // ─── 表头 ─────────────────────────────────────────────────────

  Widget _buildDayHeader(int day, {required double colWidth}) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final isWeekend = day >= 5;
    final date = weekMonday?.add(Duration(days: day));

    return Container(
      width: colWidth,
      height: _headerHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isWeekend ? Colors.blueGrey.shade700 : const Color(0xFFC62828),
        border: Border(
          bottom: BorderSide(color: Colors.white24, width: _borderWidth),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            names[day],
            style: TextStyle(
              color: Colors.white,
              fontSize: date == null ? 14 : 13,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
          if (date != null)
            Text(
              '${date.month}/${date.day}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                height: 1.2,
              ),
            ),
        ],
      ),
    );
  }

  // ─── 空节次格子 ───────────────────────────────────────────────

  Widget _buildEmptyCell({
    required int day,
    required int period,
    required double colWidth,
  }) {
    final isBeforeNoon = period == 5;
    final cell = Container(
      width: colWidth,
      height: _cellMinHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: _borderWidth),
          right: BorderSide(color: Colors.grey.shade200, width: _borderWidth),
        ),
        color: isBeforeNoon ? Colors.grey.shade50 : null,
      ),
    );
    if (onTapEmptySlot == null) return cell;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTapEmptySlot!(DayOfWeek.values[day], period),
      child: cell,
    );
  }

  // ─── 课程格子 ─────────────────────────────────────────────────

  Widget _buildCourseCell({
    required List<EffectiveClass> slots,
    required int span,
    required int day,
    required int period,
    required double colWidth,
    required Map<String, int> onceMarks,
  }) {
    final first = slots.first;
    final entry = first.entry;
    final classTime = first.classTime;
    final mark = first.mark;

    // 颜色：调课后的课沿用课程自身颜色，便于认出是哪门课
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

    final cellHeight = _cellMinHeight * span;

    // 单双周标签
    final weekLabel = classTime.weekParity != WeekParity.every
        ? ' (${classTime.weekParity.displayName})'
        : '';

    // 角标：调 / 停 / 补；整学期视图下若无标记则用「单次调整」提示角标
    final badge =
        rescheduleBadge(mark) ??
        rescheduleOnceBadge(
          onceMarks[classSlotKey(entry.courseCode, classTime)] ?? 0,
        );

    final card = Container(
      width: colWidth,
      height: cellHeight,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: mark == EffectiveMark.moved
              ? const BorderSide(
                  color: FeaturePalette.reschedule,
                  width: 2,
                )
              : BorderSide.none,
          bottom: BorderSide(color: Colors.grey.shade300, width: _borderWidth),
          right: BorderSide(color: Colors.grey.shade300, width: _borderWidth),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 课程名称 + 角标
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  entry.courseName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    height: 1.2,
                    decoration: mark == EffectiveMark.cancelled ||
                            mark == EffectiveMark.movedAway
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                  maxLines: span > 1 ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 4), badge],
            ],
          ),
          const SizedBox(height: 2),

          if (mark == EffectiveMark.movedAway) ...[
            Text(
              '已调至 ${rescheduleTargetShort(first.reschedule)}',
              style: TextStyle(fontSize: 10, color: textColor, height: 1.25),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ] else if (mark == EffectiveMark.cancelled) ...[
            Text(
              '本次停课',
              style: TextStyle(fontSize: 10, color: textColor, height: 1.25),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (span >= 2)
              Text(
                '${classTime.startWeek}-${classTime.endWeek}周$weekLabel',
                style: TextStyle(fontSize: 9, color: textColor, height: 1.25),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ] else ...[
            // 教师（始终显示）
            Text(
              first.teacherName,
              style: TextStyle(
                fontSize: 10,
                color: textColor.withAlpha(190),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // 教室：节数多时分两行更清晰
            if (span >= 2) ...[
              const SizedBox(height: 2),
              Text(
                classTime.classroom,
                style: TextStyle(
                  fontSize: 10,
                  color: textColor.withAlpha(180),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ] else
              Text(
                classTime.classroom,
                style: TextStyle(
                  fontSize: 9,
                  color: textColor.withAlpha(150),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            // 周次 / 调课来源（单节格子放不下第 4 行，只在跨节格子里显示）
            if (mark == EffectiveMark.moved && span >= 2)
              Text(
                '调自 ${rescheduleOriginShort(first.reschedule)}',
                style: TextStyle(
                  fontSize: 9,
                  color: FeaturePalette.reschedule,
                  height: 1.25,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else if (span >= 2)
              Text(
                '${classTime.startWeek}-${classTime.endWeek}周$weekLabel',
                style: TextStyle(fontSize: 9, color: textColor.withAlpha(140)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],

          // 同一格有多个 slot（单双周不同教室）时分隔显示
          if (slots.length > 1) ...[
            const Divider(height: 4, thickness: 0.5),
            for (final s in slots.skip(1))
              Text(
                s.mark == EffectiveMark.normal
                    ? '${s.classTime.weekParity.displayName}: ${s.classTime.classroom}'
                    : '${s.mark.name}: ${s.classTime.classroom}',
                style: TextStyle(
                  fontSize: 9,
                  color: textColor.withAlpha(160),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
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

  /// 构建 7 天 × 12 节次的网格
  ///
  /// 返回 `List<Map<int, List<EffectiveClass>>>`，索引为 day(0-6)，
  /// Map 的 key 为起始节次(1-12)，value 为该节次开始的课节列表。
  List<Map<int, List<EffectiveClass>>> _buildGrid() {
    final grid = List.generate(7, (_) => <int, List<EffectiveClass>>{});

    final classes = effectiveClasses(
      entries: entries,
      reschedules: reschedules,
      week: week,
    );

    for (final c in classes) {
      final day = c.dayIndex - 1; // 0-based
      final period = c.startPeriod;

      grid[day].putIfAbsent(period, () => []);
      grid[day][period]!.add(c);
    }

    return grid;
  }
}
