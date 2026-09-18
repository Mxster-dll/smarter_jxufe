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
    this.enabled = true,
    this.smoothRequest = 0,
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

  /// 主体高度（= 12 × 行高）；`PageView` 必须拿到有界高度。
  final double bodyHeight;

  /// 某一周的主体：`(context, week)` → 该周的 7 天课格（**不含表头**）。
  final Widget Function(BuildContext context, int week) pageBuilder;

  /// 是否允许手势翻页（桌面端 false）。
  final bool enabled;

  /// 「平滑跳转」请求序号（长按回本周这类**有意的跨周跳转**要看得见翻页过程）：
  /// 原样透传给 [WeekPager.smoothRequest]，口径与理由都在那里。
  final int smoothRequest;

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
  /// （点「上一周/下一周」按钮走 `animateToPage`，那时节数列保持可见，
  /// 避免按钮切周时节数列闪一下）。
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

  /// 每页：左侧空出节数列宽度（与静态表头的列对齐），右侧放该周的 7 天课格。
  ///
  /// 页面**占满整块宽度**（含节数列那一栏）是刻意的：分页视口 = 整块宽度，
  /// 于是拖动时「节数列那一栏」下面就是滑动中的课表 —— 节数列淡出即露出。
  Widget _buildPage(BuildContext context, int week) => Row(
    children: [
      SizedBox(width: widget.leadingWidth),
      Expanded(child: widget.pageBuilder(context, week)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 表头：静态，不参与滑动。
        widget.header,
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
                    onWeekChanged: widget.onWeekChanged,
                    pageBuilder: _buildPage,
                  ),
                ),
              ),
              // 节数列浮层：拖动时淡出 → 露出下方滑动中的课表。
              // `IgnorePointer` 必须留着：它盖在主体之上，否则会吞掉拖动与点击。
              Positioned(
                left: 0,
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
  }
}
