import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/volunteer_hours_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/domain/volunteer_hours_stats.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/volunteer_hours_screen.dart';
import 'package:smarter_jxufe/features/electricity/data/models/electricity_models.dart';
import 'package:smarter_jxufe/features/electricity/data/providers/electricity_providers.dart';
import 'package:smarter_jxufe/features/electricity/presentation/electricity_screen.dart';
import 'package:smarter_jxufe/features/home/domain/grade_rank_badge.dart';
import 'package:smarter_jxufe/features/home_widget/data/home_widget_sync.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/weighted_grade_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/weighted_grade.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';
import 'package:smarter_jxufe/features/net_fee/data/providers/net_fee_providers.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';
import 'package:smarter_jxufe/features/net_fee/presentation/net_fee_screen.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';

/// 今日课程条目（从课表按「今天」过滤后抽出）。
class TodayCourse {
  final String courseName;
  final int startPeriod;
  final int endPeriod;
  final String classroom;
  final String? campus;

  const TodayCourse({
    required this.courseName,
    required this.startPeriod,
    required this.endPeriod,
    required this.classroom,
    this.campus,
  });

  String get periodLabel => '$startPeriod-$endPeriod节';
}

String todayLabel(DateTime now) {
  const weekCn = ['一', '二', '三', '四', '五', '六', '日'];
  return '${now.month}月${now.day}日 周${weekCn[now.weekday - 1]}';
}

/// 电费：当前账号若有本地绑定记忆，取服务端实时余额；否则为 null（未绑定）。
final dashboardElectricityProvider = FutureProvider<ElectricityBalance?>((
  ref,
) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) return null;
  final box = await ref.read(electricityBindingBoxProvider.future);
  final raw = box.get(account);
  if (raw == null || raw.isEmpty) return null;
  final decoded = jsonDecode(raw);
  if (decoded is! Map) return null;
  final record = RoomBindingRecord.fromJson(
    decoded.map((k, v) => MapEntry(k.toString(), v)),
  );
  if (record.roomId <= 0) return null;
  final dataSource = ref.watch(electricityRemoteDataSourceProvider);
  return dataSource.fetchBalance(username: account, roomId: record.roomId);
});

/// 志愿时长：当前账号活动记录 `recognizedHours` 求和，并额外给出**本学年**口径
/// （用户 2026-09-16 要求「志愿时长的仪表盘里还要显示本学年志愿时长」）。
///
/// 本学年 = **当下教学学年**（`currentSchoolTerm` 的 `xn`，与课表/校历同口径）；
/// 活动日期来自列表逐行详情页，取不到时 `yearKnown` 为 false → 卡片显示「—」。
final dashboardVolunteerHoursProvider = FutureProvider<VolunteerHoursStats>((
  ref,
) async {
  final activities = await ref.watch(volunteerActivitiesProvider.future);
  final now = DateTime.now();
  final term = currentSchoolTerm(
    now,
    terms: ref.watch(offlineSemesterTermsProvider),
  );
  return volunteerHoursStats(activities, xn: term.xn);
});

/// 今日课程：取当前学期课表，按今天星期过滤并按时段排序。
final dashboardTodayCoursesProvider = FutureProvider<List<TodayCourse>>((
  ref,
) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) return const [];
  final now = DateTime.now();
  // 当前学期口径 = 课表页同一函数（校历区间优先，假期取下一学期）。
  final term = currentSchoolTerm(
    now,
    terms: ref.watch(offlineSemesterTermsProvider),
  );
  final repository = await ref.watch(scheduleRepositoryProvider.future);
  final entries = await repository.getSchedule(
    year: '${term.xn}',
    semester: '${term.xq}',
    studentId: account,
  );
  final weekday = now.weekday; // 1=周一 … 7=周日
  final result = <TodayCourse>[];
  for (final entry in entries) {
    for (final ct in entry.classTimes) {
      if (ct.dayOfWeek.dayIndex == weekday) {
        result.add(
          TodayCourse(
            courseName: entry.courseName,
            startPeriod: ct.startPeriod,
            endPeriod: ct.endPeriod,
            classroom: ct.classroom,
            campus: ct.campus,
          ),
        );
      }
    }
  }
  result.sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
  return result;
});

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

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(dashboardElectricityProvider);
    ref.invalidate(dashboardVolunteerHoursProvider);
    ref.invalidate(weightedGradeRankingProvider(1));
    ref.invalidate(dashboardTodayCoursesProvider);
    ref.invalidate(netFeeSummaryProvider);
    // 顺手同步桌面小组件：用户点「刷新」时，桌面上的数字也应跟着更新。
    final widgetSync = ref.read(homeWidgetSyncProvider);
    await widgetSync.pushAuthSnapshot();
    await widgetSync.syncAll(force: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final f = fp(context);
    final now = DateTime.now();

    final electricityAsync = ref.watch(dashboardElectricityProvider);
    final volunteerAsync = ref.watch(dashboardVolunteerHoursProvider);
    final gradeAsync = ref.watch(weightedGradeRankingProvider(1));
    final coursesAsync = ref.watch(dashboardTodayCoursesProvider);
    final netFeeAsync = ref.watch(netFeeSummaryProvider);

    // 用户 2026-09-18 裁定：去掉「数据一览」小标题；其他卡片在左、今日课程在右，
    // 窄屏上下堆叠。
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _buildMetrics(
          context,
          scheme,
          f,
          electricityAsync,
          volunteerAsync,
          gradeAsync,
          netFeeAsync,
        );
        // 作息表（与课表页同源：实时优先、缓存/内置兜底）——
        // 「间隔超过 1 小时」的分隔线要按它把节次换算成钟点。
        final periodTable =
            ref.watch(currentPeriodTableProvider).valueOrNull ??
            ref.watch(cachedPeriodTableProvider).valueOrNull;
        final today = _buildTodayCourses(
          context,
          ref,
          scheme,
          now,
          coursesAsync,
          periodTable,
        );
        // 恒为左右两栏（用户 2026-09-18 四轮裁定：「即使移动端，也是这种
        // 左右 2 : 1 的显示」）—— 窄屏不再上下堆叠，指标卡自动退成单列。
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: metrics),
            const SizedBox(width: DashboardPanel.dashboardColumnGap),
            Expanded(child: today),
          ],
        );
      },
    );
  }

  /// 指标卡区（电费 / 校园网 / 课程加权 / 志愿时长）：按可用宽度自适应列数。
  Widget _buildMetrics(
    BuildContext context,
    ColorScheme scheme,
    FeatureColors f,
    AsyncValue<ElectricityBalance?> electricityAsync,
    AsyncValue<VolunteerHoursStats> volunteerAsync,
    AsyncValue<WeightedGrade?> gradeAsync,
    AsyncValue<NetFeeSummary> netFeeAsync,
  ) {
    return LayoutBuilder(
      key: const Key('dashMetrics'),
      builder: (context, constraints) {
        const minCard = 210.0;
        const gap = 12.0;
        // 窄屏（手机端 2:1 后左栏只有 ~200dp）算出来会是 0 列 →
        // `gap * (cols - 1)` 变负数、`/ cols` 变 NaN，必须兜到 1 列。
        var cols = (constraints.maxWidth + gap) ~/ (minCard + gap);
        if (cols < 1) cols = 1;
        final width = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: width,
              child: _MetricCard(
                icon: Icons.electrical_services,
                color: f.electricity,
                label: '电费余额',
                onTap: () => _push(context, const ElectricityScreen()),
                child: _valueArea<ElectricityBalance?>(
                  scheme,
                  electricityAsync,
                  valueOf: (b) => b?.balance ?? '--',
                  unitOf: (b) => b?.unit ?? '',
                  emptyText: '未绑定宿舍',
                  valueKey: const Key('dash_electricity'),
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: _MetricCard(
                icon: Icons.wifi_outlined,
                color: f.netFee,
                label: '校园网',
                onTap: () => _push(context, const NetFeeScreen()),
                child: _valueArea<NetFeeSummary>(
                  scheme,
                  netFeeAsync,
                  valueOf: (s) =>
                      s.balance == null ? '--' : fmtYuan(s.balance!),
                  unitOf: (s) => s.balance == null ? '' : '元',
                  emptyText: '暂无数据',
                  valueKey: const Key('dash_netfee'),
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: _MetricCard(
                icon: Icons.auto_graph_outlined,
                color: f.grade,
                label: '课程加权',
                onTap: () => _push(
                  context,
                  ImsSplashScreen(initialTab: ImsTab.grade),
                ),
                // 排名不占卡片高度：塞右上角一枚胶囊（班级/专业/年级）。
                trailing: gradeAsync.valueOrNull == null
                    ? null
                    : _gradeRankCapsule(context, gradeAsync.valueOrNull!),
                child: _buildGradeContent(scheme, gradeAsync),
              ),
            ),
            SizedBox(
              width: width,
              child: _MetricCard(
                icon: Icons.volunteer_activism,
                color: f.volunteer,
                label: '志愿时长',
                onTap: () => _push(context, const VolunteerHoursScreen()),
                // 本学年时长塞右上角胶囊（与排名胶囊同位置，不占卡片高度）。
                trailing: _volunteerYearCapsule(context, volunteerAsync),
                child: _valueArea<VolunteerHoursStats>(
                  scheme,
                  volunteerAsync,
                  valueOf: (s) => _trimHours(s.total),
                  unitOf: (_) => 'h',
                  emptyText: '0 h',
                  valueKey: const Key('dash_volunteer'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _trimHours(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// 课程加权卡内容：只有加权分（单行自适应）。
  ///
  /// 排名（班级 / 专业 / 年级）自 2026-09-15 起不再占一行高度 ——
  /// 用户裁定「排名不要占用高度，而是显示在右上角的一个胶囊」，
  /// 胶囊由 [_gradeRankCapsule] 渲染、挂在卡片头部行的尾部。
  Widget _buildGradeContent(
    ColorScheme scheme,
    AsyncValue<WeightedGrade?> async,
  ) {
    return async.when(
      loading: () => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) =>
          _inlineStatus(scheme, Icons.error_outline, '获取失败，点右上角刷新'),
      data: (grade) {
        if (grade == null) {
          return _inlineStatus(scheme, Icons.link_off, '暂无成绩');
        }
        return Column(
          key: const Key('dash_grade'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [_fittedValueRow(scheme, value: grade.grade, unit: '分')],
        );
      },
    );
  }

  /// 排名胶囊：`#班级/专业/年级`（用户 2026-09-15 裁定 a/b/c 三个数字，
  /// 同日二轮改为 `#a/b/c` 紧凑写法：`#` 前缀 + 斜杠分隔、无空格）。
  ///
  /// 取不到的排名（≤ 0）写 `—`；完整含义放 tooltip（桌面悬停 / 手机长按）。
  Widget _gradeRankCapsule(BuildContext context, WeightedGrade grade) {
    final accent = appCardAccent(context);
    return Tooltip(
      message: gradeRankTooltip(
        classRank: grade.classRank,
        majorRank: grade.majorRank,
        gradeRank: grade.gradeRank,
      ),
      child: Container(
        key: const Key('dash_grade_rank'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: appCardAccentSoft(context),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          gradeRankBadge(
            classRank: grade.classRank,
            majorRank: grade.majorRank,
            gradeRank: grade.gradeRank,
          ),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  /// 本学年志愿时长胶囊（右上是功能色，取值同卡片的 `color`）。
  ///
  /// 徽标只放数字（`本学年 24h`），学年名与**上一学年的对照值**放 tooltip ——
  /// 卡片头部只有一行；本学年为 0 时用户最需要知道「那是上一学年的量」。
  Widget _volunteerYearCapsule(
    BuildContext context,
    AsyncValue<VolunteerHoursStats> async,
  ) {
    final stats = async.valueOrNull;
    if (stats == null) return const SizedBox.shrink();
    final f = fp(context);
    final text = stats.yearKnown
        ? '本学年 ${_trimHours(stats.currentYear)}h'
        : '本学年 —';
    final message = stats.yearKnown
        ? '${stats.yearLabel}志愿时长 ${_trimHours(stats.currentYear)} 小时'
              '${stats.previousYear > 0 ? ' · 上一学年 ${_trimHours(stats.previousYear)} 小时' : ''}'
        : '活动日期获取失败，无法判定本学年志愿时长';
    return Tooltip(
      message: message,
      child: Container(
        key: const Key('dash_volunteer_year'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.tint(context, f.volunteer, 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: f.volunteer,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  /// 单行自适应数值行：卡宽不足时整体等比缩小，保证完整显示不换行。
  Widget _fittedValueRow(
    ColorScheme scheme, {
    required String value,
    required String unit,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            unit,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 指标卡内容：loading / error / 空态 / 数值。
  Widget _valueArea<T>(
    ColorScheme scheme,
    AsyncValue<T> async, {
    required String Function(T data) valueOf,
    required String Function(T data) unitOf,
    required String emptyText,
    required Key valueKey,
  }) {
    return async.when(
      loading: () => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) =>
          _inlineStatus(scheme, Icons.error_outline, '获取失败，点右上角刷新'),
      data: (data) {
        if (data == null) {
          return _inlineStatus(scheme, Icons.link_off, emptyText);
        }
        return FittedBox(
          key: valueKey,
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                valueOf(data),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unitOf(data),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _inlineStatus(ColorScheme scheme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  // ---------- 今日课程 ----------

  Widget _buildTodayCourses(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
    DateTime now,
    AsyncValue<List<TodayCourse>> async,
    PeriodTable? periods,
  ) {
    return Material(
      key: const Key('dashTodayCard'),
      color: Theme.of(context).cardTheme.color,
      shape: appCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            _push(context, ImsSplashScreen(initialTab: ImsTab.schedule)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 手机端也是左右 2 : 1（用户 2026-09-18 四轮裁定）→ 右栏在 360dp
            // 手机上只有约 100dp：卡片内边距、头部图标盒、字号都要收一档，
            // 否则「图标盒 40 + 间距 12 + 刷新按钮 40」本身就超过可用宽度。
            final narrow =
                constraints.maxWidth < todayCourseCardNarrowBreakpoint;
            return Padding(
              padding: narrow
                  ? const EdgeInsets.fromLTRB(10, 10, 6, 10)
                  : const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
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
                      // 全面板唯一的刷新入口：原来是「数据一览」标题行右侧那个；
                      // 小标题撤掉后搬到这里（卡片本体仍是「点开课表」）。
                      IconButton(
                        key: const Key('dashRefresh'),
                        tooltip: '刷新数据',
                        visualDensity: VisualDensity.compact,
                        padding: narrow ? EdgeInsets.zero : null,
                        icon: Icon(Icons.refresh, size: narrow ? 16 : 18),
                        onPressed: () => _refresh(ref),
                      ),
                    ],
                  ),
                  SizedBox(height: narrow ? 8 : 10),
                  ..._todayCourseSlots(
                    context,
                    scheme,
                    async,
                    periods,
                    narrow: narrow,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

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
        _inlineStatus(
          scheme,
          Icons.error_outline,
          '课表获取失败：${e.toString().replaceAll('Exception: ', '')}',
        ),
      ],
      data: (courses) {
        if (courses.isEmpty) {
          return [
            _inlineStatus(
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
                (previousEnd - 1) * todayCourseTrackHeight +
                todayCourseSlotHeight;
            final rawGapBottom = (start - 1) * todayCourseTrackHeight;
            final rawGap = rawGapBottom - rawGapTop;
            // ⚠ 空档不足一条分隔带就**撑开**（2026-09-18 七轮）：典型是**午休** ——
            // 第 5 节 12:20 下课、第 6 节 14:00 上课（钟点差 100 分钟），但两块课在
            // 时间轴上只差一个轨道减一个节高 = 4dp；六轮时把分隔带收缩进 4dp，结果线
            // 上下各 1dp、与宽空档那条（线下 8dp）观感不一致。现在一律撑到
            // dashboardBreakBandHeight：线下 8dp、线上 4dp 留白，**每条分隔线完全一样**。
            final extra = rawGap >= dashboardBreakBandHeight
                ? 0.0
                : dashboardBreakBandHeight - rawGap;
            shifted += extra;
            blocks.add(
              Positioned(
                top: rawGapBottom + shifted - dashboardBreakBandHeight,
                left: 0,
                right: 0,
                height: dashboardBreakBandHeight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: dashboardBreakLineGap),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      key: Key('dashTodayBreak-${course.startPeriod}'),
                      height: dashboardBreakLineHeight,
                      color: AppColors.hairline(context, 0.9),
                    ),
                  ),
                ),
              ),
            );
          }
          blocks.add(
            Positioned(
              top: (start - 1) * todayCourseTrackHeight + shifted,
              left: 0,
              right: 0,
              height:
                  (end - start + 1) * todayCourseTrackHeight -
                  todayCourseSlotGap,
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
                schedulePeriodCount * todayCourseTrackHeight -
                todayCourseSlotGap +
                shifted,
            child: Stack(children: blocks),
          ),
        ];
      },
    );
  }

  /// 一门课一块：**名称在上、教室在下**（用户 2026-09-18 三轮裁定）。
  ///
  /// 单节块只有 30px 高，两行必须各收一档字号（12.5/11 → 11/9.5）才放得下。
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

  /// 两门课之间是否「间隔超过 [dashboardCourseBreakMinutes]」。
  ///
  /// 口径 = **前一门课最后一节的结束时刻 → 后一门课第一节的开始时刻**，钟点取自
  /// 作息表；[periods] 为 null 或节次缺失时一律不算大间隔（宁可不画线）。
  static bool _isLongBreak(
    PeriodTable? periods,
    TodayCourse previous,
    TodayCourse next,
  ) {
    if (periods == null) return false;
    final end = periods.periodOf(previous.endPeriod);
    final start = periods.periodOf(next.startPeriod);
    if (end == null || start == null) return false;
    return start.startMinutes - end.endMinutes > dashboardCourseBreakMinutes;
  }
}

/// 指标卡：App 同源白卡，自定义内容区（[child]）。[color] 为功能点缀色。
///
/// [trailing] 挂在卡片头部行的尾部（右上角），**不占内容区高度** ——
/// 「课程加权」的排名胶囊就走这里。
class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget child;

  const _MetricCard({
    required this.icon,
    required this.color,
    required this.label,
    this.onTap,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).cardTheme.color,
      shape: appCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: color.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.tint(context, color, 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 6),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
