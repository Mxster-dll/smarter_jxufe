/// 课表「显示周六 / 显示周日」的领域口径（用户 2026-09-17 需求）。
///
/// 唯一实现：可见天列表、星期显示名、以及「某天这一学期有多少门课」的计数。
/// 两个视图（竖版 / 横版）与设置页关闭开关时的确认框都走这里，别各写一份。
library;

import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule_engine.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';

/// 周一至周日的显示名（下标 0 = 周一，与 `EffectiveClass.dayIndex - 1` 同口径）。
const List<String> scheduleDayNames = <String>[
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
  '周日',
];

/// 周六 / 周日在 [scheduleDayNames] 里的下标。
const int scheduleSaturdayIndex = 5;
const int scheduleSundayIndex = 6;

/// 当前可见的天（下标列表，0 = 周一）。
///
/// 关掉周六 / 周日只影响**显示**：剩下的天重新等分可用宽度，
/// 课表本身（缓存、调课、通知）都不变，随时可以再打开。
List<int> scheduleVisibleDays({
  bool showSaturday = true,
  bool showSunday = true,
}) => <int>[
  for (var day = 0; day < scheduleDayNames.length; day++)
    if ((day != scheduleSaturdayIndex || showSaturday) &&
        (day != scheduleSundayIndex || showSunday))
      day,
];

/// 某一天在整学期里涉及的**课程门数**（按课程名去重）。
///
/// 用 `week: null` 数整学期（而不是当前这一周）：设置页关闭开关时要能提示
/// 「周六这一学期有 N 门课」，而不是「本周六恰好没课」。
/// 计数含调课产生的课次（与课表显示同源，见 [effectiveClasses]）。
int scheduleDayCourseCount(
  List<ScheduleEntry> entries,
  int dayIndex, {
  List<Reschedule> reschedules = const [],
}) {
  if (dayIndex < 0 || dayIndex >= scheduleDayNames.length) return 0;
  final names = <String>{};
  for (final c in effectiveClasses(entries: entries, reschedules: reschedules)) {
    if (c.dayIndex - 1 == dayIndex) names.add(c.courseName);
  }
  return names.length;
}
