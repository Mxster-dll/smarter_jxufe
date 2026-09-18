/// 课表页标题栏：学期 + 周次切换。
///
/// 学期选择按平台分形态（用户 2026-09-15 口径）：
/// - **手机端**（[ScheduleTitleBar.compact]）＝ 一个显示学期码 `xxy` 的按钮
///   （`SchoolTermCodeButton`），点开 `showSchoolTermPicker` 的 3×N 阵列
///   （`SchoolTermGrid`：行 = 学段、列 = 学年，范围 = 入学年 ~ 当前学年）；
/// - **桌面端** ＝ 学年选择器（`AcademicYearPicker`）+ 学段下拉。
///
/// 单行 / 两行**按可用宽度自适应**（用户 2026-09-15 问「为什么学期选择和
/// 周数显示不在同一行」—— 从前这里写死两行 `Column[Row(学年+学段), 周次行]`，
/// 桌面端白白浪费一行高度；手机竖屏（可用宽度约 200dp）确实放不下，仍需两行）。
///
/// 抽成独立组件的目的：**可测**。判定与渲染在同处，`test/schedule_title_bar_test.dart`
/// 能用真实渲染宽度断言「宽屏同一行 / 窄屏两行」，不必拉起整个课表页（那要伪造
/// 学籍与课表仓库）。
///
/// 正文的筛选栏（`ScheduleScreen.showAppBar == false` 时）复用学年 / 学段两个选择器。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart'
    show schoolTermCode;
import 'package:smarter_jxufe/shared/widgets/academic_year_picker.dart';
import 'package:smarter_jxufe/shared/widgets/school_term_grid.dart';

import 'schedule_week_picker.dart';

/// 标题栏内容（学期选择器 + 周次切换）的 Key。
///
/// 桌面端整组居中后，`ScheduleTitleBar` 自身的 RenderBox 会**撑满 AppBar 标题槽**
/// （`Center` 默认填满可用宽度），量「内容真实宽度」必须量这个 Key 而不是组件类型
/// —— `test/schedule_title_bar_test.dart` 的不变式用例与居中用例都按它断言。
const Key scheduleTitleContentKey = Key('scheduleTitleContent');

/// 学段选择器：手机端显示缩写（一学期/二学期/二阶段）省宽度，菜单里始终全称。
class ScheduleSemesterSelector extends StatelessWidget {
  const ScheduleSemesterSelector({
    super.key,
    required this.selectedSemester,
    required this.compact,
    required this.onChanged,
  });

  final String selectedSemester;
  final bool compact;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const values = ['0', '1', '2'];
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selectedSemester,
        isDense: true,
        iconSize: compact ? 18 : 22,
        style: TextStyle(
          fontSize: compact ? 11.5 : 13,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        selectedItemBuilder: (context) => [
          for (final v in values)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                compact
                    ? xqShortName(int.parse(v))
                    : xqDisplayName(int.parse(v)),
              ),
            ),
        ],
        items: [
          for (final v in values)
            DropdownMenuItem(
              value: v,
              child: Text(xqDisplayName(int.parse(v))),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// 周次切换：只显示 `第 N 周`（点击开周数选择器、**长按回本周**）。
///
/// 用户 2026-09-16 三条裁定叠在这一个控件上：
/// ①「取消周数的左右按钮，但是点击周数，显示一个周数选择器，要可以输入周数 /
///   点击直接选择周数」——`‹ ›` 已删，逐周前后翻靠**课表左右滑动**（`WeekPager`）；
/// ②「整学期视图下，不要显示『整学期』字样」——`week == null` 时本控件
///   **整个不渲染**（回周视图靠标题栏右侧的视图切换按钮）；
/// ③「标题栏中不显示本周按钮，但是当前周数如果是本周的话，则高亮；同时，长按
///   周数可以回到本周」——`本周` 按钮已删，改为主色高亮 + `onLongPress`；
/// ④ 用户 2026-09-17：「长按周数返回本周要显示横划动画」——长按走
///   [onReturnToCurrentWeek]（课表页据此请求分页器横划过去），未传时退回
///   [onGoToWeek]（默认直接跳）。
///
/// 首/末周边界由调用方在 [onGoToWeek] 里夹取（`clampTeachingWeek`）。
class ScheduleWeekSwitcher extends StatelessWidget {
  const ScheduleWeekSwitcher({
    super.key,
    required this.week,
    required this.currentWeek,
    required this.isCurrentTerm,
    required this.compact,
    required this.lastWeek,
    required this.onGoToWeek,
    this.onReturnToCurrentWeek,
    this.mondayOf,
    this.onToggleView,
  });

  /// 正在展示的教学周；null = 整学期视图（此时不渲染任何东西）。
  final int? week;
  final int? currentWeek;
  final bool isCurrentTerm;
  final bool compact;
  final ValueChanged<int> onGoToWeek;

  /// 长按周数回本周时走这里（可缺省 = 退回 [onGoToWeek]）。
  ///
  /// 单独一条回调是因为**回本周是一次有意的跨周跳转**：课表页要让分页器横划
  /// 过去（用户 2026-09-17），而弹窗选周 / 切学期仍是直接跳 —— 两者都走
  /// `onGoToWeek`，分不出意图。
  final ValueChanged<int>? onReturnToCurrentWeek;

  /// 视图切换按钮（周视图 / 整学期）。
  ///
  /// **标题栏里不传**：用户 2026-09-16「切换整学期/周视图的按钮和调课按钮放到
  /// 一起，而不是居中」→ 它在 `ScheduleScreen` 的 `actions` 里；只有正文筛选栏
  /// （`showAppBar == false`）仍把按钮留在这里。
  final VoidCallback? onToggleView;

  /// 本周期最后教学周（周数选择器的范围；来自 `resolveLastTeachingWeek`）。
  final int lastWeek;

  /// 第 N 周的周一（用于选择器里显示日期范围），可缺。
  final DateTime? Function(int week)? mondayOf;

  /// 当前显示的周就是本周（用来高亮）。
  bool get _isCurrent =>
      week != null &&
      isCurrentTerm &&
      currentWeek != null &&
      week == currentWeek;

  Future<void> _pickWeek(BuildContext context) async {
    final picked = await showScheduleWeekPicker(
      context,
      week: week ?? currentWeek ?? 1,
      lastWeek: lastWeek,
      currentWeek: currentWeek,
      mondayOf: mondayOf,
      compact: compact,
    );
    if (picked != null) onGoToWeek(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = week;
    if (w == null && onToggleView == null) {
      // 整学期视图 + 标题栏（按钮在 actions 里）→ 什么都不显示。
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (w != null)
          // 周数文字本身即入口（无边框、无箭头，与学期码按钮同形态）。
          Tooltip(
            message: '选择周数 · 长按回到本周',
            child: InkWell(
              key: scheduleWeekButtonKey,
              borderRadius: BorderRadius.circular(8),
              onTap: () => _pickWeek(context),
              // 长按回本周（用户 2026-09-16：「长按周数可以回到本周」）——
              // 取代从前的「本周」按钮；用户 2026-09-17 追加要求这次跳转
              // **横划过去**，故优先走 `onReturnToCurrentWeek`。
              onLongPress: () {
                if (isCurrentTerm && currentWeek != null) {
                  (onReturnToCurrentWeek ?? onGoToWeek)(currentWeek!);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: _isCurrent
                    ? BoxDecoration(
                        color: AppColors.tint(context, scheme.primary, 0.12),
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: Text(
                  '第 $w 周',
                  style: TextStyle(
                    fontSize: compact ? 12 : 13,
                    fontWeight: _isCurrent ? FontWeight.w700 : FontWeight.w600,
                    color: _isCurrent ? scheme.primary : scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        if (onToggleView != null)
          scheduleBarAction(
            icon: w == null ? Icons.view_week : Icons.grid_view,
            tooltip: w == null ? '切换到周视图' : '切换到整学期视图',
            compact: compact,
            onPressed: onToggleView!,
          ),
      ],
    );
  }
}

/// 标题栏内容（学年 + 学段 + 周次），宽度够则一行。
///
/// **手机端（[compact]）= 学年 + 学段合并成一个学期码按钮**（用户 2026-09-15：
/// 「把手机端的课表的学年选择器和学期下拉列表改成一个显示学期的按钮，显示格式
/// 也是 xxy，然后点击显示这个学期选择器，范围设为入学年份-当前学年」）；
/// 桌面端仍是「学年选择器 + 学段下拉」两个控件。
class ScheduleTitleBar extends StatelessWidget {
  const ScheduleTitleBar({
    super.key,
    required this.selectedYear,
    required this.selectedSemester,
    required this.week,
    required this.currentWeek,
    required this.isCurrentTerm,
    required this.compact,
    required this.pickerStartYear,
    required this.pickerEndYear,
    required this.onYearChanged,
    required this.onSemesterChanged,
    required this.onTermPicked,
    required this.onGoToWeek,
    required this.actionCount,
    this.onReturnToCurrentWeek,
    this.hasLeading = true,
    this.lastWeek = 20,
    this.mondayOf,
  });

  final int selectedYear;
  final String selectedSemester;
  final int? week;
  final int? currentWeek;
  final bool isCurrentTerm;
  final bool compact;

  /// 手机端学期选择器的学年范围（入学年份 ~ 当前学年，见 `schoolTermPickerRange`）。
  final int pickerStartYear;
  final int pickerEndYear;

  final ValueChanged<int> onYearChanged;
  final ValueChanged<String> onSemesterChanged;

  /// 手机端选中某个学期码后的回调（学年 + 学段一起改）。
  final ValueChanged<({int xn, int xq})> onTermPicked;
  final ValueChanged<int> onGoToWeek;

  /// 长按周数回本周（用户 2026-09-17 要求这次跳转横划过去）；缺省退回
  /// [onGoToWeek]。口径见 [ScheduleWeekSwitcher.onReturnToCurrentWeek]。
  final ValueChanged<int>? onReturnToCurrentWeek;

  /// 标题栏右侧有几个 action 按钮（调课管理 / 视图切换 / 桌面端刷新）。
  ///
  /// 用户 2026-09-16：「感觉不知道哪个组件的边距特别大，导致标题栏总是换行，
  /// 但是标题栏其实是可以装下那么多内容的」——根因就是这里从前**写死 2 个按钮**
  /// （`chromeWidth = 152`），而手机端实际只有 1 个（刷新按钮已取消）、桌面端有
  /// 3 个：手机端白扣 48px → 明明放得下却换行。
  final int actionCount;

  /// 是否占用 AppBar 左侧返回键的 56（整页模式 true；内嵌面板行内 false）。
  final bool hasLeading;

  /// 本学期最后教学周（周数选择器范围）；缺省 20 只作兜底，页面应传真实值。
  final int lastWeek;

  /// 第 N 周的周一，用于周数选择器里的日期范围提示。
  final DateTime? Function(int week)? mondayOf;

  /// 每个 action 按钮占的宽度。
  ///
  /// 用户 2026-09-16：「标题栏右侧按钮过大」→ 按钮改用紧凑 IconButton
  /// （`iconSize` 18/20 + `visualDensity: compact` + `padding: zero`），实测宽
  /// **40**（M3 默认 IconButton 是 48）。改 [scheduleBarAction] 的尺寸必须同步
  /// 这个常量，否则 `fitsOneRow` 的判定与实际不符
  /// （守卫：`test/schedule_title_bar_test.dart` 的「action 按钮量宽契约」）。
  static const double actionWidth = 40.0;

  /// 标题栏之外被 chrome 占掉的宽度：左侧返回键 56（[hasLeading] 时）
  /// + 每个 action 按钮 [actionWidth]。
  static double chromeWidthFor({
    required int actionCount,
    bool hasLeading = true,
  }) => (hasLeading ? 56.0 : 0.0) + actionWidth * actionCount;

  /// 兼容旧调用点的默认值（= 返回键 + 2 个按钮）。
  static const double chromeWidth = 56.0 + actionWidth * 2;

  /// 可选的学年范围。
  static const int firstYear = 2018;
  static const int lastYear = 2030;

  int get _xq => int.tryParse(selectedSemester) ?? 0;

  Future<void> _pickTerm(BuildContext context) async {
    final picked = await showSchoolTermPicker(
      context,
      startYear: pickerStartYear,
      endYear: pickerEndYear,
      selectedXn: selectedYear,
      selectedXq: _xq,
      compact: compact,
    );
    if (picked != null) onTermPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final oneRow = fitsOneRow(
      context,
      compact: compact,
      isCurrentTerm: isCurrentTerm,
      currentWeek: currentWeek,
      week: week,
      actionCount: actionCount,
      hasLeading: hasLeading,
    );
    // 桌面：学年选择器 + 学段下拉；手机：合并成一个学期码按钮。
    final termSelector = compact
        ? SchoolTermCodeButton(
            code: schoolTermCode(selectedYear, _xq),
            compact: compact,
            onPressed: () => _pickTerm(context),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AcademicYearPicker(
                compact: compact,
                startYear: firstYear,
                endYear: lastYear,
                initialYear: selectedYear,
                onChanged: onYearChanged,
              ),
              SizedBox(width: compact ? 4 : 8),
              ScheduleSemesterSelector(
                selectedSemester: selectedSemester,
                compact: compact,
                onChanged: onSemesterChanged,
              ),
            ],
          );
    final weekSwitcher = ScheduleWeekSwitcher(
      week: week,
      currentWeek: currentWeek,
      isCurrentTerm: isCurrentTerm,
      compact: compact,
      lastWeek: lastWeek,
      mondayOf: mondayOf,
      onGoToWeek: onGoToWeek,
      onReturnToCurrentWeek: onReturnToCurrentWeek,
      // 标题栏里**不放**视图切换按钮（它在 actions 里，与调课按钮并排）。
    );
    final gap = compact ? 6.0 : 10.0;

    final content = oneRow
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              termSelector,
              // 整学期视图下周次控件整个不渲染（用户 2026-09-16：「整学期视图下，
              // 不要显示『整学期』字样」），间距也不要白留。
              if (week != null) ...[SizedBox(width: gap), weekSwitcher],
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              termSelector,
              // 同上：整学期视图没有周次控件，第二行只留学期选择器。
              if (week != null) ...[
                SizedBox(height: compact ? 1 : 2),
                weekSwitcher,
              ],
            ],
          );
    // 内容包 Key：居中后组件自身的 RenderBox 会撑满标题槽，量宽必须量这里
    // （`test/schedule_title_bar_test.dart` 的不变式用例按此断言）。
    final keyed = KeyedSubtree(key: scheduleTitleContentKey, child: content);
    // **整组居中**（桌面端用户 2026-09-15：「电脑端标题栏中的学年学期选择器居中」
    // → 拍板「整组居中」；手机端同日追加：「移动端的学期切换和周数切换也在标题栏
    // 居中」）。块内相对位置不变，量宽一律量 `scheduleTitleContentKey`。
    return Center(child: keyed);
  }

  /// 排成一行所需的宽度（图标按固定尺寸、文字用 [TextPainter] 实测）。
  ///
  /// 学段/周次文案取「最宽的那种」来量（「二学期」/「第 20 周」），
  /// 这样切换学段、切到两位数周次时不会突然换行。
  ///
  /// ⚠ 两处极易写错，改动前先读 `test/schedule_title_bar_test.dart` 的不变式用例
  /// （用户 2026-09-15：「还有很大的空隙，但继续减小宽度就换行」）：
  /// ① **量宽用的基础样式必须与真实渲染一致**——标题栏里的文字都渲染在
  ///    `AppBar.title` 下，继承的是 **AppBar 标题样式**
  ///    （`appBarTheme.titleTextStyle` → `textTheme.titleLarge`，字体族 =
  ///    主题 `fontFamily`、`letterSpacing` 为 0），**既不是裸 `TextStyle`**
  ///    （无字体族 → 引擎默认字体，实测量成 45.0 而真实 23.25），
  ///    **也不是 `DefaultTextStyle.of(context)`** —— 本函数的调用点
  ///    （`ScheduleScreen.build`）在 `Scaffold` **之外**，那里拿到的是
  ///    fallback 样式（无字体族，同样虚高 30+）。虚高的后果就是「看着还很宽
  ///    却换行」；
  /// ② 非 compact 分支的「学年 + 学段」内部间距是 8（与 build 里的
  ///    `SizedBox(width: compact ? 4 : 8)` 一致），**不能再用 `gap`**——
  ///    否则外层的 `head + gap + switcher` 会把间距算两遍；
  /// ③ **`week` 是必填的**：`本周` 按钮在 `week == currentWeek` 时**不渲染**
  ///    （进入课表页的默认状态正是如此，2026-09-15 加入必填以杜绝漏传），
  ///    恒按「有本周按钮」预留会白占 ~35px，等于开着大空隙就换行。
  ///    组件自身 build 与 `ScheduleScreen.build` **两处判定必须传同一个 `week`**，
  ///    否则两处结论不一致（一处排一行、另一处按两行算高度）。
  static double rowNeed(
    BuildContext context, {
    required bool compact,
    required bool isCurrentTerm,
    required int? currentWeek,
    required int? week,
  }) {
    final theme = Theme.of(context);
    final titleStyle =
        theme.appBarTheme.titleTextStyle ??
        theme.textTheme.titleLarge ??
        DefaultTextStyle.of(context).style;
    final textScaler = MediaQuery.textScalerOf(context);
    double textWidth(String text, double fontSize) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: titleStyle.merge(
            TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      return painter.width;
    }

    double widest(Iterable<double> values) =>
        values.reduce((a, b) => a > b ? a : b);

    final gap = compact ? 6.0 : 10.0;

    // 头部：手机端 = 学期码按钮（`261 学期` + 左右内边距，**已无边框与下拉
    // 箭头**，见 SchoolTermCodeButton 的 2026-09-15 裁定）——文案必须走
    // `SchoolTermCodeButton.labelOf`，否则「学期」二字会被漏算；
    // 桌面端 = 学年选择器（高亮宽度 + 4，见 AcademicYearPicker 的
    // `_highlightW + 4`）+ 8 间距 + 学段下拉（取最宽学段文案量宽）。
    final double head;
    if (compact) {
      head =
          textWidth(
            SchoolTermCodeButton.labelOf('261'),
            SchoolTermCodeButton.fontSizeOf(true),
          ) +
          SchoolTermCodeButton.padding * 2;
    } else {
      final semester =
          widest([
            for (final v in const [0, 1, 2]) textWidth(xqDisplayName(v), 13.0),
          ]) +
          19; // 下拉箭头 + 内边距（2026-09-15 实测：整只下拉比文字宽 19，勿凭感觉写 32）
      head = 126.0 + 8 + semester;
    }

    // 图标按钮实测宽度：`IconButton(visualDensity: compact, padding: zero)`
    // = 48 的点击区 − 8（visualDensity 每轴 −4），与 `minWidth: 30/34` 无关
    // → compact 与桌面端都是 40.0（2026-09-15 实测，勿按约束值估）。
    final weekFontSize = compact ? 12.0 : 13.0;
    // 周数文字本身即入口（用户 2026-09-16 取消 `‹ ›`）→ 外面套 InkWell 的
    // 左右内边距 6 + 6，必须计进去。
    const weekButtonPadding = 12.0;
    // 周次那一段：**只在周视图存在**（整学期视图不显示「整学期」字样）；文案取
    // 最宽的「第 20 周」。「本周」按钮已删、视图切换按钮已移进 `actions`
    // （2026-09-16 三条裁定）→ 这里只剩这一个按钮。
    final weekPart = week == null
        ? 0.0
        : widest([textWidth('第 20 周', weekFontSize)]) + weekButtonPadding;
    return head + (weekPart == 0 ? 0 : gap) + weekPart;
  }

  /// 标题栏可用宽度是否放得下一行（留 6 的余量，避免恰好卡在边界时溢出）。
  ///
  /// 余量刻意很小：`rowNeed` 已按真实 AppBar 样式与真实控件尺寸校准到
  /// 「最宽文案时与真实渲染宽度相等（实测偏差 −3~0）」，多留余量就等于无故
  /// 提前换行。守卫 = `test/schedule_title_bar_test.dart` 的不变式用例。
  static bool fitsOneRow(
    BuildContext context, {
    required bool compact,
    required bool isCurrentTerm,
    required int? currentWeek,
    required int? week,
    required int actionCount,
    bool hasLeading = true,
  }) {
    final available =
        MediaQuery.sizeOf(context).width -
        chromeWidthFor(actionCount: actionCount, hasLeading: hasLeading);
    final need = rowNeed(
      context,
      compact: compact,
      isCurrentTerm: isCurrentTerm,
      currentWeek: currentWeek,
      week: week,
    );
    return available >= need + 6;
  }

  /// AppBar 高度（单行矮、两行高）——必须跟着行数走，否则两行内容会被压扁。
  static double toolbarHeight({required bool oneRow, required bool compact}) {
    if (oneRow) return compact ? 52 : 56;
    return compact ? 84 : 78;
  }
}

/// 标题栏 / 筛选栏里的小尺寸图标按钮（紧凑款）。
///
/// 用户 2026-09-16：「标题栏右侧按钮过大」→ 课表页 AppBar 的 action 一律走这里
/// （图标 18/20 而非 M3 默认 24，点击区实测 40 而非 48）。
/// **尺寸契约 = [ScheduleTitleBar.actionWidth]**，改这里必须同步那个常量。
Widget scheduleBarAction({
  required IconData icon,
  required String tooltip,
  required VoidCallback? onPressed,
  bool compact = true,
}) {
  return IconButton(
    tooltip: tooltip,
    icon: Icon(icon),
    iconSize: compact ? 18 : 20,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: BoxConstraints(
      minWidth: compact ? 30 : 34,
      minHeight: compact ? 30 : 34,
    ),
    onPressed: onPressed,
  );
}
