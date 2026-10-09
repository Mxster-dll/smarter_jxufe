import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import 'package:smarter_jxufe/features/ims/schedule/presentation/week_pager.dart';

/// 竖版课表的「周分页板」：**表头原地不动、节数列拖动时淡出**，
/// 只有主体（7 天课格）参与左右翻页动画（用户 2026-09-16 要求）：
///
/// > 课表我希望横划时，顶部的"周一"、...不动，然后左侧节数列淡化隐藏，
/// > 只有主体部分参与滑动动画，然后松手后，节数列出现
///
/// 为什么单独一个组件：`PageView` 只能包住「一页 = 一周的主体」，
/// 而顶部表头与左侧节数列必须留在分页器**外面**；而「拖动中」这个状态只有
/// 监听 `PageView` 冒泡上来的滚动通知才知道 —— 于是把三者拼在一个
/// `StatefulWidget` 里：结构 = `Column[header, Row[leading(淡出), WeekPager]]`。
///
/// 节数列用 `AnimatedOpacity` 淡出，**不改变布局宽度**（`Opacity` 会保留占位）
/// → 主体不会因为节数列消失而横向跳动。
///
/// 抽成独立组件同样是为了**可测**：守卫 `test/schedule_paged_board_test.dart`
/// 用假页面断言「拖动时表头不动 / 节数列淡出 / 松手后恢复 / 主体随手指位移」，
/// 不必伪造学籍 + 课表 + 调课三套 provider。
class SchedulePagedBoard extends StatefulWidget {
  const SchedulePagedBoard({
    super.key,
    required this.weekCount,
    required this.week,
    required this.onWeekChanged,
    required this.header,
    required this.leading,
    required this.leadingWidth,
    required this.bodyHeight,
    required this.pageBuilder,
    this.contentWidth,
    this.enabled = true,
    this.smoothRequest = 0,
    this.onSettled,
    this.fadeDuration = const Duration(milliseconds: 180),
  });

  /// 总周数（≥ 1），一页一周。
  final int weekCount;

  /// 当前教学周（1 起）。
  final int week;

  /// 翻到某一周（由手势触发；外部改周请改 [week]）。
  final ValueChanged<int> onWeekChanged;

  /// 顶部表头（含左上角格 + 7 个「周一…周日」列头）：**滑动时保持不动**。
  final Widget header;

  /// 左侧节数列（12 个节次格）：拖动时淡出，松手后恢复。
  ///
  /// **浮在主体之上**（`Stack` 的最后一层）：淡出后露出的是**正在滑动的课表**
  /// —— 用户 2026-09-16：「节数列隐藏后，原节数列位置可以显示被滑动的课表」。
  final Widget leading;

  /// 节数列宽度（= 每页主体左侧空出的宽度，保证与静态表头的列对齐）。
  final double leadingWidth;

  /// 表格内容宽度（含节数列那一栏）——**只影响内容在整块里的居中偏移**。
  ///
  /// ⚠ 为什么必须与「整块宽度」分开（用户 2026-10-08 四轮：「起点或终点为本周的
  /// bug 又回来了」）：非 compact 时列宽被夹在 `[80, 160]` → **列数一变整表总宽就变**
  /// （6 列 996 / 5 列 836）。若分页器直接裹在这块宽度里（旧写法 = 外层
  /// `SizedBox(width: totalWidth)`），列集合一换（= 唯一会换的情形：起止点是本周）
  /// 就会**在补间飞行途中改掉分页器的视口宽度** → 正在飞的补间像素目标失效 →
  /// 落点错周（实测：视口 900→700 会让「第 5 → 第 12 周」落在第 15 周）。
  /// 现在分页视口恒等于**整块宽度**（外层给多少就是多少，与列集合无关），
  /// 表格内容按 [contentWidth] 在整块里居中 —— 悬浮节数列也跟着这个偏移走。
  ///
  /// `null` = 内容与整块等宽（偏移 0）：紧凑布局（手机）与既有用例走这条，
  /// 与旧行为逐像素一致。
  final double? contentWidth;

  /// 主体高度（= 12 × 行高）；`PageView` 必须拿到有界高度。
  final double bodyHeight;

  /// 某一周的主体：`(context, week)` → 该周的 7 天课格（**不含表头**）。
  final Widget Function(BuildContext context, int week) pageBuilder;

  /// 是否允许手势翻页（桌面端 false）。
  final bool enabled;

  /// 「平滑跳转」请求序号（长按回本周这类**有意的跨周跳转**要看得见翻页过程）：
  /// 原样透传给 [WeekPager.smoothRequest]，口径与理由都在那里。
  final int smoothRequest;

  /// 翻页**停稳**时回调：原样透传给 [WeekPager.onSettled]（课表页用它冻结
  /// 「可见天 / 列集合」，见那里的注释）。
  final VoidCallback? onSettled;

  /// 节数列淡出 / 恢复的时长。
  final Duration fadeDuration;

  /// 拖动时节数列的不透明度（0 = 完全隐藏，用户口径「淡化隐藏」）。
  static const double leadingHiddenOpacity = 0;

  @override
  State<SchedulePagedBoard> createState() => _SchedulePagedBoardState();
}

class _SchedulePagedBoardState extends State<SchedulePagedBoard> {
  /// 正在被手指拖动（或拖动松手后的惯性滚动）→ 节数列淡出。
  bool _swiping = false;

  void _setSwiping(bool value) {
    if (_swiping == value || !mounted) return;
    setState(() => _swiping = value);
  }

  /// 只有**手指拖动**才淡出：`dragDetails != null` 区分手势与程序化滚动
  /// （选周 / 回本周走 `animateToPage` 补间，那时节数列保持可见，
  /// 避免程序化切周时节数列闪一下）。
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) _setSwiping(true);
    } else if (notification is ScrollEndNotification) {
      _setSwiping(false);
    } else if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      _setSwiping(false);
    }
    return false;
  }

  /// 每页：左侧空出**居中偏移 + 节数列宽度**（与静态表头的列对齐），
  /// 右侧放该周的 7 天课格（宽 = 表格内容宽 - 节数列）。
  ///
  /// 页面**占满整块宽度**（含节数列那一栏）是刻意的：分页视口 = 整块宽度，
  /// 于是拖动时「节数列那一栏」下面就是滑动中的课表 —— 节数列淡出即露出。
  /// 表格比整块窄时（非 compact 桌面）内容居中：偏移由 [offset] 给，
  /// 各页一致 → 滑动时整表仍是一起走。
  Widget _buildPage(
    BuildContext context,
    int week,
    double offset,
    double tableWidth,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: offset),
      SizedBox(width: widget.leadingWidth),
      SizedBox(
        width: (tableWidth - widget.leadingWidth).clamp(0.0, double.infinity),
        child: widget.pageBuilder(context, week),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 整块宽度 = 分页视口宽度（**与列集合无关**，见 [contentWidth]）。
        final boardWidth = constraints.maxWidth;
        final tableWidth = widget.contentWidth ?? boardWidth;
        final offset = ((boardWidth - tableWidth) / 2).clamp(
          0.0,
          double.infinity,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 表头：静态，不参与滑动；表格比整块窄时与各页内容的偏移一致。
            Padding(
              padding: EdgeInsets.only(left: offset),
              child: widget.header,
            ),
            SizedBox(
              height: widget.bodyHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: WeekPager(
                        weekCount: widget.weekCount,
                        week: widget.week,
                        enabled: widget.enabled,
                        smoothRequest: widget.smoothRequest,
                        onSettled: widget.onSettled,
                        onWeekChanged: widget.onWeekChanged,
                        pageBuilder: (context, week) =>
                            _buildPage(context, week, offset, tableWidth),
                      ),
                    ),
                  ),
                  // 节数列浮层：拖动时淡出 → 露出下方滑动中的课表。
                  // `IgnorePointer` 必须留着：它盖在主体之上，否则会吞掉拖动与点击。
                  Positioned(
                    left: offset,
                    top: 0,
                    bottom: 0,
                    width: widget.leadingWidth,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        key: const Key('scheduleLeadingColumn'),
                        opacity: _swiping
                            ? SchedulePagedBoard.leadingHiddenOpacity
                            : 1,
                        duration: widget.fadeDuration,
                        curve: Curves.easeOut,
                        child: widget.leading,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
