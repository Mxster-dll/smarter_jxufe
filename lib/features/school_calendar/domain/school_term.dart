/// 「当下学期」判定（课表 / 校历 / 实况窗 / 作息表共用口径）。
///
/// ## 为什么单独成域函数
/// 原先各页各自按月份猜学期（`3~8 月 → 第二学期，其余 → 第一学期`），
/// 有两个硬伤：
/// 1. **跨年错位**：`2027-01-10` 仍在本学年第一学期（261 学期
///    `2026-09-07 ~ 2027-01-16`），按月份却会跳到 2027-2028 第一学期；
/// 2. **假期语义**：暑假/寒假期间该显示的是**即将开学的下一学期**，
///    而不是刚刚结束的那一学期。
///
/// 故这里以校历学期**日期区间**为准（离线快照 [wxcalOfflineTerms] 覆盖
/// 2017 秋 ~ 2026 秋），日期落在快照覆盖范围之外时才退回月份经验规则。
///
/// ## 用户口径（2026-09 裁定）
/// - 学期进行中 → 该学期；开学前（已进学期区间、未到第 1 教学周）仍算该学期，
///   由界面决定「整学期视图」；
/// - 假期（两学期之间的空档）→ **下一学期**（假期里看的是即将开学的课表，
///   没出来则提示「课表还没出来」）。
library;

import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// 由 [now] 推「此刻应展示的学段」。
///
/// 返回 `(xn: 学年起始年, xq: 0 第一学期 / 1 第二学期)`，与教务 `xn/xq`
/// 参数口径一致（见 `ScheduleRemoteDataSource`、`schoolCalendarProvider`）。
///
/// [terms] 传校历学期列表（通常是 `wxcalOfflineToDomain()` 或实时校历）；
/// 为空时直接用月份经验规则。
({int xn, int xq}) currentSchoolTerm(
  DateTime now, {
  List<WxSemesterArrangement> terms = const [],
}) =>
    _termFromCalendar(now, terms) ?? _termFromMonths(now);

/// 校历区间判定：命中区间 → 该学期；落在两学期空档（假期）→ 下一学期。
///
/// [now] 落在快照覆盖范围（最早学期 start ~ 最晚学期 end）之外时返回 null，
/// 交给 [_termFromMonths] —— 免得离线快照过旧时永远停在最后一个学期。
({int xn, int xq})? _termFromCalendar(
  DateTime now,
  List<WxSemesterArrangement> terms,
) {
  if (terms.isEmpty) return null;

  final day = DateTime(now.year, now.month, now.day);
  final sorted = [...terms]..sort((a, b) => a.start.compareTo(b.start));
  if (day.isBefore(sorted.first.start) || day.isAfter(sorted.last.end)) {
    return null;
  }

  // ① 进行中：区间命中（多个命中取 start 更晚的，更贴近当下）
  WxSemesterArrangement? hit;
  for (final t in sorted) {
    if (!t.start.isAfter(day) && !t.end.isBefore(day)) {
      if (hit == null || t.start.isAfter(hit.start)) hit = t;
    }
  }
  if (hit != null) return (xn: hit.xn, xq: hit.xq);

  // ② 假期：区间空档 → 快照中 start 最早的「未来学期」
  for (final t in sorted) {
    if (t.start.isAfter(day)) return (xn: t.xn, xq: t.xq);
  }
  return null;
}

/// 月份经验规则（无校历 / 快照覆盖范围之外时的兜底）。
///
/// - 9~12 月：第一学期（当年入学年）
/// - 1 月：上半月仍属第一学期（期末考至 1 月中旬），下半月进入寒假 → 第二学期
/// - 2~6 月：寒假与第二学期
/// - 7~8 月：暑假 → 下一学年第一学期
///
/// 注意：7 月上旬个别年份第二学期尚未结束（如 2020-07-31、2022-07-09），
/// 此处一律按暑假给出下一学年第一学期 —— 仅影响离线快照覆盖范围之外的日期，
/// 校内数据由 [_termFromCalendar] 精确判定。
({int xn, int xq}) _termFromMonths(DateTime now) {
  final y = now.year;
  switch (now.month) {
    case 1:
      return now.day <= 14 ? (xn: y - 1, xq: 0) : (xn: y - 1, xq: 1);
    case 2:
    case 3:
    case 4:
    case 5:
    case 6:
      return (xn: y - 1, xq: 1);
    case 7:
    case 8:
      return (xn: y, xq: 0);
    default:
      return (xn: y, xq: 0);
  }
}

/// 学期展示文本，如 `2026-2027 学年第一学期`。
String schoolTermLabel(int xn, int xq) =>
    '$xn-${xn + 1} 学年${xq == 0 ? '第一学期' : '第二学期'}';
