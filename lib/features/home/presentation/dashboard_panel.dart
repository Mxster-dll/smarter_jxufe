import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/volunteer_hours_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/volunteer_hours_screen.dart';
import 'package:smarter_jxufe/features/electricity/data/models/electricity_models.dart';
import 'package:smarter_jxufe/features/electricity/data/providers/electricity_providers.dart';
import 'package:smarter_jxufe/features/electricity/presentation/electricity_screen.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/weighted_grade_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/weighted_grade.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';
import 'package:smarter_jxufe/features/net_fee/data/providers/net_fee_providers.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';
import 'package:smarter_jxufe/features/net_fee/presentation/net_fee_screen.dart';

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

/// 当前学年学期（用于课表检索）：9 月 ~ 次年 2 月 = 上半学年（semester 0），
/// 3 ~ 8 月 = 下半学年（semester 1），学年起始年随日期回推。
(int year, String semester) currentTermOf(DateTime now) {
  if (now.month >= 3 && now.month <= 8) return (now.year - 1, '1');
  return (now.year, '0');
}

String todayLabel(DateTime now) {
  const weekCn = ['一', '二', '三', '四', '五', '六', '日'];
  return '${now.month}月${now.day}日 周${weekCn[now.weekday - 1]}';
}

/// 电费：当前账号若有本地绑定记忆，取服务端实时余额；否则为 null（未绑定）。
final dashboardElectricityProvider = FutureProvider<ElectricityBalance?>(
  (ref) async {
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
    final dataSource =
        ref.watch(electricityRemoteDataSourceProvider);
    return dataSource.fetchBalance(
      username: account,
      roomId: record.roomId,
    );
  },
);

/// 志愿时长：当前账号活动记录 `recognizedHours` 求和。
final dashboardVolunteerHoursProvider = FutureProvider<double>((ref) async {
  final activities = await ref.watch(volunteerActivitiesProvider.future);
  return activities.fold<double>(
    0,
    (sum, a) => sum + (double.tryParse(a.recognizedHours) ?? 0),
  );
});

/// 今日课程：取当前学期课表，按今天星期过滤并按时段排序。
final dashboardTodayCoursesProvider = FutureProvider<List<TodayCourse>>(
  (ref) async {
    final account = ref.watch(currentAccountProvider);
    if (account.isEmpty) return const [];
    final now = DateTime.now();
    final (year, semester) = currentTermOf(now);
    final repository = await ref.watch(scheduleRepositoryProvider.future);
    final entries = await repository.getSchedule(
      year: '$year',
      semester: semester,
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
  },
);

/// 首页仪表盘总览面板：电费 / 网费 / 成绩（累计加权）/ 志愿时长 / 今日课程。
///
/// 各数据块独立加载容错；点按跳对应详情页。视觉与首页功能卡同源
/// （白卡细描边圆角 8 + 主色浅底图标盒）。
class DashboardPanel extends ConsumerWidget {
  const DashboardPanel({super.key});

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(dashboardElectricityProvider);
    ref.invalidate(dashboardVolunteerHoursProvider);
    ref.invalidate(weightedGradeRankingProvider(1));
    ref.invalidate(dashboardTodayCoursesProvider);
    ref.invalidate(netFeeSummaryProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();

    final electricityAsync = ref.watch(dashboardElectricityProvider);
    final volunteerAsync = ref.watch(dashboardVolunteerHoursProvider);
    final gradeAsync = ref.watch(weightedGradeRankingProvider(1));
    final coursesAsync = ref.watch(dashboardTodayCoursesProvider);
    final netFeeAsync = ref.watch(netFeeSummaryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 13,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '数据一览',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: '刷新',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => _refresh(ref),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const minCard = 210.0;
            const gap = 12.0;
            final cols =
                (constraints.maxWidth + gap) ~/ (minCard + gap);
            final width = (constraints.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: width,
                  child: _MetricCard(
                    icon: Icons.electrical_services,
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
                    label: '网费',
                    onTap: () => _push(context, const NetFeeScreen()),
                    child: _valueArea<NetFeeSummary>(
                      scheme,
                      netFeeAsync,
                      valueOf: (s) => s.balance == null ? '--' : fmtYuan(s.balance!),
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
                    label: '课程加权',
                    onTap: () =>
                        _push(context, ImsSplashScreen(initialTab: ImsTab.grade)),
                    child: _buildGradeContent(scheme, gradeAsync),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _MetricCard(
                    icon: Icons.volunteer_activism,
                    label: '志愿时长',
                    onTap: () =>
                        _push(context, const VolunteerHoursScreen()),
                    child: _valueArea<double>(
                      scheme,
                      volunteerAsync,
                      valueOf: (v) => _trimHours(v),
                      unitOf: (_) => 'h',
                      emptyText: '0 h',
                      valueKey: const Key('dash_volunteer'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        _buildTodayCourses(context, ref, scheme, now, coursesAsync),
      ],
    );
  }

  static String _trimHours(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// 课程加权卡内容：完整加权分（单行自适应）+ 专业排名第二行。
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
      error: (_, _) => _inlineStatus(
        scheme,
        Icons.error_outline,
        '获取失败，点右上角刷新',
      ),
      data: (grade) {
        if (grade == null) {
          return _inlineStatus(scheme, Icons.link_off, '暂无成绩');
        }
        final rank = grade.majorRank;
        return Column(
          key: const Key('dash_grade'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fittedValueRow(
              scheme,
              value: grade.grade,
              unit: '分',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.emoji_events_outlined,
                    size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Text(
                  '专业排名',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  rank > 0 ? '第 $rank 名' : '未上榜',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ],
        );
      },
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
      error: (_, _) => _inlineStatus(
        scheme,
        Icons.error_outline,
        '获取失败，点右上角刷新',
      ),
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
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant),
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
  ) {
    return Material(
      color: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            _push(context, ImsSplashScreen(initialTab: ImsTab.schedule)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.today_outlined,
                        size: 20, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '今日课程',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          todayLabel(now),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 20, color: Colors.transparent),
                ],
              ),
              const SizedBox(height: 10),
              ..._todayCoursesBody(context, scheme, async),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _todayCoursesBody(
    BuildContext context,
    ColorScheme scheme,
    AsyncValue<List<TodayCourse>> async,
  ) {
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
        _inlineStatus(scheme, Icons.error_outline,
            '课表获取失败：${e.toString().replaceAll('Exception: ', '')}'),
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
        return [
          for (final c in courses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      c.periodLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      c.courseName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      c.classroom.isEmpty ? '' : c.classroom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ];
      },
    );
  }
}

/// 指标卡：App 同源白卡，自定义内容区（[child]）。
class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget child;

  const _MetricCard({
    required this.icon,
    required this.label,
    this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: scheme.primary.withValues(alpha: 0.04),
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
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: scheme.primary),
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
