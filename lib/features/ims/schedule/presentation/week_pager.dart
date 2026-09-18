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
    this.smoothRequest = 0,
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

  /// 「平滑跳转」请求序号：外部**希望这次改周横划过去**（哪怕跨十几周）时 +1。
  ///
  /// 用户 2026-09-17：「长按周数返回本周要显示横划动画」。从前跨多周一律
  /// `jumpToPage`（瞬间到位），只有 ±1 周才补间 —— 而长按回本周常常跨十几周，
  /// 于是屏幕上是一次「瞬移」，看不出翻页方向。
  ///
  /// 为什么不做成「跨多周一律补间」：**返回本周是一次有意的跳转，弹窗选周 /
  /// 切学期是「定位到某一周」**，后者刷过去会让一整屏不相干的周次（切学期时
  /// 甚至是另一个学期的内容）在眼前掠过。故只给显式请求这条路开补间。
  final int smoothRequest;

  /// 单页切换（相邻周之间）的补间时长。
  static const Duration pageTransition = Duration(milliseconds: 280);

  /// 平滑跳转时**每多跨一页**追加的时长。
  static const Duration smoothPerPage = Duration(milliseconds: 45);

  /// 平滑跳转的时长上限（再远也不拖更久）。
  static const Duration smoothMaxTransition = Duration(milliseconds: 700);

  /// 外部改周时超过这么多页就直接跳（不逐页刷过去）。
  static const int jumpThreshold = 1;

  /// 跨 [pages] 页的平滑跳转时长：一页 [pageTransition]，每多一页 +[smoothPerPage]，
  /// 上限 [smoothMaxTransition]。
  ///
  /// 为什么不固定成 [pageTransition]：19 周一次跳完若仍给 280ms，平均每页只占
  /// ~15ms（不到一帧），既看不清方向，又要在每帧里现建/丢弃两页课表。
  /// 按跨度给时长能把「每页停留」稳在 2 帧以上（700ms / 19 页 ≈ 37ms/页）。
  static Duration smoothTransitionFor(int pages) {
    final n = pages < 1 ? 1 : pages;
    final ms =
        pageTransition.inMilliseconds + (n - 1) * smoothPerPage.inMilliseconds;
    return Duration(
      milliseconds: ms.clamp(
        pageTransition.inMilliseconds,
        smoothMaxTransition.inMilliseconds,
      ),
    );
  }

  @override
  State<WeekPager> createState() => _WeekPagerState();
}

class _WeekPagerState extends State<WeekPager> {
  late final PageController _controller;

  /// 最近一次**由本分页器自己**上报出去的周（`onPageChanged` → 外部 → 回灌）。
  ///
  /// 跨多周补间途中 `onPageChanged` 会**逐页**上报（PageView 在滚动通知里按
  /// `page.round()` 报），外部随即把 `week` 同步回来。若不区分「这是自己的回声」，
  /// [didUpdateWidget] 会把它当成一次新的外部改周：此刻 `_controller.page` 还是
  /// 小数（如 7.4），`round()` 恰好等于刚越过的那一页 → 又 `animateToPage` 回去，
  /// 长跳转会被反复拽回、来回抖。
  int? _selfReported;

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
    // 自己刚上报的周（手势翻页 / 补间途中的逐页上报）不是外部改周。
    if (widget.week == _selfReported) return;
    _followWeek(smooth: widget.smoothRequest != oldWidget.smoothRequest);
  }

  /// 外部改了周（长按回本周、弹窗选周、学期切换、周次夹取）→ 让分页器跟上：
  /// [smooth] = true（用户明确要求横划的跳转，见 [WeekPager.smoothRequest]）
  /// 时**跨多少周都补间**；否则相邻一周走补间、跨多周直接跳（不逐页刷屏）；
  /// 若第 1 帧还没 attach，`initialPage` 已经落好了，无需处理。
  void _followWeek({required bool smooth}) {
    if (!_controller.hasClients) return;
    final target = _safeWeek - 1;
    final current = _controller.page;
    if (current == null || (current - target).abs() < 0.01) return;
    if (smooth) {
      _controller.animateToPage(
        target,
        duration: WeekPager.smoothTransitionFor((current - target).abs().ceil()),
        curve: Curves.easeOutCubic,
      );
      return;
    }
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
      onPageChanged: (index) {
        _selfReported = index + 1;
        widget.onWeekChanged(index + 1);
      },
      itemBuilder: (context, index) => widget.pageBuilder(context, index + 1),
    );
  }
}
