/// 首页仪表盘「今日课程卡」零件（2026-09-20 从 `dashboard_panel.dart` 外提 · 架构审查 ⑥）。
///
/// 原 `DashboardPanel._buildTodayCourses` 簇（按节次合并的课程块 + 大间隔分隔线）。
/// **自身 `ref.watch` 取数**；节次尺寸 / 分隔带常量仍留在 `DashboardPanel` 上（守卫按源码断言），
/// 故本文件 import 它。
library;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/errors/app_exception.dart';

import 'package:smarter_jxufe/design/app_card.dart';

import 'package:smarter_jxufe/design/app_theme.dart';

import 'package:smarter_jxufe/features/home/data/providers/dashboard_providers.dart';

import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';

import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';

import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';

import 'package:smarter_jxufe/features/home/presentation/dashboard_common.dart';
import 'package:smarter_jxufe/features/home/presentation/dashboard_panel.dart';

Widget dashboardTodayCourses(BuildContext context, WidgetRef ref) {
  final scheme = Theme.of(context).colorScheme;
  final now = DateTime.now();
  // ⚠ 名字沿用原 `_buildTodayCourses` 的形参名（`async` / `periods`）—— 这样块内一行都不用改。
  final AsyncValue<List<TodayCourse>> async = ref.watch(dashboardTodayCoursesProvider);
  final PeriodTable? periods =
      ref.watch(currentPeriodTableProvider).valueOrNull ??
      ref.watch(cachedPeriodTableProvider).valueOrNull;

    return Material(
      key: const Key('dashTodayCard'),
      color: Theme.of(context).cardTheme.color,
      shape: appCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            dashboardPush(context, ImsSplashScreen(initialTab: ImsTab.schedule)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 手机端也是左右 2 : 1（用户 2026-09-18 四轮裁定）→ 右栏在 360dp
            // 手机上只有约 100dp：卡片内边距、头部图标盒、字号都要收一档，
            // 否则「图标盒 40 + 间距 12 + 刷新按钮 40」本身就超过可用宽度。
            final narrow =
                constraints.maxWidth < DashboardPanel.todayCourseCardNarrowBreakpoint;
            // 高度是否被外层限定（移动端等高 = `SizedBox`、桌面端最小高度 =
            // `ConstrainedBox` 都会给有限高度；面板放进滚动列表时则不受限）。
            final bounded = constraints.hasBoundedHeight;
            final slots = _todayCourseSlots(
              context,
              scheme,
              async,
              periods,
              narrow: narrow,
            );
            return Padding(
              padding: narrow
                  ? const EdgeInsets.fromLTRB(10, 10, 6, 10)
                  : const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 窄档（手机 2:1 分栏，卡宽约 100dp）**不显示图标**：用户
                      // 2026-09-19 先要求「移动端不隐藏icon」，试过之后当场改口
                      // 「还是去除图标吧」→ 恢复为仅宽档显示（40×40）。
                      if (!narrow) ...[
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: appCardAccentSoft(context),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.today_outlined,
                            size: 20,
                            color: appCardAccent(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '今日课程',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: narrow ? 13 : 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              todayLabel(now),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: narrow ? 10.5 : 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 刷新按钮已撤（用户 2026-09-19：「去除主页课表卡片的
                      // 刷新按钮」）—— 刷新改由首页下拉完成（`refreshDashboard`）。
                    ],
                  ),
                  SizedBox(height: narrow ? 8 : 10),
                  // 高度受限时把剩余空间给时间轴、不够就滚动（卡片高度可能被压到
                  // 比时间轴还矮 —— 移动端要与指标卡区等高）；**高度不受限时一律
                  // 不挂 flex** —— 无限高约束 + 非零 flex 子项会直接抛
                  // 「RenderFlex children have non-zero flex but incoming height
                  // constraints are unbounded.」（实测踩到，别再改回 Flexible）。
                  if (bounded)
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: slots,
                        ),
                      ),
                    )
                  else
                    ...slots,
                ],
              ),
            );
          },
        ),
      ),
    );
}

  List<Widget> _todayCourseSlots(
    BuildContext context,
    ColorScheme scheme,
    AsyncValue<List<TodayCourse>> async,
    PeriodTable? periods, {
    bool narrow = false,
  }) {
    return async.when(
      loading: () => const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ],
      error: (e, _) => [
        dashboardInlineStatus(
          scheme,
          Icons.error_outline,
          '课表获取失败：${friendlyErrorText(e)}',
        ),
      ],
      data: (courses) {
        if (courses.isEmpty) {
          return [
            dashboardInlineStatus(
              scheme,
              Icons.event_available_outlined,
              '今天没有课，好好休息吧',
            ),
          ];
        }
        final blocks = <Widget>[];
        // 上一门课占到的最后一节（算空档用；课程按开始节次升序）。
        var previousEnd = 0;
        TodayCourse? previous;
        // 大间隔把该处空档撑到分隔带高时，后续课块整体下移的累计量。
        var shifted = 0.0;
        for (final course in courses) {
          final start = course.startPeriod.clamp(1, schedulePeriodCount).toInt();
          final end = course.endPeriod.clamp(start, schedulePeriodCount).toInt();
          if (previous != null && _isLongBreak(periods, previous, course)) {
            // 大间隔：上一门块的下沿 → 本门块的上沿之间是空档。
            final rawGapTop =
                (previousEnd - 1) * DashboardPanel.todayCourseTrackHeight +
                DashboardPanel.todayCourseSlotHeight;
            final rawGapBottom = (start - 1) * DashboardPanel.todayCourseTrackHeight;
            final rawGap = rawGapBottom - rawGapTop;
            // ⚠ 空档不足一条分隔带就**撑开**（2026-09-18 七轮）：典型是**午休** ——
            // 第 5 节 12:20 下课、第 6 节 14:00 上课（钟点差 100 分钟），但两块课在
            // 时间轴上只差一个轨道减一个节高 = 4dp；六轮时把分隔带收缩进 4dp，结果线
            // 上下各 1dp、与宽空档那条（线下 8dp）观感不一致。现在一律撑到
            // DashboardPanel.dashboardBreakBandHeight：线下 8dp、线上 4dp 留白，**每条分隔线完全一样**。
            final extra = rawGap >= DashboardPanel.dashboardBreakBandHeight
                ? 0.0
                : DashboardPanel.dashboardBreakBandHeight - rawGap;
            shifted += extra;
            blocks.add(
              Positioned(
                top: rawGapBottom + shifted - DashboardPanel.dashboardBreakBandHeight,
                left: 0,
                right: 0,
                height: DashboardPanel.dashboardBreakBandHeight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: DashboardPanel.dashboardBreakLineGap),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      key: Key('dashTodayBreak-${course.startPeriod}'),
                      height: DashboardPanel.dashboardBreakLineHeight,
                      color: AppColors.hairline(context, 0.9),
                    ),
                  ),
                ),
              ),
            );
          }
          blocks.add(
            Positioned(
              top: (start - 1) * DashboardPanel.todayCourseTrackHeight + shifted,
              left: 0,
              right: 0,
              height:
                  (end - start + 1) * DashboardPanel.todayCourseTrackHeight -
                  DashboardPanel.todayCourseSlotGap,
              child: _todayCourseCell(
                context,
                scheme,
                course,
                span: end - start + 1,
                narrow: narrow,
              ),
            ),
          );
          if (end > previousEnd) previousEnd = end;
          previous = course;
        }
        // 全天都占位（末尾没课的节次也留高度）→ 最后一门课之后始终有余量。
        return [
          SizedBox(
            key: const Key('dashTodayTimeline'),
            height:
                schedulePeriodCount * DashboardPanel.todayCourseTrackHeight -
                DashboardPanel.todayCourseSlotGap +
                shifted,
            child: Stack(children: blocks),
          ),
        ];
      },
    );
}

  Widget _todayCourseCell(
    BuildContext context,
    ColorScheme scheme,
    TodayCourse course, {
    required int span,
    bool narrow = false,
  }) {
    final tint = appCardAccentSoft(context);
    final roomy = span >= 2;
    final nameSize = narrow ? (roomy ? 11.0 : 10.0) : (roomy ? 12.5 : 11.0);
    final roomSize = narrow ? (roomy ? 9.5 : 9.0) : (roomy ? 11.0 : 9.5);
    return Container(
      key: Key('dashTodayCourse-${course.startPeriod}'),
      padding: EdgeInsets.symmetric(horizontal: narrow ? 5 : 8, vertical: 2),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tint),
      ),
      child: ClipRect(
        // 名称 / 教室**放不下就换行**（用户 2026-09-18 六轮：「内容宽度不够不要
        // 显示省略号，而是换行」）：合并块（span ≥ 2，内高 60dp 起）给两行，
        // 单节块（内高 26dp）只放得下一行 —— 2 行名称 28.75 + 2 行教室 25.3 =
        // 54.05 ≤ 60 放得下。`ellipsis` 仅作极端兜底（超长名 / 系统大字号），
        // `ClipRect` 保证兜不住时也不会溢到相邻课块上。
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              course.courseName,
              maxLines: roomy ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: nameSize,
                height: 1.15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            if (course.classroom.isNotEmpty)
              Text(
                course.classroom,
                maxLines: roomy ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: roomSize,
                  height: 1.15,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
}

  bool _isLongBreak(
    PeriodTable? periods,
    TodayCourse previous,
    TodayCourse next,
  ) {
    if (periods == null) return false;
    final end = periods.periodOf(previous.endPeriod);
    final start = periods.periodOf(next.startPeriod);
    if (end == null || start == null) return false;
    return start.startMinutes - end.endMinutes > DashboardPanel.dashboardCourseBreakMinutes;
}
