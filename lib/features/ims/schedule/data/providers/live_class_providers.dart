import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/anti_corruption/period_table_html_parser.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/datasources/period_table_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/period_table_repository.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/schedule_cache_repository.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/school_calendar_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/teaching_week.dart';

/// 作息时间表远程数据源。
///
/// 复用校历的免登录 Dio（同域 `/public/`、同 GBK、同匿名会话要求），
/// 不挂 IMS 认证拦截器 —— 作息表接口**不需要登录**，
/// 因而不受教务会话过期影响。
final periodTableRemoteDataSourceProvider =
    Provider<PeriodTableRemoteDataSource>(
      (ref) =>
          PeriodTableRemoteDataSource(ref.watch(schoolCalendarDioProvider)),
    );

/// 作息时间表 HTML 解析器。
final periodTableHtmlParserProvider = Provider<PeriodTableHtmlParser>(
  (ref) => PeriodTableHtmlParser(),
);

/// 作息时间表仓库（实时 + 缓存 + 兜底）。
final periodTableRepositoryProvider = Provider<PeriodTableRepository>(
  (ref) => PeriodTableRepository(
    remote: ref.watch(periodTableRemoteDataSourceProvider),
    parser: ref.watch(periodTableHtmlParserProvider),
  ),
);

/// 当前学段的作息时间表。
///
/// 学年学期口径与课表完全一致（见 [currentSchoolTerm]）：校历区间优先，
/// 假期取下一学期，月份经验规则仅作兜底。
final currentPeriodTableProvider = FutureProvider<PeriodTable>((ref) async {
  final repo = ref.watch(periodTableRepositoryProvider);
  final term = currentSchoolTerm(
    DateTime.now(),
    terms: ref.watch(offlineSemesterTermsProvider),
  );
  return repo.getTable(xn: term.xn, xq: term.xq);
});

/// 缓存中最近一个学期的作息表（不联网）。
///
/// 用于界面首帧先渲染已知内容，避免空白等待。
final cachedPeriodTableProvider = FutureProvider<PeriodTable>(
  (ref) => ref.watch(periodTableRepositoryProvider).cachedOrBuiltin(),
);

/// 当前教学周。
///
/// 口径说明见 `domain/teaching_week.dart`：**第 1 教学周 = 学期 `start` 所在周**
/// （261 → 2026-09-07）。注意「老生开始上课」09-14 属第 2 周，不是第 1 周。
final teachingWeekProvider = FutureProvider<TeachingWeek?>((ref) async {
  return resolveTeachingWeek(
    DateTime.now(),
    terms: ref.watch(offlineSemesterTermsProvider),
  );
});

/// 课表缓存仓库（cache-first，离线可用）。
final scheduleCacheRepositoryProvider = FutureProvider<ScheduleCacheRepository>(
  (ref) async {
    final inner = await ref.watch(scheduleRepositoryProvider.future);
    return ScheduleCacheRepository(inner);
  },
);
