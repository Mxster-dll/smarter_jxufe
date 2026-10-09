/// 「填表助手」的数据快照 + **标签 → 自动值**的唯一口径。
///
/// 用户 2026-10-07：「自动识别有哪些项需要填，然后把能填的都填了。填不了/不确定的，
/// 空着。然后用户可以在自动填完后，再手动调整各部分文本」——
/// 本文件就是那个「能填的都填了」：一个纯函数 [fillValueFor]，
/// 输入 docx 里扫出来的一个待填项 + 一份 [FillFormData]，输出该填什么（null = 留空）。
///
/// 口径（改动前先读）：
/// - **只写真实数据**。取不到就返回 null（那一格留空），绝不编造；
/// - 综测分项**全部走引擎**（`zcCalculate` 的 details 与前缀求和），
///   界面层不许自己写 `(德+智+体+美+劳)/5` 那一套（见 `zc_engine.dart` 的口径）；
/// - 成段文字（主要表现 / 突出事迹 / 受表彰情况…）由数据**成文**，
///   可带一句克制的评价（用户 2026-10-07 拍板「允许适度评价性表述」），
///   但评价句也按数据挑（没有荣誉就不写「表现突出」）；
/// - 表格里写了「限 N 字」的字段按 N 字截断（学校原话：多出字数按前后顺序直接删除）。
library;

import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

export 'fill_form_zc.dart';
export 'fill_form_prose.dart';
export 'fill_form_values.dart';


/// 自动填表要用到的全部数据（**离线可得**：学籍缓存 + 成绩缓存 + 综测本地库）。
class FillFormData {
  // ---- 学籍 ----
  final String name;
  final String studentId;
  final String gender;
  final String birthDate;
  final String politicalStatus;
  final String ethnicity;
  final String college;
  final String major;
  final String className;
  final String enrollYear;
  final String studyYears;
  final String trainLevel;
  final String advisor;
  final String phone;
  final String email;
  final String address;
  final String hometown;
  final String familyContact;
  final String familyContactPhone;

  /// 测评学年**结束**年（2026 = 2025-2026 学年）。
  final int yearEnd;

  // ---- 成绩（该学年）----
  final double? weighted;
  final double? minScore;
  final double? credits;
  final bool hasFail;

  // ---- 综测 ----
  final ZcManual manual;
  final double? volunteerHours;
  final ZcCalcResult? zc;

  /// 全部材料（不分学年）——「大学期间受表彰情况」用它。
  final List<ZcMaterial> allMaterials;

  /// 落在本学年的材料（附加分审核表用它）。
  final List<ZcMaterial> materials;

  /// 「填表当天」（**注入**而不是读时钟：纯函数才好单测，口径同
  /// `buildAiSnapshot(ref, {required DateTime now})`）。null = 填表时间留空。
  final DateTime? now;

  const FillFormData({
    this.name = '',
    this.studentId = '',
    this.gender = '',
    this.birthDate = '',
    this.politicalStatus = '',
    this.ethnicity = '',
    this.college = '',
    this.major = '',
    this.className = '',
    this.enrollYear = '',
    this.studyYears = '',
    this.trainLevel = '',
    this.advisor = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.hometown = '',
    this.familyContact = '',
    this.familyContactPhone = '',
    required this.yearEnd,
    this.weighted,
    this.minScore,
    this.credits,
    this.hasFail = false,
    this.manual = const ZcManual(),
    this.volunteerHours,
    this.zc,
    this.allMaterials = const [],
    this.materials = const [],
    this.now,
  });

  /// 「2025-2026 学年」。
  String get yearLabel => '${yearEnd - 1}-$yearEnd 学年';

  /// 「2025-2026 年度」。
  String get yearLabelShort => '${yearEnd - 1}-$yearEnd';

  /// 从学籍构造（其余字段由 provider 补齐）。
  factory FillFormData.ofStudent(
    StudentInfo? info, {
    required int yearEnd,
  }) {
    if (info == null) return FillFormData(yearEnd: yearEnd);
    return FillFormData(
      name: info.name,
      studentId: info.studentId,
      gender: info.gender,
      birthDate: info.birthDate,
      politicalStatus: info.politicalStatus,
      ethnicity: info.ethnicity,
      college: info.college,
      major: info.major,
      className: info.className,
      enrollYear: info.enrollYear,
      studyYears: info.studyYears,
      trainLevel: info.trainLevel,
      advisor: info.advisor,
      phone: info.phone,
      email: info.email,
      address: info.address,
      hometown: info.hometown,
      familyContact: info.familyContact,
      familyContactPhone: info.familyContactPhone,
      yearEnd: yearEnd,
    );
  }

  FillFormData copyWith({
    double? weighted,
    double? minScore,
    double? credits,
    bool? hasFail,
    ZcManual? manual,
    double? volunteerHours,
    ZcCalcResult? zc,
    List<ZcMaterial>? allMaterials,
    List<ZcMaterial>? materials,
    DateTime? now,
  }) =>
      FillFormData(
        name: name,
        studentId: studentId,
        gender: gender,
        birthDate: birthDate,
        politicalStatus: politicalStatus,
        ethnicity: ethnicity,
        college: college,
        major: major,
        className: className,
        enrollYear: enrollYear,
        studyYears: studyYears,
        trainLevel: trainLevel,
        advisor: advisor,
        phone: phone,
        email: email,
        address: address,
        hometown: hometown,
        familyContact: familyContact,
        familyContactPhone: familyContactPhone,
        yearEnd: yearEnd,
        weighted: weighted ?? this.weighted,
        minScore: minScore ?? this.minScore,
        credits: credits ?? this.credits,
        hasFail: hasFail ?? this.hasFail,
        manual: manual ?? this.manual,
        volunteerHours: volunteerHours ?? this.volunteerHours,
        zc: zc ?? this.zc,
        allMaterials: allMaterials ?? this.allMaterials,
        materials: materials ?? this.materials,
        now: now ?? this.now,
      );
}

// ---------------------------------------------------------------------------
// 数字 / 日期
// ---------------------------------------------------------------------------

/// 数值文案：整数不带小数点，小数最多 2 位（末尾 0 去掉）。
String? ffNum(double? v) {
  if (v == null) return null;
  final r = zcRound2(v);
  if (r == r.roundToDouble()) return r.round().toString();
  var s = r.toStringAsFixed(2);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

String ffToday(FillFormData d) {
  final now = d.now;
  if (now == null) return '';
  return '${now.year}年${now.month}月${now.day}日';
}

// ---------------------------------------------------------------------------
// 综测分项（口径 = zc_engine 的 details 行前缀求和）
// ---------------------------------------------------------------------------

const Map<String, String> ffDimNames = {
  'd': '德育',
  'z': '智育',
  't': '体育',
  'm': '美育',
  'l': '劳育',
};
