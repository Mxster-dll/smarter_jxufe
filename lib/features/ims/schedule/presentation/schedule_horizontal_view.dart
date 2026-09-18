import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule_engine.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_color_index.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_display_days.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_gap_rows.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/reschedule_marks.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_grid_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_tone.dart';

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

  /// 显示周六 / 显示周日（用户 2026-09-17 两个开关；关掉后行数变少、
  /// 剩下的天重新等分可用高度，口径见 `domain/schedule_display_days.dart`）。
  final bool showSaturday;
  final bool showSunday;

  /// 显示表格线（用户 2026-09-17 第 3 条；开关在设置页「课表」节）。
  /// 口径与 [ScheduleGridView.showGridLines] 完全一致。
  final bool showGridLines;

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
    this.showSaturday = true,
    this.showSunday = true,
    this.showGridLines = true,
  });

  // ─── 布局常量 ─────────────────────────────────────────────────

  static const _dayLabelWidth = 36.0;
  static const _headerHeight = 40.0;
  static const _borderWidth = 0.5;

  /// 大间隔矮**列**的宽度（用户 2026-09-17 第 2 条；横版里「两行之间」= 「两列
  /// 之间」，故竖版插矮行、横版插矮列，同一个 [scheduleRows] 序列驱动）。
  ///
  /// 与竖版的矮行一样刻意不等比：午休 100 分钟比一节课还长，等比会画出一条
  /// 比课格还宽的列。窄列放不下 `1h40` 文案（表头格只有 8px 小字也不划算），
  /// 时长在表头的 `12:20` / `14:00` 两个时刻里已经读得出来。
  ///
  /// 宽度与竖版矮行同档（10/8）：矮列同样只是**纯错位量**，不涂底色、不写字，
  /// 跟着用户 2026-09-17 三轮「矮行太高」的口径一起收窄。
  static const _gapWidth = 10.0;
  static const _compactGapWidth = 8.0;

  /// 单元格内容按行高取舍的阈值（**恒适应高度**后行高可能很小，见 [build]）。
  ///
  /// 这些阈值是「不溢出」的硬约束：字号 11/9 时单行约 13/11px，
  /// 累加高度超过行高就会触发 RenderFlex overflow（用户 2026-09-15：
  /// 「横版课表永远适应宽度和高度」→ 只能靠取舍内容而不是裁剪/滚动）。
  static const _twoLineNameHeight = 56.0;
  static const _twoLineClassroomHeight = 46.0;
  static const _teacherHeight = 70.0;

  double _gapWidthOf(bool compact) => compact ? _compactGapWidth : _gapWidth;

  /// 表格线（用户 2026-09-17 第 3 条）；与竖版同口径：[BorderSide.none] = 不画。
  BorderSide _line(Color color) => showGridLines
      ? BorderSide(color: color, width: _borderWidth)
      : BorderSide.none;

  /// 落在跨 [span] 列课格**内部**的矮列总宽（口径同竖版的
  /// `ScheduleGridView._innerGapHeight`：不吸收就会整列错位）。
  double _innerGapWidth(int period, int span, double gapWidth, List<int> gapsAfter) {
    var total = 0.0;
    for (final p in gapsAfter) {
      if (p >= period && p <= period + span - 2) total += gapWidth;
    }
    return total;
  }

  // ─── 调色板 ───────────────────────────────────────────────────
  //
  // 课程底板 / 文字 12 色的**唯一实现**在 `schedule_tone.dart`
  // （`ScheduleTone.fill/text`）：浅色逐值不变，深色按色相自适应
  // （用户 2026-09-17：「课表的颜色没有做深色适配」）。别在这里再抄一份色表。

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
        // 可见天（用户 2026-09-17 两个开关）：关掉周六/周日 → 行数变少、
        // 剩下的行重新等分可用高度。
        final days = scheduleVisibleDays(
          showSaturday: showSaturday,
          showSunday: showSunday,
        );
        final dayCount = days.length;
        // 手机（短边 < 620）左右无边距、字号收紧；桌面保留 12。
        // 用**短边**判手机：手机横屏时宽度已经很大，按宽度会误判成桌面。
        final shortestSide = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final compact = shortestSide < ScheduleGridView.compactBreakpoint;
        final hPadding = compact ? 0.0 : 12.0;
        final vPadding = compact ? 6.0 : 12.0;

        // 大间隔矮列（用户 2026-09-17 第 2 条）：行序列 = 12 个节次列 + 空档超过
        // 1h 处的矮列。表头与每一行都按**同一份序列**渲染，否则整表错位。
        final rows = scheduleRows(periods);
        final gapsAfter = scheduleGapAfterPeriods(periods);
        final gapWidth = _gapWidthOf(compact);
        final gapTotal = gapsAfter.length * gapWidth;

        // **恒适应宽度**（用户 2026-09-15：「横版课表永远适应宽度和高度」）：
        // 12 个节次等分可用宽度（矮列先占掉固定宽度）→ 永不横向滚动。
        final rawCellWidth =
            (constraints.maxWidth - hPadding * 2 - _dayLabelWidth - gapTotal) /
            schedulePeriodCount;
        final cellWidth = rawCellWidth > 0 ? rawCellWidth : 1.0;
        // **恒适应高度**：可见天平分「表头 + 上下内边距」之外的剩余高度，
        // 不再 clamp 到最小行高（否则小窗口必然纵向溢出）。
        final rawRowHeight =
            (constraints.maxHeight - vPadding * 2 - _headerHeight) / dayCount;
        final rowHeight = rawRowHeight > 0 ? rawRowHeight : 1.0;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: hPadding,
            vertical: vPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderRow(
                context,
                cellWidth: cellWidth,
                rows: rows,
                gapWidth: gapWidth,
              ),
              ...List.generate(
                dayCount,
                (i) => _buildDayRow(
                  context,
                  days[i],
                  grid[days[i]],
                  rowHeight: rowHeight,
                  cellWidth: cellWidth,
                  onceMarks: onceMarks,
                  rows: rows,
                  gapsAfter: gapsAfter,
                  gapWidth: gapWidth,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── 表头行 ───────────────────────────────────────────────────

  /// 表头格里的小字钟点（上=上课、下=下课）；颜色由调用方按对比度给定
  /// （浅色 = `white70` 逐像素不变，深色 = 提亮红底上的近黑 70%）。
  Widget _headerTimeText(String value, Color color) => Text(
    value,
    style: TextStyle(
      color: color,
      fontSize: 8,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );

  Widget _buildHeaderRow(
    BuildContext context, {
    required double cellWidth,
    required List<ScheduleRow> rows,
    required double gapWidth,
  }) {
    // 表头是**实心底**：深浅两档都用原深色（[ScheduleTone.headerFill]）。
    // 深色下提亮成 `#D96363` 会让白字只剩 3.55:1、`onAccent` 翻成近黑字
    // （用户 2026-09-17：「顶部周几的文本不要用深灰，太暗」）。
    final headerColor = ScheduleTone.headerFill(context, ScheduleTone.headerRed);
    // 表头前景色按**实测对比度**择白 / 近黑（浅色恒为白 → 逐像素不变）。
    final foreground = AppColors.onAccent(context, headerColor);
    final foregroundSoft = foreground.withValues(alpha: 0.7);
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
                  color: ScheduleTone.header(context, ScheduleTone.headerRed),
                  size: 18,
                ),
              ),
            )
          else
            SizedBox(width: _dayLabelWidth, height: _headerHeight),
          // 12 节次表头：上课时间 / 节次 / 下课时间（用户 2026-09-16 裁定）
          // + 大间隔矮列（用户 2026-09-17 第 2 条）。
          for (final row in rows)
            if (row.isGap)
              // 矮列在表头里保持红底 → 红色表头带不被切断（它是「列」的分隔，
              // 不是「缺一块」），只是多出一点宽度把上下午错开。
              Container(
                key: Key('scheduleGapColumnAfter-${row.period}'),
                width: gapWidth,
                height: _headerHeight,
                decoration: BoxDecoration(
                  color: headerColor,
                  border: Border(right: _line(Colors.white24)),
                ),
              )
            else
              _buildPeriodHeaderCell(
                context,
                period: row.period,
                cellWidth: cellWidth,
                headerColor: headerColor,
                foreground: foreground,
                foregroundSoft: foregroundSoft,
              ),
        ],
      ),
    );
  }

  /// 单个节次表头格：上课时间 / 节次 / 下课时间。
  Widget _buildPeriodHeaderCell(
    BuildContext context, {
    required int period,
    required double cellWidth,
    required Color headerColor,
    required Color foreground,
    required Color foregroundSoft,
  }) {
    final slot = periods?.periodOf(period);
    return Container(
      key: Key('schedulePeriodHeaderCell-$period'),
      width: cellWidth,
      height: _headerHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // 红底随亮度提亮（深色下仍是可读的红，不糊在深色页面上）。
        color: headerColor,
        border: Border(right: _line(Colors.white24)),
      ),
      child: slot == null
          ? Text(
              '$period',
              style: TextStyle(
                color: foreground,
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
                  child: _headerTimeText(slot.start, foregroundSoft),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '$period',
                      style: TextStyle(
                        color: foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _headerTimeText(slot.end, foregroundSoft),
                ),
              ],
            ),
    );
  }

  // ─── 一天行 ───────────────────────────────────────────────────

  Widget _buildDayRow(
    BuildContext context,
    int day,
    Map<int, List<EffectiveClass>> dayData, {
    required double rowHeight,
    required double cellWidth,
    required Map<String, int> onceMarks,
    required List<ScheduleRow> rows,
    required List<int> gapsAfter,
    required double gapWidth,
  }) {
    final isWeekend = day >= 5;

    // 配色下标（**每门课一个不同的色**，用户 2026-09-17：「优先保证每门课程的颜色
    // 都不同，实在不行再重复」）：按整学期课程表算一份，本行的每个课格共用。
    // 口径与「为什么不能哈希取模」见 `schedule_color_index.dart`。
    final colorIndices = scheduleColorIndices(entries);

    // 被跨列占用的节次
    final occupied = <int, bool>{};
    // 被跨列课程吸收进自己格子的矮列（口径同竖版 `absorbedGaps`）
    final absorbedGaps = <int>{};
    final cells = <Widget>[];

    for (final row in rows) {
      if (row.isGap) {
        if (absorbedGaps.contains(row.period)) continue;
        cells.add(
          Container(
            // 与表头那颗同 Key（分属不同 Row，不冲突）：守卫测试靠它断言
            // 「表头 1 颗 + 每个可见天各 1 颗」。
            key: Key('scheduleGapColumnAfter-${row.period}'),
            width: gapWidth,
            height: rowHeight,
            decoration: BoxDecoration(
              // 与同一行的空格子同底色（用户 2026-09-17：「矮行颜色要与其他
              // 格子颜色一致，不显示内容文本」）—— 工作日透明、周末列有分区底。
              color: isWeekend ? AppColors.fill(context) : null,
              border: Border(
                right: _line(AppColors.fillStrong(context)),
                bottom: _line(AppColors.fillStrong(context)),
              ),
            ),
          ),
        );
        continue;
      }

      final period = row.period;
      if (occupied[period] == true) continue;

      final slots = dayData[period];
      if (slots == null || slots.isEmpty) {
        cells.add(
          _buildEmptyCell(
            context,
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
      for (int p = period + 1; p < period + span && p <= schedulePeriodCount; p++) {
        occupied[p] = true;
        if (gapsAfter.contains(p - 1)) absorbedGaps.add(p - 1);
      }

      cells.add(
        _buildCourseCell(
          context,
          slots: slots,
          span: span,
          day: day,
          period: period,
          height: rowHeight,
          width:
              cellWidth * span +
              _innerGapWidth(period, span, gapWidth, gapsAfter),
          onceMarks: onceMarks,
          colorIndices: colorIndices,
        ),
      );
    }

    return SizedBox(
      height: rowHeight,
      child: Row(
        children: [
          _buildDayLabel(context, day, isWeekend, height: rowHeight),
          ...cells,
        ],
      ),
    );
  }

  // ─── 星期标签 ─────────────────────────────────────────────────

  Widget _buildDayLabel(
    BuildContext context,
    int day,
    bool isWeekend, {
    required double height,
  }) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final date = weekMonday?.add(Duration(days: day));
    return Container(
      width: _dayLabelWidth,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // 周末列比工作日深一档（原来 `blueGrey.shade50` / `grey.shade50`）——
        // 深色下方向相反，故用 fill（分区）对 fillSoft（极淡）保持同一层级关系。
        color: isWeekend
            ? AppColors.fill(context)
            : AppColors.fillSoft(context),
        border: Border(
          right: _line(AppColors.stroke(context)),
          bottom: _line(AppColors.fillStrong(context)),
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
              color: AppColors.textMuted(context),
            ),
          ),
          if (date != null)
            Text(
              '${date.month}/${date.day}',
              style: TextStyle(
                fontSize: 8,
                color: AppColors.textMuted(context),
              ),
            ),
        ],
      ),
    );
  }

  // ─── 空节次格子 ───────────────────────────────────────────────

  Widget _buildEmptyCell(
    BuildContext context, {
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
          right: _line(AppColors.fillStrong(context)),
          bottom: _line(AppColors.fillStrong(context)),
        ),
        color: isWeekend ? AppColors.fill(context) : null,
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

  Widget _buildCourseCell(
    BuildContext context, {
    required List<EffectiveClass> slots,
    required int span,
    required int day,
    required int period,
    required double height,
    required double width,
    required Map<String, int> onceMarks,
    required Map<String, int> colorIndices,
  }) {
    final first = slots.first;
    final entry = first.entry;
    final classTime = first.classTime;
    final mark = first.mark;

    // 格内文字分两个角色（口径见 `schedule_tone.dart` 文件头）：
    //   nameColor = 课程名（深色下比正文色更柔）
    //   textColor = 次级行（教师 / 教室 / 周次）的**基准**色，下面再 withAlpha 淡化
    //
    // 色号 = **按课程身份发的号**（每门课一个不同的色，用户 2026-09-17），由调用方
    // 按整学期课程表算好传进来；取不到键时才回落到旧的哈希值（见 `colorIndices`）。
    final colorSeed =
        colorIndices[scheduleColorKeyOf(entry)] ??
        entry.courseCode.hashCode.abs();
    var bgColor = ScheduleTone.fill(context, colorSeed);
    var nameColor = ScheduleTone.name(context, colorSeed);
    var textColor = ScheduleTone.meta(context, colorSeed);

    switch (mark) {
      case EffectiveMark.movedAway:
        bgColor = AppColors.fillSoft(context);
        nameColor = AppColors.textMuted(context);
        textColor = AppColors.textMuted(context);
      case EffectiveMark.cancelled:
        bgColor = AppColors.fill(context);
        nameColor = AppColors.textMuted(context);
        textColor = AppColors.textMuted(context);
      case EffectiveMark.extra:
        if (first.reschedule?.courseCode.isEmpty ?? true) {
          // 补课格沿用课程调色板同族的浅绿底（浅色逐值不变；深色换成同色相实底）。
          bgColor = ScheduleTone.tintFill(
            context,
            ScheduleTone.extraFill,
            fp(context).makeUpClass,
          );
          nameColor = fp(context).makeUpClass;
          textColor = fp(context).makeUpClass;
        }
      case EffectiveMark.normal:
      case EffectiveMark.moved:
        break;
    }

    // 真实宽度由调用方给出（跨过矮列的课格已把它算进去，见 `_innerGapWidth`），
    // 不在这里按 `cellWidth * span` 重算。

    // 内容按行高取舍：行高被压缩（手机横屏）时少显示几行，绝不溢出。
    final nameLines = height >= _twoLineNameHeight ? 2 : 1;
    final classroomLines = height >= _twoLineClassroomHeight ? 2 : 1;
    final showTeacher = height >= _teacherHeight && (span >= 3 || width >= 180);
    final badge =
        rescheduleBadge(context, mark) ??
        rescheduleOnceBadge(
          context,
          onceMarks[classSlotKey(entry.courseCode, classTime)] ?? 0,
        );

    final card = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          // 「调课」格的橙色左边 = **语义标记线**，不属于表格线（表格线关掉照画）。
          left: mark == EffectiveMark.moved
              ? BorderSide(color: fp(context).reschedule, width: 2)
              : BorderSide.none,
          right: _line(AppColors.stroke(context)),
          bottom: _line(AppColors.stroke(context)),
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
                          color: nameColor,
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
                      style: TextStyle(
                        fontSize: 8,
                        color: fp(context).reschedule,
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
