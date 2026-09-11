/// 校历「假/班」角标相关 providers：显示偏好、学籍条件、角标索引。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/school_calendar/data/calendar_prefs.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_mark.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// 校历显示偏好（改动即时通知，页面直接 watch）。
///
/// 实例由本 provider 持有/释放（`ChangeNotifierProvider` 会 dispose 它，
/// 故 [CalendarPrefsStore] 不做全局单例）。
final calendarPrefsStoreProvider = ChangeNotifierProvider<CalendarPrefsStore>((
  ref,
) {
  final store = CalendarPrefsStore();
  unawaited(store.ensureLoaded());
  return store;
});

/// 「看这份日历的人」：从学籍派生判定所需的两项条件（入学年 / 培养层次）。
///
/// 离线缓存命中即可用；取不到（未登录 / 未同步学籍）返回 [CalendarViewer.unknown]
/// —— 判定侧退化为「不过滤事件、军训不显示」，不阻塞校历展示。
final calendarViewerProvider = FutureProvider<CalendarViewer>((ref) async {
  final repo = await ref.watch(studentInfoRepositoryProvider.future);
  final info = repo.getCachedStudentInfo().fold((_) => null, (info) => info);
  return CalendarViewer(
    enrollYear: int.tryParse(info?.enrollYear.trim() ?? ''),
    trainLevel: info?.trainLevel,
  );
});

/// 角标索引：由全部学期官方安排 + 显示偏好 + 学籍条件构建。
final calendarMarkIndexProvider = Provider<CalendarMarkIndex>((ref) {
  final prefs = ref.watch(calendarPrefsStoreProvider).prefs;
  final terms =
      ref.watch(wxArrangementsProvider).valueOrNull ??
      const <WxSemesterArrangement>[];
  final viewer =
      ref.watch(calendarViewerProvider).valueOrNull ?? CalendarViewer.unknown;

  return CalendarMarkIndex.build(
    terms: terms,
    options: CalendarMarkOptions(
      enrollYear: viewer.enrollYear,
      alwaysShowMilitary: prefs.alwaysShowMilitary,
      filterByCategory: prefs.filterByCategory,
      trainLevel: viewer.trainLevel,
    ),
  );
});
