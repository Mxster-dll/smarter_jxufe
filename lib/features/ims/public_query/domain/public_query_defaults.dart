/// 公共查询「按当前账号预填筛选条件」的纯匹配逻辑（无 IO，可直接单测）。
///
/// 口径来自 2026-09-14 的**真实会话实测**（TGC → CAS 换新票 → 激活 → 各层选择器）：
/// - 校区 `MsSchoolArea` 的显示名与 `MyCampus.name` **同字面**：`1` 蛟桥园校区 /
///   `3` 麦庐园校区 / `4` 枫林园校区 / `05` 深圳校区 / `06` 北京校区 / `07` 上海校区。
///   教务**没有**「青山园校区」→ 匹配不到就留空，绝不猜。
/// - 学院 `MsYXB`（`nj` + **`isYXB=0`**）显示名剥掉 `[143]` 前缀后 = 学籍 `college`；
/// - 专业 `MsYXB_Specialty`（`nj&dwh`）显示名 = 学籍 `major`（实测 `4405` 精确等于
///   `计算机科学与技术`，**不能**命中 `1842` 的「计算机科学与技术(拔尖实验班)」）；
/// - 班级选择器 `kbbp_dykb_SpecialClassComb`（`xn&xq_m&nj&yxb&zy&flag&xqdm`）显示名
///   = 学籍 `className`（`[2508090D52]计算机科学与技术252` → `计算机科学与技术252`）。
///
/// ⚠ **年级（`nj`）必须用学籍入学年，不是学年**：2025 级的班只在 `nj=2025` 的列表里，
/// `nj=2026` 里没有——学院/专业/班级三项默认全靠它才对得上（见 §14）。
///
/// ⚠ 班级列表**必须**用「与班级配套的校区」去取（`xqdm`）：校区不对 → 列表里没有这个班，
/// 报告也会恒回「没有检索到记录」。跨校区纠正在界面层（要发请求）完成。
library;

import 'package:flutter/foundation.dart';

import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';

/// 账号侧输入（只取匹配要用的字段，别把整个 `StudentInfo` 灌进判定层）。
@immutable
class PublicQueryAccountProfile {
  /// 学籍入学年 `<rxnj>`（如 `2025`）——公共查询的「年级」用它，**不是学年**。
  final String enrollYear;

  /// 学籍院系部 `<yxb>`。
  final String college;

  /// 学籍专业名称 `<zymc>`。
  final String major;

  /// 学籍班级名称 `<bjmc>`。
  final String className;

  /// 「我的校区」偏好（`MyCampus.label`，如 `麦庐园校区`；空串 = 未设置）。
  ///
  /// ⚠ 是 `label` 不是 enum 的 `name`（`mailu`）——教务校区选项用的是中文全称。
  final String campusName;

  const PublicQueryAccountProfile({
    this.enrollYear = '',
    this.college = '',
    this.major = '',
    this.className = '',
    this.campusName = '',
  });

  /// 四项账号信息都没拿到（「我的校区」也没设）→ 无从预填。
  bool get isEmpty =>
      enrollYear.trim().isEmpty &&
      college.trim().isEmpty &&
      major.trim().isEmpty &&
      className.trim().isEmpty &&
      campusName.trim().isEmpty;

  @override
  String toString() =>
      'PublicQueryAccountProfile($enrollYear, $college, $major, $className, '
      '$campusName)';
}

/// 解析出的账号默认筛选（每项都可能为 null = 匹配不到，界面保持「不限 / 全部」）。
@immutable
class PublicQueryAccountDefaults {
  /// 年级（`nj`）：学籍入学年，落在下拉可选范围内才用它。
  final String grade;

  final PublicQueryOption? campus;
  final PublicQueryOption? college;
  final PublicQueryOption? major;
  final PublicQueryOption? klass;

  const PublicQueryAccountDefaults({
    this.grade = '',
    this.campus,
    this.college,
    this.major,
    this.klass,
  });

  static const empty = PublicQueryAccountDefaults();

  bool get isEmpty =>
      grade.isEmpty &&
      campus == null &&
      college == null &&
      major == null &&
      klass == null;

  @override
  String toString() =>
      'PublicQueryAccountDefaults(grade=$grade, campus=${campus?.code}, '
      'college=${college?.code}, major=${major?.code}, klass=${klass?.code})';
}

/// 名称归一化：剥掉开头的 `[码]` 前缀（与 [PublicQueryOption.displayName] 同口径）、
/// 去掉**全部空白**、全角括号转半角、转小写。
///
/// 教务名称带字间空格（如「本 科 生」）与全角括号，学籍侧也可能有尾随空格。
String normalizePublicQueryName(String value) => value
    .replaceFirst(RegExp(r'^\s*\[[^\]]*\]'), '')
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll('（', '(')
    .replaceAll('）', ')')
    .toLowerCase();

/// 在候选项里按显示名找最匹配的一项：**精确 > 前缀 > 包含**，同级取更短的名字
/// （更接近原名，避免「计算机科学与技术」命中带长后缀的班/专业）。
///
/// 找不到返回 null（由调用方留空），绝不返回「差不多的那一项」。
PublicQueryOption? matchPublicQueryOption(
  List<PublicQueryOption> options,
  String wanted,
) {
  final target = normalizePublicQueryName(wanted);
  if (target.isEmpty) return null;
  PublicQueryOption? best;
  var bestRank = 0;
  var bestLength = 1 << 30;
  for (final option in options) {
    final name = normalizePublicQueryName(option.displayName);
    if (name.isEmpty) continue;
    final rank = name == target
        ? 3
        : name.startsWith(target)
        ? 2
        : name.contains(target)
        ? 1
        : 0;
    if (rank == 0) continue;
    if (rank > bestRank || (rank == bestRank && name.length < bestLength)) {
      best = option;
      bestRank = rank;
      bestLength = name.length;
    }
  }
  return best;
}

/// 年级下拉的可选范围 = `baseYear ~ baseYear-4`（与 `_gradeRow` 一致）。
///
/// 学籍入学年不在范围内（或取不到）时回退 `baseYear`（= 当前学期学年）。
String publicQueryGradeOf(String enrollYear, int baseYear) {
  final year = int.tryParse(enrollYear.trim());
  if (year != null && year <= baseYear && year >= baseYear - 4) return '$year';
  return '$baseYear';
}

/// 账号信息 + 各层选项列表 → 默认筛选（**纯函数**；发请求的部分在界面层）。
///
/// [classes] 必须是**用已匹配到的 年级/校区/学院/专业** 取回来的班级列表
/// （班级码与校区配套），否则匹配不到你的班。
PublicQueryAccountDefaults resolvePublicQueryAccountDefaults({
  required PublicQueryAccountProfile profile,
  required int baseYear,
  List<PublicQueryOption> campuses = const [],
  List<PublicQueryOption> colleges = const [],
  List<PublicQueryOption> majors = const [],
  List<PublicQueryOption> classes = const [],
}) => PublicQueryAccountDefaults(
  grade: publicQueryGradeOf(profile.enrollYear, baseYear),
  campus: matchPublicQueryOption(campuses, profile.campusName),
  college: matchPublicQueryOption(colleges, profile.college),
  major: matchPublicQueryOption(majors, profile.major),
  klass: matchPublicQueryOption(classes, profile.className),
);
