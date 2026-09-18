import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule_engine.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_color_index.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_display_days.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_gap_rows.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_view_mode.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/reschedule_marks.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_paged_board.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_tone.dart';

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
    this.pagerWeekCount,
    this.pagerEnabled = true,
    this.pagerSmoothRequest = 0,
    this.onPagerWeekChanged,
    this.mondayOfWeek,
    this.showSaturday = true,
    this.showSunday = true,
    this.showGridLines = true,
  });

  /// 周视图分页：总周数（`null` = 不分页 —— 整学期视图、桌面端、横版视图）。
  ///
  /// 传入后本组件改用 [SchedulePagedBoard]：顶部表头原地不动、左侧节数列在
  /// 拖动时淡出，只有 7 天课格参与左右翻页（用户 2026-09-16 要求）。
  final int? pagerWeekCount;

  /// 手势翻页是否可用（桌面端 false → 只能靠外部改 [week]）。
  final bool pagerEnabled;

  /// 「平滑跳转」请求序号（长按回本周这类有意的跨周跳转要看得见翻页过程）：
  /// 原样透传给 [SchedulePagedBoard.smoothRequest] → [WeekPager.smoothRequest]。
  final int pagerSmoothRequest;

  /// 手势翻到某一周（相邻周由分页器内部手势触发）。
  final ValueChanged<int>? onPagerWeekChanged;

  /// 某一页的周一（分页后每页的列头日期不同）：`(week) => DateTime?`。
  final DateTime? Function(int week)? mondayOfWeek;

  /// 显示周六 / 显示周日（用户 2026-09-17 两个开关）。
  ///
  /// 关掉后天数变少、剩下的天**重新等分**可用宽度（口径见
  /// `domain/schedule_display_days.dart`）；只影响显示，课表数据本身不变。
  final bool showSaturday;
  final bool showSunday;

  /// 显示表格线（用户 2026-09-17 第 3 条；开关在设置页「课表」节）。
  ///
  /// 关掉后**所有**构成表格的分隔线都不画（节次列右线、行底线、课格右/底线、
  /// 表头里的白线）—— 表头色带与课格底色不受影响，仍然分得清列。
  /// **语义标记线照旧**：调课格的橙色上边（宽 2）、`调/停/补` 角标。
  final bool showGridLines;

  // ─── 布局常量 ─────────────────────────────────────────────────

  static const _periodLabelWidth = 36.0;
  static const _compactPeriodLabelWidth = 30.0;
  static const _headerHeight = 40.0;
  static const _compactHeaderHeight = 34.0;

  /// 单个节次的最小行高。**留够「课程名 + 教师 + 教室（两行）」**——
  /// 用户 2026-09-15 要求「课程教室不能在一行显示时自动换行」，
  /// 教室多占一行就必须多给高度，否则 RenderFlex 溢出。
  static const _cellMinHeight = 68.0;

  /// 手机端最小行高：**只作极端兜底**。
  ///
  /// 手机端行高**恒取适配值**（见 [_fitCellHeight]）——留下最小行高就意味着
  /// 「内容区偏矮的机型仍然放不下 12 节」。用户 2026-09-16 二轮原话：
  /// 「移动端依旧没有适应高度，内容还是超出屏幕范围」（上一版下限 52 仍偏高：
  /// 减去状态栏 / 标题栏 / 系统导航栏后，不少机型的内容区不足 664dp）。
  static const _compactCellMinHeight = 40.0;

  static const _borderWidth = 0.5;

  /// 大间隔矮行的高度（用户 2026-09-17 第 2 条：「任意两行之间的时间间隔一旦
  /// 超过了 1h，就在这两行之间插一个矮行」）。
  ///
  /// 刻意**不按空档时长等比缩放**：午休 100 分钟比一节课（45 分钟）还长，
  /// 等比画出来会是一条比课格还高的行，与「矮行」的语义相反。凡是超过阈值的
  /// 空档一律同样矮。
  ///
  /// 高度 = **纯错位量**（10/8）：矮行既不涂底色、也不写时长文案（用户
  /// 2026-09-17 二轮：「矮行颜色要与其他格子颜色一致，不显示内容文本」），
  /// 现在唯一的作用是把上下午 / 晚间的节次行错开。首版 18/14 是为了放那条
  /// 8px 的时长文案，文案删掉后就成了白占高度的一条空带 —— 用户 2026-09-17
  /// 三轮当场指出「矮行太高」。
  static const _gapHeight = 10.0;
  static const _compactGapHeight = 8.0;

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
  double _gapHeightOf(bool compact) => compact ? _compactGapHeight : _gapHeight;

  /// 表格线（用户 2026-09-17 第 3 条）。
  ///
  /// 关掉表格线时统一返回 [BorderSide.none]（宽 0、不画）—— 所有**构成表格的**
  /// 分隔线都从这里出，别在下面各写一处 `BorderSide(...)`，否则开关会漏。
  BorderSide _line(Color color) => showGridLines
      ? BorderSide(color: color, width: _borderWidth)
      : BorderSide.none;

  /// 落在跨 [span] 节课格**内部**的矮行总高。
  ///
  /// 课格高度必须把它算进去：`5-6 节`这种跨过午休的课一旦只画 `cellHeight * 2`，
  /// 那一列就比别的列矮一个矮行，整表从第 6 节起错位。
  /// 内部 = 边界 p 满足 `period ≤ p ≤ period + span - 2`（首行之前、末行之后不算）。
  double _innerGapHeight(int period, int span, double gapHeight, List<int> gapsAfter) {
    var total = 0.0;
    for (final p in gapsAfter) {
      if (p >= period && p <= period + span - 2) total += gapHeight;
    }
    return total;
  }

  /// 单个节次的最小行高（教室要能换行，见 [_cellMinHeight] 注释）。
  double _minCellHeightOf(bool compact) =>
      compact ? _compactCellMinHeight : _cellMinHeight;

  /// 实际行高：**有空间就把 12 行撑满可用高度**（不留底部空档）。
  ///
  /// 手机端（[compact]）**恒取适配行高**：不管内容区多矮，12 节都必须一屏看完
  /// —— 用户 2026-09-16 二轮：「移动端依旧没有适应高度，内容还是超出屏幕范围」。
  /// 桌面端保留 `_cellMinHeight` 下限（不够就纵向滚动，桌面滚动是常态）。
  double _fitCellHeight({
    required bool compact,
    required double maxHeight,
    required double verticalPadding,
    required double gapTotal,
    double? bottomPadding,
  }) {
    // 分页模式下底部不留白（用户 2026-09-16：「竖排课表高度与屏幕同高」），
    // 故底部内边距单独可调；不传时与旧行为完全一致（上下同值）。
    // [gapTotal] = 插入的矮行总高：**必须先扣掉**，否则 12 节 + 矮行会超出内容区。
    final available =
        maxHeight -
        verticalPadding -
        (bottomPadding ?? verticalPadding) -
        _headerHeightOf(compact) -
        gapTotal;
    final fitted = available / schedulePeriodCount;
    if (fitted <= 0) return _minCellHeightOf(compact);
    if (compact) return fitted;
    return fitted > _cellMinHeight ? fitted : _cellMinHeight;
  }

  // ─── 调色板 ───────────────────────────────────────────────────
  //
  // 课程底板 / 文字 12 色的**唯一实现**已提到 `schedule_tone.dart`
  // （`ScheduleTone.fill/text`）：浅色逐值不变，深色按色相自适应
  // （用户 2026-09-17：「课表的颜色没有做深色适配」）。别在这里再抄一份色表。

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
        // 可见天（用户 2026-09-17 的两个开关）：关掉周六 / 周日 → 列数变少、
        // 剩下的天重新等分可用宽度（表头、空格子、课格全都按这份列表走）。
        final days = scheduleVisibleDays(
          showSaturday: showSaturday,
          showSunday: showSunday,
        );
        final dayCount = days.length;
        // 手机判定用**短边**：手机横屏时宽度已过断点，按宽度会误判成桌面。
        final shortestSide = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final compact = shortestSide < compactBreakpoint;
        // 手机端左右无边距（用户 2026-09-15 要求），桌面端保留 12。
        final hPadding = compact ? 0.0 : 12.0;
        final labelWidth = _labelWidth(compact);
        final available = constraints.maxWidth - hPadding * 2;
        final rawColWidth = (available - labelWidth) / dayCount;
        // 手机：列宽 = 可用宽度 / 可见天数 → 整表恰好铺满屏宽；
        // 桌面：80~160 之间自适应屏宽，越界不再拉伸 / 不足则横向滚动。
        final colWidth = compact
            ? (rawColWidth > 0 ? rawColWidth : _minColWidth)
            : rawColWidth.clamp(_minColWidth, _maxColWidth);
        final totalWidth = labelWidth + dayCount * colWidth;
        final fitsWidth = totalWidth <= available + 0.5;

        final verticalPadding = compact ? 6.0 : 12.0;
        // 周视图分页（手机竖版）：表头静态 + 节数列拖动淡出 + 只有主体翻页。
        final pagerOn = pagerWeekCount != null && fitsWidth;
        // 大间隔矮行（用户 2026-09-17 第 2 条）：行序列 = 12 个节次行 + 空档超过
        // 1h 处的矮行。节次列与每一天列都按**同一份序列**渲染，否则整表错位。
        final rows = scheduleRows(periods);
        final gapsAfter = scheduleGapAfterPeriods(periods);
        final gapHeight = _gapHeightOf(compact);
        final gapTotal = gapsAfter.length * gapHeight;
        // 行高：手机端恒取适配值把 12 节铺满可用高度（见 [_fitCellHeight]）。
        //
        // ⚠ **不要**在这里再扣一次底部系统栏（导航栏 / 手势条）：
        // `Scaffold` **不会**替 body 让出导航栏 ——
        // `flutter/lib/src/material/scaffold.dart:3187-3190` 把 `minInsets.bottom`
        // 覆写成键盘高度（`viewInsets.bottom`）或 `0.0`，系统栏只进 `minViewPadding`
        // （那里的注释写明它仅供 FAB / SnackBar 定位）。本应用是 edge-to-edge
        // （见 `home_screen.dart` 的「底部不留 SafeArea」口径），导航栏**盖在内容上**
        // → 让位由**页面级**的 `ScheduleBodyArea`（`SafeArea(top: false)`）负责，
        // 走到这里的 `constraints.maxHeight` 已经是「导航栏以上」的高度
        // （用户 2026-09-17：「课表适应高度不要包括底部三键导航的部分」）。
        // 在这里再扣一次会在底部白留 40~48dp。
        final cellHeight = _fitCellHeight(
          compact: compact,
          maxHeight: constraints.maxHeight,
          verticalPadding: verticalPadding,
          gapTotal: gapTotal,
          bottomPadding: pagerOn ? 0 : null,
        );

        final gridContent = SizedBox(
          width: totalWidth,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPeriodLabelColumn(
                  context,
                  compact: compact,
                  cellHeight: cellHeight,
                  rows: rows,
                  gapHeight: gapHeight,
                ),
                ...List.generate(
                  dayCount,
                  (i) => _buildDayColumn(
                    context,
                    days[i],
                    grid[days[i]],
                    colWidth: colWidth,
                    compact: compact,
                    cellHeight: cellHeight,
                    onceMarks: onceMarks,
                    rows: rows,
                    gapsAfter: gapsAfter,
                    gapHeight: gapHeight,
                  ),
                ),
              ],
            ),
          ),
        );

        if (pagerOn) {
          // 分页板：顶部表头（左上角格 + 7 个「周一…周日」）静止不动，
          // 左侧节数列在拖动时淡出、松手后恢复，只有 7 天课格随手指翻页。
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              hPadding,
              verticalPadding,
              hPadding,
              0,
            ),
            child: Center(
              child: SizedBox(
                width: totalWidth,
                child: SchedulePagedBoard(
                  weekCount: pagerWeekCount!,
                  week: week ?? 1,
                  enabled: pagerEnabled,
                  smoothRequest: pagerSmoothRequest,
                  onWeekChanged: onPagerWeekChanged ?? (int _) {},
                  bodyHeight: schedulePeriodCount * cellHeight + gapTotal,
                  // 节数列宽度：分页板靠它给每页左侧留出占位，使 7 天课格
                  // 与静态表头的列严格对齐（页面占满整块宽度 → 拖动时
                  // 「节数列那一栏」下面就是滑动中的课表）。
                  leadingWidth: labelWidth,
                  header: Row(
                    children: [
                      _buildCornerCell(context, compact: compact),
                      for (final day in days)
                        _buildDayHeader(
                          context,
                          day,
                          colWidth: colWidth,
                          compact: compact,
                        ),
                    ],
                  ),
                  leading: _buildPeriodLabelColumn(
                    context,
                    compact: compact,
                    cellHeight: cellHeight,
                    rows: rows,
                    gapHeight: gapHeight,
                    includeCorner: false,
                  ),
                  pageBuilder: (context, w) => _buildDayRow(
                    context,
                    week: w,
                    grid: _buildGrid(w),
                    days: days,
                    colWidth: colWidth,
                    compact: compact,
                    cellHeight: cellHeight,
                    onceMarks: onceMarks,
                    rows: rows,
                    gapsAfter: gapsAfter,
                    gapHeight: gapHeight,
                  ),
                ),
              ),
            ),
          );
        }

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
  Widget _periodTimeText(
    BuildContext context,
    String value, {
    required bool compact,
  }) => Text(
    value,
    style: TextStyle(
      fontSize: compact ? 7.5 : 8.5,
      height: 1.2,
      color: AppColors.textMuted(context),
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );

  /// 左上角格：切换横/竖版按钮（手机端按横竖屏自动切视图 → 不渲染按钮）。
  ///
  /// 分页模式（[SchedulePagedBoard]）把它放进**静态表头行**，节数列则用
  /// `includeCorner: false` 只画 12 个节次格。
  Widget _buildCornerCell(BuildContext context, {required bool compact}) {
    final labelWidth = _labelWidth(compact);
    final headerHeight = _headerHeightOf(compact);
    if (!showToggle) {
      return SizedBox(width: labelWidth, height: headerHeight);
    }
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        width: labelWidth,
        height: headerHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: _line(AppColors.fillStrong(context)),
          ),
        ),
        child: Icon(
          isHorizontal ? Icons.view_day : Icons.view_week,
          color: ScheduleTone.header(context, ScheduleTone.headerRed),
          size: compact ? 16 : 18,
        ),
      ),
    );
  }

  /// 节次格显示「上课时间 + 节数 + 下课时间」所需的最小行高。
  ///
  /// 三行文字（时间 7.5 + 节数 10.5 + 时间 7.5，含 3+3 内边距）≈ 37dp；
  /// 行高被压到 30dp（内容区 400dp 的矮屏）时留着时间会
  /// `A RenderFlex overflowed by 0.5 pixels on the bottom.` → 退回只显示节数。
  static const double _periodTimeMinCellHeight = 46.0;

  Widget _buildPeriodLabelColumn(
    BuildContext context, {
    required bool compact,
    required double cellHeight,
    required List<ScheduleRow> rows,
    required double gapHeight,
    bool includeCorner = true,
  }) {
    final labelWidth = _labelWidth(compact);

    return Column(
      children: [
        // 左上角：切换横/竖版按钮（手机端按横竖屏自动切视图，故不渲染按钮）
        // [includeCorner] = false 时分页板已把左上角放进**静态表头行**，
        // 这里只画 12 个节次格（否则会多出一格、与表头错位）。
        if (!includeCorner)
          const SizedBox.shrink()
        else
          _buildCornerCell(context, compact: compact),
        // 12 节标签 + 大间隔矮行：上课时间 / 节次 / 下课时间（用户 2026-09-16 裁定）
        for (final row in rows)
          if (row.isGap)
            _buildGapLabelCell(
              context,
              afterPeriod: row.period,
              labelWidth: labelWidth,
              height: gapHeight,
            )
          else
            _buildPeriodLabelCell(
              context,
              period: row.period,
              labelWidth: labelWidth,
              cellHeight: cellHeight,
              compact: compact,
            ),
      ],
    );
  }

  /// 单个节次格：上课时间 / 节次 / 下课时间。
  Widget _buildPeriodLabelCell(
    BuildContext context, {
    required int period,
    required double labelWidth,
    required double cellHeight,
    required bool compact,
  }) {
    final slot = periods?.periodOf(period);
    return Container(
      key: Key('schedulePeriodCell-$period'),
      width: labelWidth,
      height: cellHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(
          right: _line(AppColors.stroke(context)),
          bottom: _line(AppColors.fillStrong(context)),
        ),
        // 12 个节次格**底色一致**（用户 2026-09-16：「课表第五行的颜色和其他行
        // 不一样」）—— 从前第 5 节格外加了一层浅灰填充作「午休分隔」，
        // 用户视作异常，已去掉；**别再加任何行底色**。深色迁移时同理：
        // 这里只把边框换成 `AppColors` 的角色色，`color` 恒为 null。
        //
        // 注意「午休分隔」现在由**独立的矮行**承担（用户 2026-09-17 第 2 条要求
        // 插矮行）——那是另一个 widget（[_buildGapLabelCell]），不是给本节次格
        // 涂色，两者别混。
      ),
      child: slot == null || cellHeight < _periodTimeMinCellHeight
          ? Text(
              '$period',
              style: TextStyle(
                fontSize: compact ? 10.5 : 12,
                color: AppColors.textMuted(context),
                fontWeight: FontWeight.w500,
              ),
            )
          : Column(
              // 时间贴格子上下两端，节数居中（用户 2026-09-16：「时间显示在
              // 格子两端，而不是紧贴节数号」）——中间用 Expanded 撑开。
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: _periodTimeText(context, slot.start, compact: compact),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '$period',
                      style: TextStyle(
                        fontSize: compact ? 10.5 : 12,
                        color: AppColors.textMuted(context),
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: _periodTimeText(context, slot.end, compact: compact),
                ),
              ],
            ),
    );
  }

  /// 矮行在节次列里的那一格：**空着**。
  ///
  /// 用户 2026-09-17：「矮行颜色要与其他格子颜色一致，不显示内容文本」
  /// → 去掉底色（跟其它节次格一样透明，只有边框）、去掉 `1h40` 文案。
  /// 矮行仍占 [gapHeight] 的高度，作用只剩「把上下午/晚间的节次行错开」。
  /// 时长文案的纯函数 [scheduleGapLabel] 保留在 domain（供将来复用与测试），
  /// 只是**不再渲染**。
  Widget _buildGapLabelCell(
    BuildContext context, {
    required int afterPeriod,
    required double labelWidth,
    required double height,
  }) => Container(
    key: Key('scheduleGapRowAfter-$afterPeriod'),
    width: labelWidth,
    height: height,
    decoration: BoxDecoration(
      // 无底色（与 [_buildPeriodLabelCell] 一致：`color` 恒为 null）。
      border: Border(
        right: _line(AppColors.stroke(context)),
        bottom: _line(AppColors.fillStrong(context)),
      ),
    ),
  );

  // ─── 一天列 ───────────────────────────────────────────────────

  Widget _buildDayColumn(
    BuildContext context,
    int day,
    Map<int, List<EffectiveClass>> dayData, {
    required double colWidth,
    required bool compact,
    required double cellHeight,
    required Map<String, int> onceMarks,
    required List<ScheduleRow> rows,
    required List<int> gapsAfter,
    required double gapHeight,
    bool includeHeader = true,
    DateTime? mondayOf,
  }) {
    // 预计算每个节次是否被上方跨行课程占用
    final occupied = <int, bool>{};
    // 被跨行课程「吸收」进自己格子的矮行（它前后的节次属于同一门课时，
    // 矮行高度已经算进那一格，不能再单独画一行，否则整列会多出一个矮行的高度）。
    final absorbedGaps = <int>{};
    final widgets = <Widget>[];

    // 配色下标（**每门课一个不同的色**，用户 2026-09-17：「优先保证每门课程的颜色
    // 都不同，实在不行再重复」）：按整学期课程表算一份，本列的每个课格共用。
    // 口径与「为什么不能哈希取模」见 `schedule_color_index.dart`。
    final colorIndices = scheduleColorIndices(entries);

    // 表头（分页模式下表头被提到静态行走，这里传 includeHeader: false）
    if (includeHeader) {
      widgets.add(
        _buildDayHeader(
          context,
          day,
          colWidth: colWidth,
          compact: compact,
          mondayOf: mondayOf,
        ),
      );
    }

    // 逐行构建（行序列 = 12 个节次行 + 大间隔矮行，见 `scheduleRows`）
    for (final row in rows) {
      if (row.isGap) {
        if (absorbedGaps.contains(row.period)) continue;
        widgets.add(
          _buildGapCell(
            context,
            afterPeriod: row.period,
            colWidth: colWidth,
            height: gapHeight,
          ),
        );
        continue;
      }

      final period = row.period;
      if (occupied[period] == true) continue;

      final slots = dayData[period];
      if (slots == null || slots.isEmpty) {
        widgets.add(
          _buildEmptyCell(
            context,
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

      // 标记后续节次为已占用；跨过的矮行一并标成「已被吸收」
      for (int p = period + 1; p < period + span && p <= schedulePeriodCount; p++) {
        occupied[p] = true;
        if (gapsAfter.contains(p - 1)) absorbedGaps.add(p - 1);
      }

      widgets.add(
        _buildCourseCell(
          context,
          slots: slots,
          span: span,
          day: day,
          period: period,
          colWidth: colWidth,
          compact: compact,
          cellHeight: cellHeight,
          cellSpanHeight:
              cellHeight * span +
              _innerGapHeight(period, span, gapHeight, gapsAfter),
          onceMarks: onceMarks,
          colorIndices: colorIndices,
        ),
      );
    }

    return SizedBox(
      width: colWidth,
      child: Column(children: widgets),
    );
  }

  /// 分页页主体：某一周的课格（**不含表头** —— 表头由静态表头行负责）。
  Widget _buildDayRow(
    BuildContext context, {
    required int week,
    required List<Map<int, List<EffectiveClass>>> grid,
    required List<int> days,
    required double colWidth,
    required bool compact,
    required double cellHeight,
    required Map<String, int> onceMarks,
    required List<ScheduleRow> rows,
    required List<int> gapsAfter,
    required double gapHeight,
  }) {
    return Row(
      // 每页一个 Key：便于量测「当前周主体」的位移（守卫测试与排障用）
      key: Key('scheduleWeekRow-$week'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final day in days)
          _buildDayColumn(
            context,
            day,
            grid[day],
            colWidth: colWidth,
            compact: compact,
            cellHeight: cellHeight,
            onceMarks: onceMarks,
            rows: rows,
            gapsAfter: gapsAfter,
            gapHeight: gapHeight,
            includeHeader: false,
          ),
      ],
    );
  }

  // ─── 表头 ─────────────────────────────────────────────────────

  Widget _buildDayHeader(
    BuildContext context,
    int day, {
    required double colWidth,
    required bool compact,
    DateTime? mondayOf,
  }) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final isWeekend = day >= 5;
    final date = (mondayOf ?? weekMonday)?.add(Duration(days: day));
    // 表头是**实心底**：深浅两档都用原深色（[ScheduleTone.headerFill]）。
    // 深色下**不许**按「文字色」提亮 —— 提亮成 `#D96363` 后白字只剩 3.55:1，
    // [AppColors.onAccent] 会择近黑字，用户 2026-09-17 当场报
    // 「顶部周几的文本不要用深灰，太暗」。深红 `#C62828` 白字 5.62:1 ✓。
    final headerColor = ScheduleTone.headerFill(
      context,
      isWeekend ? ScheduleTone.weekendHeader : ScheduleTone.headerRed,
    );
    // 表头前景色按**实测对比度**择白 / 近黑（浅色恒为白 → 逐像素不变）。
    final foreground = AppColors.onAccent(context, headerColor);

    return Container(
      width: colWidth,
      height: _headerHeightOf(compact),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // 红底 / 蓝灰底都随亮度提亮（深色下原来的 `blueGrey.shade700` 会糊在
        // 深色页面上 —— 用户 2026-09-17 报的深色适配问题之一）。
        color: headerColor,
        // 表头里的白色竖线也属于「表格线」，跟着开关一起消失。
        border: Border(bottom: _line(Colors.white24)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            names[day],
            style: TextStyle(
              color: foreground,
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
                color: foreground.withValues(alpha: 0.7),
                fontSize: compact ? 8 : 9,
                height: 1.2,
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
    required double colWidth,
    required bool compact,
    required double cellHeight,
  }) {
    // 空格子与其他行**同底色**（用户 2026-09-16 裁定：第 5 行不该长得不一样）。
    final cell = Container(
      width: colWidth,
      height: cellHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: _line(AppColors.fillStrong(context)),
          right: _line(AppColors.fillStrong(context)),
        ),
      ),
    );
    if (onTapEmptySlot == null) return cell;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTapEmptySlot!(DayOfWeek.values[day], period),
      child: cell,
    );
  }

  /// 大间隔矮行在课格区里的那一格（用户 2026-09-17 第 2 条）。
  ///
  /// 它**不是一个节次**：不可点（点它不会新建课程）、不参与跨行占用 ——
  /// 跨过它的课会把它的高度吸收进课格（见 `_buildDayColumn` 的 `absorbedGaps`）。
  ///
  /// 用户 2026-09-17 追加：「矮行颜色要与其他格子颜色一致，不显示内容文本」
  /// → **不再涂任何底色**（原先用 [AppColors.fill] 画一条分区带），边框与
  /// [_buildEmptyCell] 逐值相同；整行的辨识度只剩「一截空白 + 上下两条行线」。
  Widget _buildGapCell(
    BuildContext context, {
    required int afterPeriod,
    required double colWidth,
    required double height,
  }) => Container(
    // 与节次列那颗同 Key（它们分属不同的 Column，不冲突）：守卫测试靠它断言
    // 「节次列 1 颗 + 每个可见天各 1 颗」。
    key: Key('scheduleGapRowAfter-$afterPeriod'),
    width: colWidth,
    height: height,
    decoration: BoxDecoration(
      // 无 color：与空格子一致（透明 → 露出页面底）。
      border: Border(
        bottom: _line(AppColors.fillStrong(context)),
        right: _line(AppColors.fillStrong(context)),
      ),
    ),
  );

  // ─── 课程格子 ─────────────────────────────────────────────────

  Widget _buildCourseCell(
    BuildContext context, {
    required List<EffectiveClass> slots,
    required int span,
    required int day,
    required int period,
    required double colWidth,
    required bool compact,
    required double cellHeight,
    required double cellSpanHeight,
    required Map<String, int> onceMarks,
    required Map<String, int> colorIndices,
  }) {
    final first = slots.first;
    final entry = first.entry;
    final classTime = first.classTime;
    final mark = first.mark;

    // 颜色：调课后的课沿用课程自身颜色，便于认出是哪门课
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
          // 补课格沿用课程调色板同族的浅绿底（浅色逐值不变；深色换成同色相实底，
          // 文字色随亮度提亮 —— 用户 2026-09-17：「课表的颜色没有做深色适配」）。
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

    // 课格的真实高度由调用方给出（[cellSpanHeight]）：跨过矮行的课格已把矮行
    // 高度算进去（见 `_innerGapHeight`），不在这里按 `cellHeight * span` 重算。

    // 周次信息（区间 + 单双周）**只在整学期视图显示**（用户 2026-09-15 裁定）：
    // 周视图已按该教学周过滤，格子里出现的都是本周真要上的课，周次字样是冗余信息。
    final showWeekInfo = week == null;

    // 单双周标签
    final weekLabel = classTime.weekParity != WeekParity.every
        ? ' (${classTime.weekParity.displayName})'
        : '';

    // 教室放不下整行时**换行**（用户 2026-09-15：「课表中的课程教室不能在一行
    // 显示时，自动换行」）；同格有多门课时留给「分隔线 + 第二门课」的位置，
    // 此时教室仍限一行。
    //
    // 手机端行高被压扁（矮屏机型要一屏看完 12 节）时**按格子总高分配内容行**：
    // 单节格子 30dp 就只剩课名，跨 2 节的 60dp 能放课名 + 教师 + 教室。
    // 判据用 `cellHeight * span`（格子真实高度）而不是单节行高 —— 否则跨节格子
    // 明明有空间也被砍内容，或反过来溢出（用户 2026-09-16 二轮：「内容还是
    // 超出屏幕范围」，实测 400dp 内容区曾 `RenderFlex overflowed by 0.5 pixels`）。
    final spanHeight = cellHeight * span;
    final roomy = spanHeight >= 100;
    final nameLines = span > 1 ? (roomy ? 3 : (spanHeight >= 74 ? 2 : 1)) : 1;
    final showTeacher = spanHeight >= 58;
    final showClassroom = spanHeight >= 48;
    final classroomLines = slots.length > 1 ? 1 : (spanHeight >= 56 ? 2 : 1);

    // 角标：调 / 停 / 补；整学期视图下若无标记则用「单次调整」提示角标
    final badge =
        rescheduleBadge(context, mark) ??
        rescheduleOnceBadge(
          context,
          onceMarks[classSlotKey(entry.courseCode, classTime)] ?? 0,
        );

    final card = Container(
      width: colWidth,
      height: cellSpanHeight,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          // 「调课」格的橙色上边是**语义标记线**，不属于表格线：表格线关掉它也照画。
          top: mark == EffectiveMark.moved
              ? BorderSide(color: fp(context).reschedule, width: 2)
              : BorderSide.none,
          bottom: _line(AppColors.stroke(context)),
          right: _line(AppColors.stroke(context)),
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
            // 教师（紧凑格且只跨 1 节时省掉，见 `tight`）
            if (showTeacher)
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
              if (showClassroom) ...[
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
              ],
            ] else if (showClassroom)
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
                  color: fp(context).reschedule,
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
  List<Map<int, List<EffectiveClass>>> _buildGrid([int? forWeek]) {
    final grid = List.generate(7, (_) => <int, List<EffectiveClass>>{});

    final classes = effectiveClasses(
      entries: entries,
      reschedules: reschedules,
      week: forWeek ?? week,
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
