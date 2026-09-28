/// 综测计算引擎：材料 + 手动输入 → 五育分数/等次 + 综合等次 + 明细。
///
/// 逐条移植自《2026综测计算器.html》`recalc()` 与表 2 综合等次判定，
/// 数值口径见 reverse_engineering/2026综测规则.md。
library;

import 'zc_catalog.dart';
import 'zc_foreign.dart';
import 'zc_models.dart';
import 'zc_rules.dart';
import 'zc_weights.dart';

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
      // 用户 2026-09-17 二轮：外语按证书名目**查表 10 档位**计分（`manualScore` 存的是
      // 原始成绩，如四级 489 → 1 分；等级类证书直接取固定分）；
      // 旧材料（只有档位下标、没有原始成绩）仍按 [zcForeignLevels] 计。
      final award = zcForeignAward(name: m.name, rawScore: m.manualScore);
      if (award != null) return _max0(award);
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

  /// 总评成绩 = Σ 五育分数 × 占比（五育占比见 [weights]）。
  ///
  /// 用户 2026-09-18：「综测不是直接算平均分，而是有一个总评成绩，这个成绩的
  /// 占比由班主任定，应该让用户自行设置」→ 这里就是**唯一**的总评实现，
  /// 界面层不许再自己写 `(德+智+体+美+劳)/5`（那只是 [average] 五育平均）。
  final double total;

  /// 本学年生效的五育占比（来自 `ZcManual.weights`）。
  final ZcWeights weights;

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
    required this.total,
    required this.weights,
  });

  /// 五育平均（仅供对照/展示，**不是**总评成绩）。
  double get average => (deyu + zhiyu + tiyu + meiyu + laoyu) / 5;
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

  // ---- 「放开所有累加」开关（用户 2026-09-27） ----
  // 口径 = 学校《评优评先综测计算器》与标准版在**累加**上的差别：所有「就高
  // 一次」改多项叠加、所有附加分封顶取消。**民主评议（20）、扣分项、等次评定、
  // 一票否决一律照旧** —— 那份参考文件里 `dPing`/`mPing`/`lPing` 仍
  // `Math.min(…,20)`，扣分也都还在 `− dKou` 里。
  final open = manual.openAccumulate;
  /// 分槽分：标准档「就高一次」（`slotMax`），放开档改累加（`slotSum`）。
  double slotBest(ZcTypeId id) => open ? slotSum(id) : slotMax(id);
  /// 附加分封顶：**只在标准档生效**，放开档原值放行。
  double capped(double value, double max) => open ? value : _c(value, 0, max);

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
    if (open) {
      // 放开累加：Ⅰ~Ⅳ 类完全平等，所有获奖一律相加、无 5 分封顶（对应参考版
      // `calcJS` 的 `for (const it of arr) { total += it.v; }`）。
      for (final v in comp) {
        compTotal += v;
      }
    } else if (comp.first > 5) {
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
  // 放开累加：国内一般刊物不再限 1.5 分、合计不再封顶 5 分（对应参考版只
  // `total += genSum`）。
  paperTotal += open ? genSum : _c(genSum, 0, 1.5);
  if (!open && !hasBreak) paperTotal = _c(paperTotal, 0, 5);

  // ---- 自动源 ----
  final volunteerHours = manual.volunteerHours ?? (autoVolunteer ?? 0);
  final volunteerAuto = manual.volunteerHours == null;
  final volScore = zcVolunteerScore(volunteerHours);
  // 智育总分用**舍入后的加权**计算（用户 2026-09-18：「智育总分是用舍入后的
  // 加权计算的」）：界面一律显示 2 位小数，若拿原始 double 计分，显示的加权
  // 与算出来的智育会对不上（91.8596… 显示 91.86，却按 91.8596 算）。
  final weight = zcRound2(manual.weight ?? autoWeight ?? 0);
  final weightAuto = manual.weight == null;
  final weightMissing = weight <= 0;

  final tBase = manual.tMian ? 60.0 : manual.tScore;
  final tJs = slotSum(ZcTypeId.sportComp);
  final tXl = slotSum(ZcTypeId.psych);
  final tTeam = slotBest(ZcTypeId.sportTeam);
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
  mMt += capped(mMtYuan, 10);
  final mHd = slotSum(ZcTypeId.artAct);
  final lSh = slotSum(ZcTypeId.social);
  final lHd = slotSum(ZcTypeId.laborAct);
  final lQinshi = slotBest(ZcTypeId.dorm);

  // ---- 德育 ----
  // 民主评议**两档都封顶 20**（参考版 `Math.min(Math.max(…), 20)` 照旧）。
  final dPingyi = _c(manual.deyuPingyi, 0, 20);
  final dShi = slotBest(ZcTypeId.deed);
  // 思想教育分两槽：**贡献度**（骨干，职责取最高）+ **参与度**（活动次数累加，
  // 封顶 2 分）。用户 2026-09-27：「思想教育应该分为思想教育·贡献度和
  // 思想教育·参与度」→ 明细拆成两行，界面各挂一个板块（值只从引擎取，界面不重算）。
  final dSxCon = slotBest(ZcTypeId.eduCon);
  final dSxPart = capped(slotSum(ZcTypeId.eduPart), 2);
  final dSx = dSxCon + dSxPart;
  final dFw = slotBest(ZcTypeId.servicePost);
  // 荣誉称号同样拆：**个人**（表 6）+ **集体**（表 7）。「两槽合计封顶 10 分」
  // 只体现在父级 [dHonor]（进而进 [dAdd] 的 20 分封顶）—— 两个板块各显示自己
  // 那一槽的分值，与智育四小项同口径（板块显示分槽值、父级合计才封顶）。
  final dHonorP = slotBest(ZcTypeId.honorP);
  final dHonorG = slotBest(ZcTypeId.honorG);
  final dHonor = capped(dHonorP + dHonorG, 10);
  final dAdd = capped(dShi + dSx + dFw + dHonor, 20);
  const dCf = [0.0, 2.0, 5.0, 10.0];
  final cfIdx = manual.kouCf < 0 ? 0 : (manual.kouCf > 3 ? 3 : manual.kouCf);
  final dKou = manual.kouQk * 2 + manual.kouHd + dCf[cfIdx];
  final dScore = _max0(60 + dPingyi + dAdd - dKou);
  final gD = manual.vetoD ? ZcGrade.fail : zcGradeOf(dScore, manual.rankD);

  // ---- 智育 ----
  final zWy = slotBest(ZcTypeId.foreign);
  final zCy = slotBest(ZcTypeId.startup);
  final zAdd = capped(compTotal + paperTotal + zWy + zCy, 20);
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
  final tAdd = capped(tJs + tXl + tTeam, 20);
  final tKou = manual.tKou1 * 5.0 + manual.tKou2 * 2.0;
  final tTotal = _max0(tBase + tAdd - tKou);
  final gT = tBase < 60 ? ZcGrade.fail : zcGradeOf(tTotal, manual.rankT);

  // ---- 美育 ----
  // 民主评议两档都封顶 20（同上）。
  final mPingyi = _c(manual.meiyuPingyi, 0, 20);
  final mAdd = capped(mWy + mMt + mHd, 20);
  final mKou =
      manual.mKou1 * 1.0 + manual.mKou2 * 2.0 + manual.mKou3 * 5.0;
  final mScore = _max0(60 + mPingyi + mAdd - mKou);
  final gM = zcGradeOf(mScore, manual.rankM);

  // ---- 劳育 ----
  // 民主评议两档都封顶 20（同上）。
  final lPingyi = _c(manual.laoyuPingyi, 0, 20);
  final lAdd = capped(volScore + lSh + lHd + lQinshi, 20);
  final lKou = manual.lKou1 * 1.0 +
      (manual.lKou2 ? 2 : 0) +
      (manual.lKou3 ? 2 : 0) +
      (manual.lKou4 ? 4 : 0);
  final lScore = _max0(60 + lPingyi + lAdd - lKou);
  final gL = zcGradeOf(lScore, manual.rankL);

  // ---- 总评成绩（五育加权；占比按学年可设） ----
  final weights = manual.weights;
  final total = zcRound2(
    weights.applyTo(
      deyu: dScore,
      zhiyu: zScore,
      tiyu: tTotal,
      meiyu: mScore,
      laoyu: lScore,
    ),
  );

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
    // ⚠ 思想教育与荣誉称号**各拆两行**（用户 2026-09-27）—— 界面按这 6 行挂
    // 6 个板块；每行是**分槽值**，父级封顶（思想教育参与度 2 / 荣誉称号合计 10 /
    // 附加合计 20）不进这两行，所以「6 行之和」可能大于实际计入的附加分。
    ZcDetail('德育 · 思想教育贡献度', dSxCon),
    ZcDetail('德育 · 思想教育参与度', dSxPart),
    ZcDetail('德育 · 公共服务', dFw),
    ZcDetail('德育 · 荣誉称号（个人）', dHonorP),
    ZcDetail('德育 · 荣誉称号（集体）', dHonorG),
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
    total: total,
    weights: weights,
  );
}

/// 材料按测评学年窗口过滤。
List<ZcMaterial> zcFilterByYear(List<ZcMaterial> all, int yearEnd) => [
  for (final m in all)
    if (m.date != null && zcYearWindowContains(m.date!, yearEnd)) m,
];

/// 四舍五入到 2 位小数（综测页显示的加权成绩精度；智育总分按它计算）。
double zcRound2(double v) => (v * 100).roundToDouble() / 100;

/// 学科竞赛里**最终计入总分**的材料 id 集合（= 引擎 calcJS 口径的同一套规则：
/// 最高项 > 5 分时只计最高那一项；否则按分值从高到低累加，累加到 ≥ 5 分为止，
/// 总分封顶 5 分）。用户 2026-09-18：「综测智育竞赛加分要把最终贡献分数的项
/// 高亮一下」——界面用本函数决定高亮哪几条材料，别再自己写一套判断。
///
/// [open] = 综测页的「放开所有累加」开关（`ZcManual.openAccumulate`）：放开档
/// 所有获奖一律相加、无封顶 → **每一条有分的竞赛都被计入**。
Set<String> zcContestContributingIds(
  List<ZcMaterial> materials, {
  bool open = false,
}) {
  final entries = <({String id, double value})>[];
  for (final m in materials) {
    if (m.typeId != ZcTypeId.contest) continue;
    final v = zcMaterialValue(m);
    if (v != null && v > 0) entries.add((id: m.id, value: v));
  }
  if (entries.isEmpty) return const <String>{};
  if (open) return {for (final e in entries) e.id};
  entries.sort((a, b) => b.value.compareTo(a.value));
  if (entries.first.value > 5) return {entries.first.id};
  final out = <String>{};
  var sum = 0.0;
  for (final e in entries) {
    out.add(e.id);
    sum += e.value;
    if (sum >= 5) break;
  }
  return out;
}

/// 德育附加分涉及的六个材料类型（表 3~7；[zcMoralContributingIds] 只认这几个，
/// 传进来的其它类型材料一律忽略）。
const List<ZcTypeId> _zcMoralTypeIds = [
  ZcTypeId.deed, // 表 3 优秀事迹
  ZcTypeId.eduCon, // 表 4 思想教育 · 贡献度
  ZcTypeId.eduPart, // 表 4 思想教育 · 参与度
  ZcTypeId.servicePost, // 表 5 公共服务
  ZcTypeId.honorP, // 表 6 荣誉称号 · 个人
  ZcTypeId.honorG, // 表 7 荣誉称号 · 集体
];

/// 德育附加分里**最终被采用**的材料 id 集合（= 引擎 `dShi/dSx/dFw/dHonor`
/// 的同一套规则）。用户 2026-09-27：「德育加分部分，也要像竞赛附加分一样，
/// 只高亮计入的那一项」—— 界面用本函数决定高亮哪几条，别再自己写一套判断。
///
/// 逐板块口径（与 [zcCalculate] 逐字对应，六个板块与界面 `d-3-1 ~ d-3-4b`
/// 的规则点、材料类型一一对齐）：
/// - **优秀事迹**（表 3）：`slotMax(deed)` → 只采用最高一条；
/// - **思想教育 · 贡献度**（表 4）：骨干培训 `slotMax(eduCon)` → 只采用最高一条；
/// - **思想教育 · 参与度**（表 4）：活动参与 `slotSum(eduPart)` 累加（引擎再封顶
///   2 分）→ 按分值从高到低累加到 ≥ 2 分为止的那几条；
/// - **公共服务**（表 5）：`slotMax(servicePost)` → 只采用最高一条；
/// - **荣誉称号 · 个人**（表 6）：`slotMax(honorP)` → 只采用最高一条；
/// - **荣誉称号 · 集体**（表 7）：`slotMax(honorG)` → 只采用最高一条
///   （引擎把个人+集体**合计**封顶 10 分 —— 那是两槽合计的上限，
///   不改变「采用了哪两条」，故两条都算采用）。
///
/// ⚠ 附加合计封顶 20 分（引擎的 `dAdd`）同样是**在上述结果之上的一次性截断**，
/// 不改变「采用了哪几条」—— 故本函数刻意不模拟它（否则得凭空规定截断顺序）。
///
/// 同分并列时取**材料列表里靠前的那一条**（严格大于才替换，见 `_takeMax`），
/// 与 [zcContestContributingIds] 的 `sort` 口径相比更确定（`List.sort`
/// 不保证稳定）。分值 ≤ 0 / 未填分的材料一律不算采用。
///
/// [open] = 综测页的「放开所有累加」开关（`ZcManual.openAccumulate`）：放开档
/// 六个板块全部改累加、封顶全取消 → **每一条有分的德育材料都被采用**。
Set<String> zcMoralContributingIds(
  List<ZcMaterial> materials, {
  bool open = false,
}) {
  final byType = <ZcTypeId, List<({String id, double value})>>{};
  for (final m in materials) {
    final v = zcMaterialValue(m);
    if (v == null || v <= 0) continue;
    final list = byType.putIfAbsent(
      m.typeId,
      () => <({String id, double value})>[],
    );
    list.add((id: m.id, value: v));
  }
  if (open) {
    final all = <String>{};
    for (final t in _zcMoralTypeIds) {
      for (final e in byType[t] ?? const <({String id, double value})>[]) {
        all.add(e.id);
      }
    }
    return all;
  }
  final out = <String>{};
  // 只取最高一条（并列取靠前的）。
  void takeMax(ZcTypeId id) {
    final list = byType[id];
    if (list == null || list.isEmpty) return;
    var best = list.first;
    for (final e in list) {
      if (e.value > best.value) best = e;
    }
    out.add(best.id);
  }

  // 按分值从高到低累加，累加到 ≥ cap 为止（并列按原顺序）。
  void takeUntil(ZcTypeId id, double cap) {
    final list = [...?byType[id]]
      ..sort((a, b) => b.value.compareTo(a.value));
    var sum = 0.0;
    for (final e in list) {
      out.add(e.id);
      sum += e.value;
      if (sum >= cap) break;
    }
  }

  takeMax(ZcTypeId.deed); // 表 3 优秀事迹
  takeMax(ZcTypeId.eduCon); // 表 4 思想教育贡献度
  takeUntil(ZcTypeId.eduPart, 2); // 表 4 思想教育参与度（≤2 分）
  takeMax(ZcTypeId.servicePost); // 表 5 公共服务
  takeMax(ZcTypeId.honorP); // 表 6 荣誉称号·个人
  takeMax(ZcTypeId.honorG); // 表 7 荣誉称号·集体
  return out;
}
