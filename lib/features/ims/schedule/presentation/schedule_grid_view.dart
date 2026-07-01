import 'package:flutter/material.dart';

import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';

/// 课表网格中某个格子（时段槽位）包含的数据
class _SlotData {
  final ScheduleEntry entry;
  final ClassTime classTime;
  const _SlotData(this.entry, this.classTime);
}

/// 7×12 课表网格组件
///
/// - 7 列 = 周一至周日
/// - 12 行 = 第1节至第12节
/// - 课程可纵向跨行（如3-5节跨3行）
/// - 相同时段多门课（单双周冲突）垂直平分该格
class ScheduleGridView extends StatelessWidget {
  final List<ScheduleEntry> entries;
  final VoidCallback? onToggle;
  final bool isHorizontal;

  const ScheduleGridView({
    super.key,
    required this.entries,
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
                  (day) => _buildDayColumn(day, grid[day], colWidth: colWidth),
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
    Map<int, List<_SlotData>> dayData, {
    required double colWidth,
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
          _buildEmptyCell(isBeforeNoon: period == 5, colWidth: colWidth),
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
        ),
      );
    }

    return SizedBox(
      width: colWidth,
      child: Column(children: widgets),
    );
  }

  // ─── 表头 ─────────────────────────────────────────────────────

  Widget _buildDayHeader(int day, {required double colWidth}) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final isWeekend = day >= 5;
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
      child: Text(
        names[day],
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ─── 空节次格子 ───────────────────────────────────────────────

  Widget _buildEmptyCell({
    required bool isBeforeNoon,
    required double colWidth,
  }) {
    return Container(
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
  }

  // ─── 课程格子 ─────────────────────────────────────────────────

  Widget _buildCourseCell({
    required List<_SlotData> slots,
    required int span,
    required int day,
    required int period,
    required double colWidth,
  }) {
    final entry = slots.first.entry;
    final classTime = slots.first.classTime;

    // 根据课程代码确定颜色索引
    final colorIndex = entry.courseCode.hashCode.abs() % _coursePalette.length;
    final bgColor = _coursePalette[colorIndex];
    final textColor = _textPalette[colorIndex];

    // 计算格子高度：跨 N 节
    final cellHeight = _cellMinHeight * span;

    // 单双周标签
    final weekLabel = classTime.weekParity != WeekParity.every
        ? ' (${classTime.weekParity.displayName})'
        : '';

    return Container(
      width: colWidth,
      height: cellHeight,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: _borderWidth),
          right: BorderSide(color: Colors.grey.shade300, width: _borderWidth),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 课程名称
          Text(
            entry.courseName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
              height: 1.2,
            ),
            maxLines: span > 1 ? 3 : 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          // 教师（始终显示）
          Text(
            entry.teacherName,
            style: TextStyle(fontSize: 10, color: textColor.withAlpha(190)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // 教室：节数多时分两行更清晰
          if (span >= 2) ...[
            const SizedBox(height: 2),
            Text(
              classTime.classroom,
              style: TextStyle(fontSize: 10, color: textColor.withAlpha(180)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ] else
            // span=1：教室和教师挤一行
            Text(
              classTime.classroom,
              style: TextStyle(fontSize: 9, color: textColor.withAlpha(150)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          // 周次信息（2节以上显示）
          if (span >= 2)
            Text(
              '${classTime.startWeek}-${classTime.endWeek}周$weekLabel',
              style: TextStyle(fontSize: 9, color: textColor.withAlpha(140)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          // 如果同一格有多个 slot（单双周不同教室），分隔显示
          if (slots.length > 1) ...[
            const Divider(height: 4, thickness: 0.5),
            for (final s in slots.skip(1))
              Text(
                '${s.classTime.weekParity.displayName}: ${s.classTime.classroom}',
                style: TextStyle(fontSize: 9, color: textColor.withAlpha(160)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ],
      ),
    );
  }

  // ─── 数据预处理 ───────────────────────────────────────────────

  /// 构建 7 天 × 12 节次的网格
  ///
  /// 返回 `List<Map<int, List<_SlotData>>>`，索引为 day(0-6)，
  /// Map 的 key 为起始节次(1-12)，value 为该节次开始的课程列表
  List<Map<int, List<_SlotData>>> _buildGrid() {
    final grid = List.generate(7, (_) => <int, List<_SlotData>>{});

    for (final entry in entries) {
      for (final ct in entry.classTimes) {
        final day = ct.dayOfWeek.dayIndex - 1; // 0-based
        final period = ct.startPeriod;

        grid[day].putIfAbsent(period, () => []);
        grid[day][period]!.add(_SlotData(entry, ct));
      }
    }

    return grid;
  }
}
