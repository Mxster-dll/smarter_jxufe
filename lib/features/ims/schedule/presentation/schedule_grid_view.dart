import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule_engine.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_view_mode.dart';
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

  /// 是否渲染左上角的「横/竖版切换」按钮（手机端按设备横竖屏自动切 → `false`）。
  final bool showToggle;

  /// 作息时间表（节次 → 上下课钟点）。
  ///
  /// 用户 2026-09-16：「在显示节数的格子里显示上课下课的时间，上课时间显示在
  /// 节数上方，下课时间在下方」。数据来自教务公开页 `SchoolTimetable.jsp`
  /// （免登录，见 `PeriodTableRepository`：实时 → 按学期缓存 → 内置兜底）；
  /// 取不到（null / 缺该节次）时退回只显示节次的旧样式。
  final PeriodTable? periods;

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
    this.showToggle = true,
    this.periods,
  });

  // ─── 布局常量 ─────────────────────────────────────────────────

  static const _periodLabelWidth = 36.0;
  static const _compactPeriodLabelWidth = 30.0;
  static const _headerHeight = 40.0;
  static const _compactHeaderHeight = 34.0;

  /// 单个节次的最小行高。**留够「课程名 + 教师 + 教室（两行）」**——
  /// 用户 2026-09-15 要求「课程教室不能在一行显示时自动换行」，
  /// 教室多占一行就必须多给高度，否则 RenderFlex 溢出。
  static const _cellMinHeight = 68.0;
  static const _compactCellMinHeight = 64.0;
  static const _borderWidth = 0.5;

  /// 桌面端列宽区间：区间内**适应屏宽**（列宽 = 可用宽度 / 7），
  /// 宽到 160 就不再拉伸（改为整表居中），窄到 80 才允许横向滚动。
  static const _minColWidth = 80.0;
  static const _maxColWidth = 160.0;

  /// 移动端断点：小于此宽度视为手机竖屏 —— 左右**无边距**、列宽等分屏宽
  /// （整表恰好铺满，不再横向滚动）、字号收紧。
  ///
  /// 值定义在 `domain/schedule_view_mode.dart`（视图选型与排版的唯一口径）。
  static const compactBreakpoint = scheduleCompactBreakpoint;

  double _labelWidth(bool compact) =>
      compact ? _compactPeriodLabelWidth : _periodLabelWidth;
  double _headerHeightOf(bool compact) =>
      compact ? _compactHeaderHeight : _headerHeight;

  /// 单个节次的最小行高（教室要能换行，见 [_cellMinHeight] 注释）。
  double _minCellHeightOf(bool compact) =>
      compact ? _compactCellMinHeight : _cellMinHeight;

  /// 实际行高：**有空间就把 12 行撑满可用高度**（不留底部空档），
  /// 空间不足才退回最小行高并纵向滚动。
  double _fitCellHeight({
    required bool compact,
    required double maxHeight,
    required double verticalPadding,
  }) {
    final available =
        maxHeight - verticalPadding * 2 - _headerHeightOf(compact);
    final fitted = available / 12;
    final minCell = _minCellHeightOf(compact);
    return fitted > minCell ? fitted : minCell;
  }

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
        // 手机判定用**短边**：手机横屏时宽度已过断点，按宽度会误判成桌面。
        final shortestSide = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final compact = shortestSide < compactBreakpoint;
        // 手机端左右无边距（用户 2026-09-15 要求），桌面端保留 12。
        final hPadding = compact ? 0.0 : 12.0;
        final labelWidth = _labelWidth(compact);
        final available = constraints.maxWidth - hPadding * 2;
        final rawColWidth = (available - labelWidth) / 7;
        // 手机：列宽 = 可用宽度 / 7 → 整表恰好铺满屏宽；
        // 桌面：80~160 之间自适应屏宽，越界不再拉伸 / 不足则横向滚动。
        final colWidth = compact
            ? (rawColWidth > 0 ? rawColWidth : _minColWidth)
            : rawColWidth.clamp(_minColWidth, _maxColWidth);
        final totalWidth = labelWidth + 7 * colWidth;
        final fitsWidth = totalWidth <= available + 0.5;

        final verticalPadding = compact ? 6.0 : 12.0;
        // 行高：有空间就撑满可用高度（底部不留空档），不够才滚动。
        final cellHeight = _fitCellHeight(
          compact: compact,
          maxHeight: constraints.maxHeight,
          verticalPadding: verticalPadding,
        );

        final gridContent = SizedBox(
          width: totalWidth,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPeriodLabelColumn(
                  compact: compact,
                  cellHeight: cellHeight,
                ),
                ...List.generate(
                  7,
                  (day) => _buildDayColumn(
                    day,
                    grid[day],
                    colWidth: colWidth,
                    compact: compact,
                    cellHeight: cellHeight,
                    onceMarks: onceMarks,
                  ),
                ),
              ],
            ),
          ),
        );

        if (fitsWidth) {
          // 铺满可用宽度时无需滚动；桌面超宽时 totalWidth < 可用宽度 → 居中。
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              hPadding,
              verticalPadding,
              hPadding,
              verticalPadding,
            ),
            child: Center(child: gridContent),
          );
        }
        // 内容超出 → 水平滚动（仅窄桌面窗口会走到这里）
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: hPadding),
            child: gridContent,
          ),
        );
      },
    );
  }

  // ─── 左侧节次标签 ─────────────────────────────────────────────

  /// 节次格里的小字钟点（上=上课、下=下课）。
  ///
  /// 窄格（手机 30dp）也要放下 `08:00` 五个字符，故字号压到 7.5/8.5，
  /// 并用等宽数字（`tabularFigures`）让 12 行的冒号对齐。
  Widget _periodTimeText(String value, {required bool compact}) => Text(
    value,
    style: TextStyle(
      fontSize: compact ? 7.5 : 8.5,
      height: 1.2,
      color: Colors.grey.shade500,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );

  Widget _buildPeriodLabelColumn({
    required bool compact,
    required double cellHeight,
  }) {
    final labelWidth = _labelWidth(compact);
    final headerHeight = _headerHeightOf(compact);

    return Column(
      children: [
        // 左上角：切换横/竖版按钮（手机端按横竖屏自动切视图，故不渲染）
        if (showToggle)
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: labelWidth,
              height: headerHeight,
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
                size: compact ? 16 : 18,
              ),
            ),
          )
        else
          SizedBox(width: labelWidth, height: headerHeight),
        // 12 节标签：上课时间 / 节次 / 下课时间（用户 2026-09-16 裁定）
        ...List.generate(12, (i) {
          final period = i + 1;
          final slot = periods?.periodOf(period);
          return Container(
            key: Key('schedulePeriodCell-$period'),
            width: labelWidth,
            height: cellHeight,
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
            child: slot == null
                ? Text(
                    '$period',
                    style: TextStyle(
                      fontSize: compact ? 10.5 : 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : Column(
                    // 时间贴格子上下两端，节数居中（用户 2026-09-16：「时间显示在
                    // 格子两端，而不是紧贴节数号」）——中间用 Expanded 撑开。
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: _periodTimeText(slot.start, compact: compact),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '$period',
                            style: TextStyle(
                              fontSize: compact ? 10.5 : 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: _periodTimeText(slot.end, compact: compact),
                      ),
                    ],
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
    required bool compact,
    required double cellHeight,
    required Map<String, int> onceMarks,
  }) {
    // 预计算每个节次是否被上方跨行课程占用
    final occupied = <int, bool>{};
    final widgets = <Widget>[];

    // 表头
    widgets.add(_buildDayHeader(day, colWidth: colWidth, compact: compact));

    // 逐节次构建
    for (int period = 1; period <= 12; period++) {
      if (occupied[period] == true) continue;

      final slots = dayData[period];
      if (slots == null || slots.isEmpty) {
        widgets.add(
          _buildEmptyCell(
            day: day,
            period: period,
            colWidth: colWidth,
            compact: compact,
            cellHeight: cellHeight,
          ),
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
          compact: compact,
          cellHeight: cellHeight,
          onceMarks: onceMarks,
        ),
      );
    }

    return SizedBox(
      width: colWidth,
      child: Column(children: widgets),
    );
  }

  // ─── 表头 ─────────────────────────────────────────────────────

  Widget _buildDayHeader(
    int day, {
    required double colWidth,
    required bool compact,
  }) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final isWeekend = day >= 5;
    final date = weekMonday?.add(Duration(days: day));

    return Container(
      width: colWidth,
      height: _headerHeightOf(compact),
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
              fontSize: compact
                  ? (date == null ? 12 : 11.5)
                  : (date == null ? 14 : 13),
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
          if (date != null)
            Text(
              '${date.month}/${date.day}',
              style: TextStyle(
                color: Colors.white70,
                fontSize: compact ? 8 : 9,
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
    required bool compact,
    required double cellHeight,
  }) {
    final isBeforeNoon = period == 5;
    final cell = Container(
      width: colWidth,
      height: cellHeight,
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
    required bool compact,
    required double cellHeight,
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

    final cellSpanHeight = cellHeight * span;

    // 周次信息（区间 + 单双周）**只在整学期视图显示**（用户 2026-09-15 裁定）：
    // 周视图已按该教学周过滤，格子里出现的都是本周真要上的课，周次字样是冗余信息。
    final showWeekInfo = week == null;

    // 单双周标签
    final weekLabel = classTime.weekParity != WeekParity.every
        ? ' (${classTime.weekParity.displayName})'
        : '';

    // 教室放不下整行时**换行**（用户 2026-09-15：「课表中的课程教室不能在一行
    // 显示时，自动换行」）；同格有多门课时留给「分隔线 + 第二门课」的位置，
    // 此时教室仍限一行（行高预算见 `_cellMinHeight` 注释）。
    final classroomLines = slots.length > 1 ? 1 : 2;

    // 角标：调 / 停 / 补；整学期视图下若无标记则用「单次调整」提示角标
    final badge =
        rescheduleBadge(mark) ??
        rescheduleOnceBadge(
          onceMarks[classSlotKey(entry.courseCode, classTime)] ?? 0,
        );

    final card = Container(
      width: colWidth,
      height: cellSpanHeight,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: mark == EffectiveMark.moved
              ? const BorderSide(color: FeaturePalette.reschedule, width: 2)
              : BorderSide.none,
          bottom: BorderSide(color: Colors.grey.shade300, width: _borderWidth),
          right: BorderSide(color: Colors.grey.shade300, width: _borderWidth),
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 3 : 6,
        vertical: compact ? 3 : 4,
      ),
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
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    height: 1.2,
                    decoration:
                        mark == EffectiveMark.cancelled ||
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
              style: TextStyle(
                fontSize: compact ? 9 : 10,
                color: textColor,
                height: 1.25,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ] else if (mark == EffectiveMark.cancelled) ...[
            Text(
              '本次停课',
              style: TextStyle(
                fontSize: compact ? 9 : 10,
                color: textColor,
                height: 1.25,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (showWeekInfo && span >= 2)
              Text(
                '${classTime.startWeek}-${classTime.endWeek}周$weekLabel',
                style: TextStyle(
                  fontSize: compact ? 8.5 : 9,
                  color: textColor,
                  height: 1.25,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ] else ...[
            // 教师（始终显示）
            Text(
              first.teacherName,
              style: TextStyle(
                fontSize: compact ? 9 : 10,
                color: textColor.withAlpha(190),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // 教室：节数多时分两行更清晰；放不下一行也换行
            if (span >= 2) ...[
              const SizedBox(height: 2),
              Text(
                classTime.classroom,
                style: TextStyle(
                  fontSize: compact ? 9 : 10,
                  color: textColor.withAlpha(180),
                  height: 1.2,
                ),
                maxLines: classroomLines,
                overflow: TextOverflow.ellipsis,
              ),
            ] else
              Text(
                classTime.classroom,
                style: TextStyle(
                  fontSize: compact ? 8.5 : 9,
                  color: textColor.withAlpha(150),
                  height: 1.2,
                ),
                maxLines: classroomLines,
                overflow: TextOverflow.ellipsis,
              ),
            // 周次 / 调课来源（单节格子放不下第 4 行，只在跨节格子里显示）
            if (mark == EffectiveMark.moved && span >= 2)
              Text(
                '调自 ${rescheduleOriginShort(first.reschedule)}',
                style: TextStyle(
                  fontSize: compact ? 8.5 : 9,
                  color: FeaturePalette.reschedule,
                  height: 1.25,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else if (showWeekInfo && span >= 2)
              Text(
                '${classTime.startWeek}-${classTime.endWeek}周$weekLabel',
                style: TextStyle(
                  fontSize: compact ? 8.5 : 9,
                  color: textColor.withAlpha(140),
                ),
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
                    ? (showWeekInfo
                          ? '${s.classTime.weekParity.displayName}: ${s.classTime.classroom}'
                          : s.classTime.classroom)
                    : '${s.mark.name}: ${s.classTime.classroom}',
                style: TextStyle(
                  fontSize: compact ? 8.5 : 9,
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
