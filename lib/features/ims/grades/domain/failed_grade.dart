/// 「挂科记录」的唯一判据（成绩页 / 毕业学分 / 推免页共用）。
///
/// 2026-10-08 立（用户原话：「不及格的话即使已修也算未获得学分，并且我希望有 UI
/// 提示……挂科可以产生一个联动，那就是一旦有挂科记录，保研分页就显示您已挂科，
/// 无保研资格之类的」）。
///
/// 判据 = **成绩表里有这门课**（= 已考核）**且获得学分为 0**。成绩表里的行都是
/// 出过分的，所以这不会把「还在修、没出分」误判成挂科 —— 那些走课表那条路。
///
/// ⚠ **重修通过也算「有挂科记录」**：推免资格看的是「有没有挂过」，不是「现在过没过」
/// （用户措辞是「一旦有挂科记录」）。所以这里不按课程去重掉已通过的记录 ——
/// 同一门课挂过又重修通过，仍然会出现在记录里。
library;

/// 一条挂科记录。
class FailedGrade {
  /// 课程代码（可能为空 —— 成绩表偶有缺码的行）。
  final String code;
  final String name;

  /// 课程学分（挂掉的就是这么多学分没拿到）。
  final double credit;

  /// 成绩分值（`优秀`/`良好` 这类等级制解析不出来 → null）。
  final double? score;

  /// 学期码，如 `251`（字典序即时间序）。
  final String semester;

  const FailedGrade({
    required this.code,
    required this.name,
    required this.credit,
    this.score,
    this.semester = '',
  });

  /// 分值的上屏文本（`58` / `58.5` / `—`）。
  String get scoreText =>
      score == null ? '—' : score!.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}
