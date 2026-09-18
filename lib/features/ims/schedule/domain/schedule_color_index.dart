/// 课表课程配色：把「课程」映射到一个**稳定且互不相同**的配色下标。
///
/// 用户 2026-09-17：「我希望优先保证每门课程的颜色都不同，实在不行再重复」。
///
/// **为什么不能再用哈希取模**：从前两个视图都写
/// `entry.courseCode.hashCode.abs() % 配色数` —— 哈希取模下撞色是**常态**而不是
/// 例外（生日问题：10 门课塞进 14 个槽位，「完全不撞」的概率只有约 4%），
/// 用户看到的重复就是这么来的。要「每门课一个色」必须按**课程身份**发号，
/// 也就是这份去重表；配色本身仍留在 `schedule_tone.dart`（`courseFills` /
/// `courseTexts`），这里只管发号。
///
/// 发号口径：
/// * 键 = [scheduleColorKeyOf]（**课程号优先**，同一门课的多个班次共用一色）；
/// * 键**升序排序**后依次发号 0, 1, 2, … —— 排序是为了让结果只取决于「有哪些课」，
///   与课表接口返回的行序无关：换周、下拉刷新、横竖版切换、两个视图之间都不会变色；
/// * 课程数 ≤ 配色数（现为 14，见 `ScheduleTone.courseFills`）→ **全部不同**；
///   超过配色数才按下标取模重复（第 15 门与第 1 门同色）。
library;

import 'schedule_entry.dart';

/// 配色的身份键：课程号优先；课程号为空（脏数据 / 未选课占位行）时退回班级号。
String scheduleColorKeyOf(ScheduleEntry entry) {
  final code = entry.courseCode.trim();
  if (code.isNotEmpty) return code;
  return entry.classCode.trim();
}

/// 课程 → 配色下标（**每门课一个不同的色**）。
///
/// 返回值喂给 `ScheduleTone.fill/name/meta` 的 `seed` 参数 —— 那些函数内部仍走
/// `seed % 配色数`，所以这里发出去的是「第几门课」。取不到键的课程由调用方自行
/// 兜底（两个视图回落到旧的哈希值，行为与改动前一致）。
Map<String, int> scheduleColorIndices(Iterable<ScheduleEntry> entries) {
  final keys = <String>{};
  for (final entry in entries) {
    final key = scheduleColorKeyOf(entry);
    if (key.isNotEmpty) keys.add(key);
  }
  final sorted = keys.toList()..sort();
  return {for (var i = 0; i < sorted.length; i++) sorted[i]: i};
}
