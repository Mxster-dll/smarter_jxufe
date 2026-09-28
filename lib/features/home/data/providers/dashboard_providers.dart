/// 首页「数据一览」的数据源 providers（**非**渲染层）。
///
/// ⚠ 为什么单独成文件（2026-09-20 · 架构审查 ⑦）：这些 provider 从前写在
/// `home/presentation/dashboard_panel.dart` 里，而桌面小组件的数据同步
/// （`features/home_widget/data/home_widget_sync.dart`，**data 层**）要复用同一口径
/// —— 于是出现了「data 层 import 别家 presentation」的越界依赖。
/// 口径本身（电费/志愿/今日课表怎么算）属于数据层，渲染（`DashboardPanel`）与
/// 「下拉刷新」编排（`refreshDashboard`，依赖 home_widget 同步）留在 presentation。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/volunteer_hours_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/domain/volunteer_hours_stats.dart';
import 'package:smarter_jxufe/features/electricity/data/models/electricity_models.dart';
import 'package:smarter_jxufe/features/electricity/data/providers/electricity_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/school_time_providers.dart';
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
/// 学年窗口取自校历（`schoolTimeTableProvider`）—— 取不到时该 provider 内部退回
/// 固定口径 `[xn]-09-01 ~ [xn+1]-08-31`，不会让卡片卡住或抛错。
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
  final table = await ref.watch(schoolTimeTableProvider(term.xn).future);
  return volunteerHoursStats(activities, xn: term.xn, table: table);
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
  // 课表：**cache-first + 联网刷新 + 失败降级**（与实况窗 `live_class_screen`
  // 同一套口径）。教务会话过期 / 网络抖动时退回本地缓存，卡片照常显示今天
  // 有什么课；从前直接用在线仓库，一次失败就在首页摊一张红字
  // 「课表获取失败：凭证已失效，请重新登录」（用户 2026-09-19 报的问题）。
  // 缓存也为空时才把异常抛给卡片。
  final cacheRepository = await ref.watch(
    scheduleCacheRepositoryProvider.future,
  );
  final cached = await cacheRepository.load(
    year: '${term.xn}',
    semester: '${term.xq}',
    studentId: account,
    refresh: true,
  );
  final entries = cached.entries;
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
