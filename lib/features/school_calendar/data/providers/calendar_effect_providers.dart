/// 校历效应的取数入口：其它模块（课表 / 首页今日课程 / 实况窗 / 课前提醒）
/// 一律从这里取 [CalendarDayEffectIndex]，别各自去 build 判定。
///
/// 口径：**实时校历优先、内置快照兜底**（与校历页一致，见 `wxcal_providers.dart`）。
/// 线程模型是「同步 Provider + `valueOrNull`」：内置快照让首帧就有数据，
/// 实时数据回来时 provider 自动重建、界面跟着更新（不阻塞、不闪空白）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_effect.dart';

/// 校历效应索引（假 / 班 → 课表安排）。
///
/// ⚠ 刻意**不传** `CalendarMarkOptions`：课表只看「假」与「班」，这两类不受
/// 人群过滤与军训开关影响（见 `calendar_day_mark.dart`）；学籍上下文留在校历页。
final calendarDayEffectIndexProvider = Provider<CalendarDayEffectIndex>((ref) {
  final live = ref.watch(wxArrangementsProvider).valueOrNull;
  final terms = (live == null || live.isEmpty)
      ? ref.watch(offlineSemesterTermsProvider)
      : live;
  return CalendarDayEffectIndex.build(terms: terms);
});
