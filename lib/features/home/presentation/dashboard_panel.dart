
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/home/presentation/dashboard_metrics.dart';
import 'package:smarter_jxufe/features/home/presentation/dashboard_today_courses.dart';
import 'package:smarter_jxufe/features/home/data/providers/dashboard_providers.dart';
import 'package:smarter_jxufe/features/home_widget/data/home_widget_sync.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/weighted_grade_repository_provider.dart';

import 'package:smarter_jxufe/features/net_fee/data/providers/net_fee_providers.dart';
import 'package:smarter_jxufe/features/network_service/data/providers/network_service_providers.dart';

/// 刷新首页仪表盘的全部卡片数据（**唯一实现**）。
///
/// 用户 2026-09-19 裁定：「去除主页课表卡片的刷新按钮」「主页视图下拉刷新所有
/// 卡片」—— 面板内不再有刷新按钮，改为首页 `RefreshIndicator` 调本函数；
/// 顺手把桌面小组件的数字也推一遍（原来点刷新按钮时就是这么做的）。
Future<void> refreshDashboard(WidgetRef ref) async {
  ref.invalidate(dashboardElectricityProvider);
  ref.invalidate(dashboardVolunteerHoursProvider);
  ref.invalidate(weightedGradeRankingProvider(1));
  ref.invalidate(dashboardTodayCoursesProvider);
  ref.invalidate(netFeeSummaryProvider);
  // 校园网卡片右上角要显示「本周期已用流量」。
  ref.invalidate(networkAccountProvider);
  final widgetSync = ref.read(homeWidgetSyncProvider);
  await widgetSync.pushAuthSnapshot();
  await widgetSync.syncAll(force: true);
}

/// 首页仪表盘总览面板：电费 / 校园网 / 成绩（累计加权）/ 志愿时长 + 今日课程。
///
/// **版式（用户 2026-09-18 四轮裁定）**：其他卡片在左、今日课程在右，**恒为
/// `Row` 且宽度约 2 : 1 —— 移动端也一样不堆叠**（三轮前窄屏会上下堆叠，
/// 已被否）；面板**不再有小标题** —— 原来的「数据一览」竖条标题与其刷新按钮
/// 已撤，刷新入口搬到今日课程卡头部。
/// 今日课程 = **按节次合并的课程块**（空节不画格子但按节数占位），每块只写
/// 「名称 + 教室」，相邻两门课若按作息表算出的间隔超过 1 小时，中间插一条
/// **贴着后一门课**的分隔线。
///
/// 各数据块独立加载容错；点按跳对应详情页。视觉与首页功能卡同源。
class DashboardPanel extends ConsumerWidget {
  const DashboardPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 用户 2026-09-18 裁定：去掉「数据一览」小标题；其他卡片在左、今日课程在右，
    // 窄屏上下堆叠。
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = dashboardMetrics(context, ref);
        // 作息表（与课表页同源：实时优先、缓存/内置兜底）——
        // 「间隔超过 1 小时」的分隔线要按它把节次换算成钟点。
        final today = dashboardTodayCourses(context, ref);
        // 恒为左右两栏（用户 2026-09-18 四轮裁定：「即使移动端，也是这种
        // 左右 2 : 1 的显示」）—— 窄屏不再上下堆叠，指标卡自动退成单列。
        // 今日课程卡高度对齐（用户 2026-09-19 裁定）：**移动端与指标卡区总高
        // 度等高、桌面端最小高度与之一致**。指标卡高度是固定常量、行数由
        // [metricsLayout] 算出 → 指标区总高可直接算，无需二次布局测量。
        final metricsWidth =
            (constraints.maxWidth - DashboardPanel.dashboardColumnGap) * 2 / 3;
        final metricsHeight = DashboardPanel.metricsLayout(metricsWidth).height;
        final compact =
            MediaQuery.sizeOf(context).width <
            DashboardPanel.dashboardCompactBreakpoint;
        final sizedToday = compact
            ? SizedBox(height: metricsHeight, child: today)
            : ConstrainedBox(
                constraints: BoxConstraints(minHeight: metricsHeight),
                child: today,
              );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: metrics),
            const SizedBox(width: DashboardPanel.dashboardColumnGap),
            Expanded(child: sizedToday),
          ],
        );
      },
    );
  }

  /// 指标卡区（电费 / 校园网 / 课程加权 / 志愿时长）：按可用宽度自适应列数。

  /// 课程加权卡内容：只有加权分（单行自适应）。
  ///
  /// 排名（班级 / 专业 / 年级）自 2026-09-15 起不再占一行高度 ——
  /// 用户裁定「排名不要占用高度，而是显示在右上角的一个胶囊」，
  /// 胶囊由 [_gradeRankCapsule] 渲染、挂在卡片头部行的尾部。

  /// 排名胶囊：`#班级/专业/年级`（用户 2026-09-15 裁定 a/b/c 三个数字，
  /// 同日二轮改为 `#a/b/c` 紧凑写法：`#` 前缀 + 斜杠分隔、无空格）。
  ///
  /// 取不到的排名（≤ 0）写 `—`；完整含义放 tooltip（桌面悬停 / 手机长按）。

  /// 本学年志愿时长胶囊（右上是功能色，取值同卡片的 `color`）。
  ///
  /// 徽标只放数字（`本学年 24h`），学年名与**上一学年的对照值**放 tooltip ——
  /// 卡片头部只有一行；本学年为 0 时用户最需要知道「那是上一学年的量」。

  /// 校园网卡片右上角胶囊：本计费周期已用流量。
  ///
  /// 数据源 = 网络服务总览 `networkAccountProvider`（`NetworkAccount.useFlow`，MB；
  /// 与「校园网」页顶部同一口径），**不是**网费充值域的余额。

  /// 单行自适应数值行：卡宽不足时整体等比缩小，保证完整显示不换行。

  /// 指标卡内容：loading / error / 空态 / 数值。

  // ---------- 今日课程 ----------

  /// 单节高度与节间空隙：第 n 节的顶端偏移 = `(n - 1) × todayCourseTrackHeight`。
  static const double todayCourseSlotHeight = 30;

  /// 相邻节次之间的空隙。
  static const double todayCourseSlotGap = 4;

  /// 一节的「轨道」高度 = 节高 + 节间空隙。空节**不画格子，但按轨道占位**
  /// —— 用户 2026-09-18 三轮裁定：「无课格子不显示不等于不占位」。
  static const double todayCourseTrackHeight =
      todayCourseSlotHeight + todayCourseSlotGap;

  /// 两门课之间的「大间隔」阈值（分钟）——**按作息表的钟点算**，超过就画分隔线。
  static const int dashboardCourseBreakMinutes = 60;

  /// 大间隔分隔带的高度：分隔线画在这条带子的下沿，**带底与下一门课的块之间还留
  /// [dashboardBreakLineGap]** —— 用户 2026-09-18 四轮裁定「增大分割线的占位高度」
  /// 「最后一节课应该是贴着分割线的」，五轮又裁定「分割线距离卡片太近」。
  /// 14 = 线上方留白 4 + 线 2 + 线下到课块 8。
  static const double dashboardBreakBandHeight = 14;

  /// 分隔线**底边**到下方课块顶边的距离（别贴死，也别退回「空档正中」）。
  static const double dashboardBreakLineGap = 8;

  /// 分隔线粗细。
  static const double dashboardBreakLineHeight = 2;

  /// 左栏（指标卡）与右栏（今日课程）之间的栏间距。
  ///
  /// 用户 2026-09-18 六轮：「缩小左右卡片间距」→ 16 → 10。
  static const double dashboardColumnGap = 10;

  /// 「今日课程」卡片窄档断点：低于它（手机端 2 : 1 的右栏）收一档内边距与字号。
  static const double todayCourseCardNarrowBreakpoint = 210;

  /// 单张指标卡的统一高度。
  ///
  /// 四张卡内容行数不同（成绩卡多一行排名）会让卡片高矮不一、Wrap 参差；更要紧的是
  /// 用户 2026-09-19 裁定「课程卡片在移动端要与其余卡片总高度等高，桌面端最小高度
  /// 要与其余卡片一致」需要一个**可计算**的指标区高度（`IntrinsicHeight` 在这里
  /// 用不了：两侧都含 `LayoutBuilder`，它不支持 intrinsic 尺寸）。
  static const double dashboardMetricCardHeight = 132;

  /// 指标卡张数（电费 / 校园网 / 课程加权 / 志愿时长）。
  static const int dashboardMetricCount = 4;

  /// 指标卡之间的横竖间距（与 [metricsLayout] 同一套公式）。
  static const double dashboardMetricGap = 12;

  /// 手机档断点：低于它按「与指标卡区等高」，高于它按「最小高度 = 指标卡区」。
  static const double dashboardCompactBreakpoint = 620;

  /// 指标卡区的列数 / 行数 / 总高度（**唯一公式**，`build` 与 `_buildMetrics` 共用）。
  static ({int cols, int rows, double height}) metricsLayout(double maxWidth) {
    const minCard = 210.0;
    // 窄屏（手机端 2:1 后左栏只有 ~200dp）算出来会是 0 列 →
    // `gap * (cols - 1)` 变负数、`/ cols` 变 NaN，必须兜到 1 列。
    var cols = (maxWidth + dashboardMetricGap) ~/ (minCard + dashboardMetricGap);
    if (cols < 1) cols = 1;
    final rows = (dashboardMetricCount + cols - 1) ~/ cols;
    return (
      cols: cols,
      rows: rows,
      height:
          rows * dashboardMetricCardHeight + (rows - 1) * dashboardMetricGap,
    );
  }

  /// 今日课程 = **绝对定位的时间轴**：每门课一块（按节次合并，块高 ∝ 节数），
  /// 位置 = `(起始节 - 1) × todayCourseTrackHeight` + 前面大间隔撑开的位移，所以无课
  /// 节次虽然不画格子，却仍然占着对应的高度（第 7 节的课永远在第 3 节的课下方 4 个
  /// 轨道处）。
  ///
  /// 相邻两门课之间若按作息表算出的间隔超过 [dashboardCourseBreakMinutes]，就画一条
  /// 细线，并且**该处空档至少撑到 [dashboardBreakBandHeight]**（不足则由后面的课块整体
  /// 下移补足）—— 于是每条分隔线的几何完全一致：线下 [dashboardBreakLineGap]、线上 4dp
  /// 留白，不再出现「第一条被挤在两块之间、第二条悬在半空」的观感（用户 2026-09-18 七轮：
  /// 「第一条分界线距离上下卡片距离和第二条不一样」）。
  ///
  /// **全天 [schedulePeriodCount] 节都占位**（末尾没课的节次也留高度）→ 最后一门课之后
  /// 始终有余量（用户 2026-09-18 七轮：「今天没有第三节晚课，但是组件里第二节晚课后没有
  /// 空间了」）。
  ///
  /// 用户 2026-09-18 三轮裁定：「① 无课格子不显示不等于不占位 ③ 教室显示在课程
  /// 名称下面」；二轮裁定：「格子可以合并 / 无课格子不显示 / 间隔超过 1h 画分隔线」。

  /// 一门课一块：**名称在上、教室在下**（用户 2026-09-18 三轮裁定）。
  ///
  /// 单节块只有 30px 高，两行必须各收一档字号（12.5/11 → 11/9.5）才放得下。

  /// 两门课之间是否「间隔超过 [dashboardCourseBreakMinutes]」。
  ///
  /// 口径 = **前一门课最后一节的结束时刻 → 后一门课第一节的开始时刻**，钟点取自
  /// 作息表；[periods] 为 null 或节次缺失时一律不算大间隔（宁可不画线）。

}

/// 指标卡：App 同源白卡，自定义内容区（[child]）。[color] 为功能点缀色。
///
/// [trailing] 挂在卡片头部行的尾部（右上角），**不占内容区高度** ——
/// 「课程加权」的排名胶囊就走这里。

