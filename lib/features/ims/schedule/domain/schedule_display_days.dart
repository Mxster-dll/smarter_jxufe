/// 课表「显示周六 / 显示周日」的领域口径。
///
/// 唯一实现：可见天列表、星期显示名、以及「某天这一学期有多少门课」的计数。
/// 两个视图（竖版 / 横版）与设置页都走这里，别各写一份。
///
/// ## 隐藏是**有条件**的（用户 2026-10-07 修订，2026-10-08 细化粒度）
/// 原话：「修改一下课表隐藏周六、周日的逻辑，隐藏生效仅当没课时才生效，如果某周周 x
/// 有课，但是设置又是隐藏周 x，那么此时这天还是显示的」。
/// 即：开关只负责「**本次展示范围**这一天都没课时把这一列收起来」，**有课的列永远
/// 照常显示** —— 「有课却看不见」这件事从此不可能发生，所以设置页也不再有「隐藏后
/// 看不到课」的确认框。
/// ⚠ 2026-10-08 二轮补充（用户原话：「如果周六在第 5 周因为补课而有课，但是其他周
/// 没有，那么在其他周的视图中，周六就不应该显示。只有在第五周的视图中周六显示」）：
/// 粒度是**一周**，但**冻结在「分页器停稳」那一刻**（动画途中不许改列数，否则整屏
/// 在飞行中重排）。口径由页面负责（`schedule_screen.dart` 的 `_layoutWeek`）。
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
///
/// [daysWithClass] = **本次展示范围**里**真的有课**的星期（由 `schedule_board.dart` 的
/// `scheduleDaysWithClass` 算出，已考虑校历假期与调课）：只有它没包含这一天时，
/// 开关才真的把这一列收起来（用户 2026-10-07：「隐藏生效仅当没课时才生效」）。
///
/// ⚠ **「本次展示范围」的粒度 = 页面上停稳的那一周**（用户 2026-10-08 二轮）：分页器
/// 的静态表头与相邻页共用这一份列集合，若它随「正在看第几周」逐页变化，切周动画途中
/// 就会「列数 6→5、列宽重排」（实测就是用户报的「起点 / 终点是本周时动画错乱」）；
/// 若改成整学期一刀切，又变成「第 6 周也显示周六」（用户同日否决）。
/// 故口径 = **按已落定的那一周算、动画期间冻结**，由页面负责传进来
/// （`schedule_screen.dart` 的 `_layoutWeek` + `visibleDays:`）。
List<int> scheduleVisibleDays({
  bool showSaturday = true,
  bool showSunday = true,
  Set<int> daysWithClass = const <int>{},
}) => <int>[
  for (var day = 0; day < scheduleDayNames.length; day++)
    if ((day != scheduleSaturdayIndex ||
            showSaturday ||
            daysWithClass.contains(day)) &&
        (day != scheduleSundayIndex ||
            showSunday ||
            daysWithClass.contains(day)))
      day,
];

/// 某一天在整学期里涉及的**课程门数**（按课程名去重）。
///
/// 用 `week: null` 数整学期（而不是当前这一周）：设置页要能提示
/// 「周六这一学期有 N 门课」，而不是「本周六恰好没课」。
/// 计数含调课产生的课次（与课表显示同源，见 [effectiveClasses]）。
///
/// ⚠ 这是**不认校历**的粗计数（只服务设置页那行说明文案）。
/// 「这一周到底要不要显示这一天」一律走 `scheduleDaysWithClass`。
int scheduleDayCourseCount(
  List<ScheduleEntry> entries,
  int dayIndex, {
  List<Reschedule> reschedules = const [],
}) {
  if (dayIndex < 0 || dayIndex >= scheduleDayNames.length) return 0;
  final names = <String>{};
  for (final c in effectiveClasses(
    entries: entries,
    reschedules: reschedules,
  )) {
    if (c.dayIndex - 1 == dayIndex) names.add(c.courseName);
  }
  return names.length;
}
