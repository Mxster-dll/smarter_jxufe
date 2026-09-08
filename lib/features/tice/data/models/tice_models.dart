import 'package:flutter/painting.dart' show Color;

/// 国家学生体质健康测试（赛康精益 www.skjycx.com）数据模型。
///
/// 接口为微信小程序「赛康精益」后端：POST /src/StuSpace/queryStuResult.php。
/// 本 App 仅查询当前登录账号本人，学号取自登录账号。

/// 单分项成绩。
class TiceItem {
  /// 项目代码，如 whScore / FHLScore / RUN50Score / LDTScore / ZWTScore /
  /// RUNScore / YTYWScore（男=引体向上，女=仰卧起坐，同一代码按性别解释）。
  final String code;

  /// 服务端返回的项目名称（如「身高体重」「耐力跑」「仰卧起坐」）。
  final String name;

  /// 原始成绩（如 20.5、5879、3'47''、13）。
  final String result;

  /// 分项得分。
  final String score;

  /// 等级：优秀 / 良好 / 及格 / 不及格（可能为空 = 该项未测/缺测）。
  final String grade;

  const TiceItem({
    required this.code,
    required this.name,
    required this.result,
    required this.score,
    required this.grade,
  });

  factory TiceItem.fromJson(String code, Object? json) {
    final map = json is Map
        ? json.map((k, v) => MapEntry(k.toString(), v))
        : const <String, Object?>{};
    return TiceItem(
      code: code,
      name: map['testItem'] as String? ?? '',
      result: _str(map['result']),
      score: _str(map['score']),
      grade: _str(map['testclass']),
    );
  }
}

/// 单个测试学年的结果（一年一条）。
class TiceYearResult {
  final int year;
  final double? totalScore;
  final String totalGrade;
  final List<TiceItem> items;

  const TiceYearResult({
    required this.year,
    required this.totalScore,
    required this.totalGrade,
    required this.items,
  });
}

/// 接口返回的学生档案信息。
class TiceStuInfo {
  final String stuNum;
  final String stuName;
  final String stuSex;
  final String gradeNum;
  final String deptName;

  const TiceStuInfo({
    required this.stuNum,
    required this.stuName,
    required this.stuSex,
    required this.gradeNum,
    required this.deptName,
  });
}

/// 一次查询的结果。ok=false 时 message 为原因（如「该生成绩尚未上传(含免测)」）。
class TiceResult {
  final bool ok;
  final String message;
  final TiceStuInfo? info;

  /// 命中学年的成绩，按年份升序。
  final List<TiceYearResult> years;

  const TiceResult({
    required this.ok,
    required this.message,
    this.info,
    this.years = const [],
  });
}

/// 单分项等级 → 语义色。优秀绿 / 良好蓝 / 及格橙 / 不及格红。
class TiceGradeStyle {
  static const excellent = Color(0xFF2E7D32);
  static const good = Color(0xFF0288D1);
  static const pass = Color(0xFFEF6C00);
  static const fail = Color(0xFFC62828);

  static Color colorOf(String grade) => switch (grade.trim()) {
        '优秀' => excellent,
        '良好' => good,
        '及格' => pass,
        '不及格' => fail,
        _ => const Color(0xFF9E9E9E),
      };
}

String _str(Object? v) => v == null ? '' : '$v';
