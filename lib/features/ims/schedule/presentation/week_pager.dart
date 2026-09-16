import 'package:flutter/material.dart';

/// 教学周分页器：一页一周，**左右相邻周始终并排**，拖动跟手、松手按
/// 距离/速度 snap —— 与手机桌面翻页同一种手感（用户 2026-09-15：
/// 「我希望就是很自然像手机桌面翻页一样」）。
///
/// 为什么不用手写 `Transform.translate` + 滑出/滑入：那种做法在旧周滑出时
/// 屏幕上没有相邻页，会露出一片空白，再硬切到新周从另一侧进来 —— 看起来就是
/// 「滑走 → 空 → 冒出来」。`PageView` 自带
/// ①相邻页随手指 1:1 位移（两侧都在屏幕上）、②`PageScrollPhysics` 的速度/距离
/// snap、③首末页的边界回弹，三者正是「翻页感」的全部来源。
///
/// 抽成独立组件是为了**可测**：守卫 `test/week_pager_test.dart` 用假页面
/// （只画一个「第 N 周」文本）断言跟手位移、snap 结果、fling 切页、边界与
/// 「外部改周」的跳转/补间 —— 不必伪造学籍 / 课表 / 调课三套 provider。
class WeekPager extends StatefulWidget {
  const WeekPager({
    super.key,
    required this.weekCount,
    required this.week,
    required this.onWeekChanged,
    required this.pageBuilder,
    this.enabled = true,
  });

  /// 总周数（≥ 1），一页一周。
  final int weekCount;

  /// 当前教学周（1 起；越界会被夹到 `[1, weekCount]`）。
  final int week;

  /// 翻到某一周（**由分页器内部手势触发**；外部改周请改 [week]）。
  final ValueChanged<int> onWeekChanged;

  /// 页面构造：`(context, week)`，week 从 1 起。
  final Widget Function(BuildContext context, int week) pageBuilder;

  /// 是否允许手势翻页（桌面端 false → 只能靠外部改 [week]，仍会补间滚动）。
  final bool enabled;

  /// 单页切换（相邻周之间）的补间时长。
  static const Duration pageTransition = Duration(milliseconds: 280);

  /// 外部改周时超过这么多页就直接跳（不逐页刷过去）。
  static const int jumpThreshold = 1;

  @override
  State<WeekPager> createState() => _WeekPagerState();
}

class _WeekPagerState extends State<WeekPager> {
  late final PageController _controller;

  int get _safeWeek =>
      widget.week.clamp(1, widget.weekCount < 1 ? 1 : widget.weekCount);

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: _safeWeek - 1);
  }

  @override
  void didUpdateWidget(covariant WeekPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.week == oldWidget.week &&
        widget.weekCount == oldWidget.weekCount) {
      return;
    }
    _followWeek();
  }

  /// 外部改了周（上一周/下一周按钮、学期切换、周次夹取）→ 让分页器跟上：
  /// 相邻一周走补间（看起来就是翻了一页），跨多周直接跳（不逐页刷屏）；
  /// 若第 1 帧还没 attach，`initialPage` 已经落好了，无需处理。
  void _followWeek() {
    if (!_controller.hasClients) return;
    final target = _safeWeek - 1;
    final current = _controller.page;
    if (current == null || (current - target).abs() < 0.01) return;
    if ((current.round() - target).abs() <= WeekPager.jumpThreshold) {
      _controller.animateToPage(
        target,
        duration: WeekPager.pageTransition,
        curve: Curves.easeOutCubic,
      );
    } else {
      _controller.jumpToPage(target);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.weekCount < 1 ? 1 : widget.weekCount;
    return PageView.builder(
      controller: _controller,
      itemCount: count,
      physics: widget.enabled
          ? const PageScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      onPageChanged: (index) => widget.onWeekChanged(index + 1),
      itemBuilder: (context, index) => widget.pageBuilder(context, index + 1),
    );
  }
}
