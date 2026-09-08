/// 综测计算引擎：材料 + 手动输入 → 五育分数/等次 + 综合等次 + 明细。
///
/// 逐条移植自《2026综测计算器.html》`recalc()` 与表 2 综合等次判定，
/// 数值口径见 reverse_engineering/2026综测规则.md。
library;

import 'zc_catalog.dart';
import 'zc_models.dart';
import 'zc_rules.dart';

double _c(double v, double lo, double hi) => v.clamp(lo, hi).toDouble();
double _max0(double v) => v < 0 ? 0.0 : v;

/// 单条材料的加分分项（供 UI 行内展示；无分/未选类别返回 null）。
double? zcMaterialValue(ZcMaterial m) {
  switch (m.typeId) {
    case ZcTypeId.contest:
      if (m.cat.isEmpty) return null; // 未识别/未选类别，无法计分
      final keys = zcLevelKeys;
      final k = m.level >= 0 && m.level < keys.length ? keys[m.level] : 'g';
      final arr = zcCompScores[m.cat]?[k];
      if (arr == null || m.opt < 0 || m.opt >= arr.length) return null;
      return arr[m.opt];
    case ZcTypeId.paper:
      if (m.level < 0 || m.level >= zcPaperLevels.length) return null;
      if (m.opt < 0 || m.opt >= zcPaperOrder.length) return null;
      return zcPaperLevels[m.level].$3 * zcPaperOrder[m.opt];
    case ZcTypeId.foreign:
      return m.level >= 0 && m.level < zcForeignLevels.length
          ? zcForeignLevels[m.level].$2
          : null;
    case ZcTypeId.startup:
      return m.level >= 0 && m.level < zcStartupLevels.length
          ? zcStartupLevels[m.level].$2
          : null;
    case ZcTypeId.deed:
      return m.level >= 0 && m.level < zcDeedLevels.length
          ? zcDeedLevels[m.level].$2
          : null;
    case ZcTypeId.eduCon:
      return m.level >= 0 && m.level < zcEduConLevels.length
          ? zcEduConLevels[m.level].$2
          : null;
    case ZcTypeId.eduPart:
      return _c(m.qty, 0, 999) * 0.5;
    case ZcTypeId.servicePost:
      return m.level >= 0 && m.level < zcPostLevels.length
          ? zcPostLevels[m.level].$2 * (m.opt == 0 ? 1 : 0.75)
          : null;
    case ZcTypeId.honorP:
      return m.level >= 0 && m.level < zcHonorPLevels.length
          ? zcHonorPLevels[m.level].$2
          : null;
    case ZcTypeId.honorG:
      return m.level >= 0 && m.level < zcHonorGLevels.length
          ? zcHonorGLevels[m.level].$2 * (m.opt == 0 ? 1 : 0.75)
          : null;
    case ZcTypeId.sportComp:
      final k = m.level == 1
          ? 's'
          : m.level == 2
              ? 'x'
              : 'g';
      final arr = zcSportScores[k];
      if (arr == null || m.opt < 0 || m.opt >= arr.length) return null;
      return arr[m.opt];
    case ZcTypeId.psych:
      const keys = ['g', 's', 'x', 'y'];
      final k = m.level >= 0 && m.level < keys.length ? keys[m.level] : 'g';
      final arr = zcPsychScores[k];
      if (arr == null || m.opt < 0 || m.opt >= arr.length) return null;
      return arr[m.opt];
    case ZcTypeId.sportTeam:
      const pts = [4.0, 2.0, 1.0];
      return m.level >= 0 && m.level < pts.length ? pts[m.level] : null;
    case ZcTypeId.artsComp:
      final k = m.level == 1
          ? 's'
          : m.level == 2
              ? 'x'
              : 'g';
      final arr = zcArtsScores[k];
      if (arr == null || m.opt < 0 || m.opt >= arr.length) return null;
      return arr[m.opt];
    case ZcTypeId.media:
      return m.level >= 0 && m.level < zcMediaLevels.length
          ? zcMediaLevels[m.level].$2
          : null;
    case ZcTypeId.artAct:
      if (m.level < 0 || m.level >= zcArtActLevels.length) return null;
      final a = zcArtActLevels[m.level];
      return m.opt == 0 ? a.$2 : a.$3;
    case ZcTypeId.social:
      if (m.level < 0 || m.level >= zcSocialTypes.length) return null;
      final v = zcSocialTypes[m.level].$2;
      return m.opt >= 0 && m.opt < v.length ? v[m.opt] : null;
    case ZcTypeId.laborAct:
      if (m.level < 0 || m.level >= zcLaborActLevels.length) return null;
      final a = zcLaborActLevels[m.level];
      return m.opt == 0 ? a.$2 : a.$3;
    case ZcTypeId.dorm:
      return m.level >= 0 && m.level < zcDormLevels.length
          ? zcDormLevels[m.level].$2
          : null;
  }
}

/// 志愿时长档位（表 18）：取满足的最高档；不满 10 小时 0 分。
double zcVolunteerScore(double hours) {
  var best = 0.0;
  for (final t in zcVolunteerTiers) {
    if (hours >= t.$1 - 0.001 && t.$2 > best) best = t.$2;
  }
  return best;
}

double _maxOf(Iterable<double?> xs) {
  var best = 0.0;
  for (final x in xs) {
    if (x != null && x > best) best = x;
  }
  return best;
}

double _sumOf(Iterable<double?> xs) {
  var s = 0.0;
  for (final x in xs) {
    if (x != null) s += x;
  }
  return s;
}

/// 明细行。
class ZcDetail {
  final String label;
  final double value;

  /// 来自自动源（加权/志愿）。
  final bool auto;
  const ZcDetail(this.label, this.value, {this.auto = false});
}

/// 计算结果。
class ZcCalcResult {
  final double deyu, zhiyu, tiyu, meiyu, laoyu;
  final ZcGrade gD, gZ, gT, gM, gL;
  final ZcGrade overall;
  final List<ZcDetail> details;
  final double weightUsed;
  final bool weightAuto;
  final double volunteerUsed;
  final bool volunteerAuto;

  /// 加权为空（未登录/教务不可用且未手动填）。
  final bool weightMissing;
  const ZcCalcResult({
    required this.deyu,
    required this.zhiyu,
    required this.tiyu,
    required this.meiyu,
    required this.laoyu,
    required this.gD,
    required this.gZ,
    required this.gT,
    required this.gM,
    required this.gL,
    required this.overall,
    required this.details,
    required this.weightUsed,
    required this.weightAuto,
    required this.volunteerUsed,
    required this.volunteerAuto,
    required this.weightMissing,
  });
}

/// 主计算入口。
///
/// [materials] 已按所选学年过滤；[manual] 手动项；[autoWeight]/[autoVolunteer]
/// 自动源回退（manual 对应字段为 null 时启用）。
ZcCalcResult zcCalculate(
  List<ZcMaterial> materials, {
  required ZcManual manual,
  double? autoWeight,
  double? autoVolunteer,
}) {
  final details = <ZcDetail>[];

  double slotMax(ZcTypeId id) => _maxOf([
        for (final m in materials)
          if (m.typeId == id) zcMaterialValue(m),
      ]);
  double slotSum(ZcTypeId id) => _sumOf([
        for (final m in materials)
          if (m.typeId == id) zcMaterialValue(m),
      ]);

  // ---- 智育竞赛（calcJS 口径） ----
  final comp = <double>[];
  for (final m in materials) {
    if (m.typeId != ZcTypeId.contest) continue;
    final v = zcMaterialValue(m);
    if (v != null && v > 0) comp.add(v);
  }
  var compTotal = 0.0;
  if (comp.isNotEmpty) {
    comp.sort((a, b) => b.compareTo(a));
    if (comp.first > 5) {
      compTotal = comp.first;
    } else {
      var sum = 0.0;
      for (final v in comp) {
        sum += v;
        if (sum >= 5) break;
      }
      compTotal = _c(sum, 0, 5);
    }
  }

  // ---- 智育论文（calcPaper 口径） ----
  var genSum = 0.0, paperTotal = 0.0;
  var hasBreak = false;
  for (final m in materials) {
    if (m.typeId != ZcTypeId.paper) continue;
    final v = zcMaterialValue(m);
    if (v == null) continue;
    final key = zcPaperLevels[m.level].$1;
    if (key == 'gen') {
      genSum += v;
    } else {
      paperTotal += v;
      if (key == 'intl' || key == 'auth' || key == 'csci') hasBreak = true;
    }
  }
  paperTotal += _c(genSum, 0, 1.5);
  if (!hasBreak) paperTotal = _c(paperTotal, 0, 5);

  // ---- 自动源 ----
  final volunteerHours = manual.volunteerHours ?? (autoVolunteer ?? 0);
  final volunteerAuto = manual.volunteerHours == null;
  final volScore = zcVolunteerScore(volunteerHours);
  final weight = manual.weight ?? autoWeight ?? 0;
  final weightAuto = manual.weight == null;
  final weightMissing = weight <= 0;

  final tBase = manual.tMian ? 60.0 : manual.tScore;
  final tJs = slotSum(ZcTypeId.sportComp);
  final tXl = slotSum(ZcTypeId.psych);
  final tTeam = slotMax(ZcTypeId.sportTeam);
  final mWy = slotSum(ZcTypeId.artsComp);
  var mMtYuan = 0.0, mMt = 0.0;
  for (final m in materials) {
    if (m.typeId != ZcTypeId.media) continue;
    final v = zcMaterialValue(m);
    if (v == null) continue;
    if (m.level == 4) {
      mMtYuan += v;
    } else {
      mMt += v;
    }
  }
  mMt += _c(mMtYuan, 0, 10);
  final mHd = slotSum(ZcTypeId.artAct);
  final lSh = slotSum(ZcTypeId.social);
  final lHd = slotSum(ZcTypeId.laborAct);
  final lQinshi = slotMax(ZcTypeId.dorm);

  // ---- 德育 ----
  final dPingyi = _c(manual.deyuPingyi, 0, 20);
  final dShi = slotMax(ZcTypeId.deed);
  final dSx = slotMax(ZcTypeId.eduCon) + _c(slotSum(ZcTypeId.eduPart), 0, 2);
  final dFw = slotMax(ZcTypeId.servicePost);
  final dHonor = _c(slotMax(ZcTypeId.honorP) + slotMax(ZcTypeId.honorG), 0, 10);
  final dAdd = _c(dShi + dSx + dFw + dHonor, 0, 20);
  const dCf = [0.0, 2.0, 5.0, 10.0];
  final cfIdx = manual.kouCf < 0 ? 0 : (manual.kouCf > 3 ? 3 : manual.kouCf);
  final dKou = manual.kouQk * 2 + manual.kouHd + dCf[cfIdx];
  final dScore = _max0(60 + dPingyi + dAdd - dKou);
  final gD = manual.vetoD ? ZcGrade.fail : zcGradeOf(dScore, manual.rankD);

  // ---- 智育 ----
  final zWy = slotMax(ZcTypeId.foreign);
  final zCy = slotMax(ZcTypeId.startup);
  final zAdd = _c(compTotal + paperTotal + zWy + zCy, 0, 20);
  final zKou = manual.kouZhiyu * 3.0;
  final zScore = _max0(weight + zAdd - zKou);
  var gZ = zcGradeOf(zScore, manual.rankZ);
  if (manual.tuixue) {
    gZ = ZcGrade.fail;
  } else if (manual.guaKe) {
    if (gZ == ZcGrade.ok) {
      gZ = ZcGrade.good;
    } else if (gZ == ZcGrade.good) {
      gZ = ZcGrade.pass;
    }
  }

  // ---- 体育 ----
  final tAdd = _c(tJs + tXl + tTeam, 0, 20);
  final tKou = manual.tKou1 * 5.0 + manual.tKou2 * 2.0;
  final tTotal = _max0(tBase + tAdd - tKou);
  final gT = tBase < 60 ? ZcGrade.fail : zcGradeOf(tTotal, manual.rankT);

  // ---- 美育 ----
  final mPingyi = _c(manual.meiyuPingyi, 0, 20);
  final mAdd = _c(mWy + mMt + mHd, 0, 20);
  final mKou =
      manual.mKou1 * 1.0 + manual.mKou2 * 2.0 + manual.mKou3 * 5.0;
  final mScore = _max0(60 + mPingyi + mAdd - mKou);
  final gM = zcGradeOf(mScore, manual.rankM);

  // ---- 劳育 ----
  final lPingyi = _c(manual.laoyuPingyi, 0, 20);
  final lAdd = _c(volScore + lSh + lHd + lQinshi, 0, 20);
  final lKou = manual.lKou1 * 1.0 +
      (manual.lKou2 ? 2 : 0) +
      (manual.lKou3 ? 2 : 0) +
      (manual.lKou4 ? 4 : 0);
  final lScore = _max0(60 + lPingyi + lAdd - lKou);
  final gL = zcGradeOf(lScore, manual.rankL);

  // ---- 综合等次（表 2） ----
  final tml = [gT, gM, gL];
  ZcGrade overall;
  if (gD == ZcGrade.fail || gZ == ZcGrade.fail) {
    overall = ZcGrade.fail;
  } else if (tml.where((g) => g == ZcGrade.fail).length >= 2) {
    overall = ZcGrade.fail;
  } else if (gD == ZcGrade.ok &&
      gZ == ZcGrade.ok &&
      tml.every((g) => g == ZcGrade.ok || g == ZcGrade.good)) {
    overall = ZcGrade.ok;
  } else if ((gD == ZcGrade.ok || gD == ZcGrade.good) &&
      (gZ == ZcGrade.ok || gZ == ZcGrade.good) &&
      tml.every((g) => g != ZcGrade.fail)) {
    overall = ZcGrade.good;
  } else {
    overall = ZcGrade.pass;
  }

  // ---- 明细 ----
  details.addAll([
    ZcDetail('德育 · 基础分', 60),
    ZcDetail('德育 · 民主评议', dPingyi),
    ZcDetail('德育 · 优秀事迹', dShi),
    ZcDetail('德育 · 思想教育', dSx),
    ZcDetail('德育 · 公共服务', dFw),
    ZcDetail('德育 · 荣誉称号', dHonor),
    if (dKou > 0) ZcDetail('德育 · 扣分', -dKou),
    ZcDetail('智育 · 加权成绩', weight, auto: weightAuto),
    if (weightMissing) ZcDetail('智育 · 加权缺失（需填/需登录）', 0),
    ZcDetail('智育 · 学科竞赛', compTotal),
    ZcDetail('智育 · 论文/专利', paperTotal),
    ZcDetail('智育 · 外语', zWy),
    ZcDetail('智育 · 创业', zCy),
    if (zKou > 0) ZcDetail('智育 · 扣分', -zKou),
    ZcDetail('体育 · 体测', tBase),
    ZcDetail('体育 · 竞赛/心理/集体', tJs + tXl + tTeam),
    if (tKou > 0) ZcDetail('体育 · 扣分', -tKou),
    ZcDetail('美育 · 基础分', 60),
    ZcDetail('美育 · 民主评议', mPingyi),
    ZcDetail('美育 · 文艺竞赛/媒体/活动', mWy + mMt + mHd),
    if (mKou > 0) ZcDetail('美育 · 扣分', -mKou),
    ZcDetail('劳育 · 基础分', 60),
    ZcDetail('劳育 · 民主评议', lPingyi),
    ZcDetail('劳育 · 志愿服务', volScore, auto: volunteerAuto),
    ZcDetail('劳育 · 实践/活动/寝室', lSh + lHd + lQinshi),
    if (lKou > 0) ZcDetail('劳育 · 扣分', -lKou),
  ]);

  return ZcCalcResult(
    deyu: dScore,
    zhiyu: zScore,
    tiyu: tTotal,
    meiyu: mScore,
    laoyu: lScore,
    gD: gD,
    gZ: gZ,
    gT: gT,
    gM: gM,
    gL: gL,
    overall: overall,
    details: details,
    weightUsed: weight,
    weightAuto: weightAuto,
    volunteerUsed: volunteerHours,
    volunteerAuto: volunteerAuto,
    weightMissing: weightMissing,
  );
}

/// 材料按测评学年窗口过滤。
List<ZcMaterial> zcFilterByYear(List<ZcMaterial> all, int yearEnd) => [
  for (final m in all)
    if (m.date != null && zcYearWindowContains(m.date!, yearEnd)) m,
];
