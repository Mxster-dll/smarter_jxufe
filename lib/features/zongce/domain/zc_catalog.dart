/// 综测材料类型目录：录入控件规格 + 计入口 + 聚合语义。
///
/// 「材料」= 一条可证明的加分事实（竞赛获奖/论文/荣誉等），录入结构化字段
/// （类型/名称/级别/奖项/日期/单位/附件）。聚合语义分四种：
/// - [ZcAgg.max]：多项只计最高（外语/创业/事迹/职务/寝室等，HTML 单选口径）；
/// - [ZcAgg.sum]：多项累加（体育/文艺/实践/媒体/活动等）；
/// - [ZcAgg.contest]：全部竞赛获奖走 calcJS 口径（最高项 >5 只计最高项，否则累加封顶 5）；
/// - [ZcAgg.paper]：论文/专利走 calcPaper 口径（一般类累计 ≤1.5，无权威破格时合计 ≤5）。
library;

import 'zc_rules.dart';

/// 材料类型 id。
enum ZcTypeId {
  contest,
  paper,
  foreign,
  startup,
  honorP,
  honorG,
  deed,
  eduCon,
  eduPart,
  servicePost,
  sportComp,
  psych,
  sportTeam,
  artsComp,
  media,
  artAct,
  social,
  laborAct,
  dorm,
}

enum ZcAgg { max, sum, contest, paper }

/// 某材料类型：录入表单 + 计入口 + 聚合语义描述。
class ZcTypeSpec {
  final ZcTypeId id;

  /// 类型名。
  final String label;

  /// 计入口说明（分组标题/结果明细归属）。
  final String section;

  /// 计入哪一育：d 德育 / z 智育 / t 体育 / m 美育 / l 劳育。
  final String dim;

  /// 聚合槽（荣誉称号个人/集体合并为 honor，上限 10）。
  final String slot;

  final ZcAgg agg;

  final bool needName;
  final bool needDate;
  final bool needOrg;

  /// 竞赛类别（自动识别 + 手动 c1~c4）。
  final bool needCat;

  /// 次数输入标签（思想教育参与度：0.5 分/次，上限 2）。
  final String? qtyLabel;

  /// 下拉一选项 label（级别/档位/类型；带分值文案）。
  final List<String> levels;

  /// 下拉二选项 label（奖次/作者序/考核/角色；可为空）。
  final List<String> opts;

  /// 规则提示。
  final String hint;

  const ZcTypeSpec({
    required this.id,
    required this.label,
    required this.section,
    required this.dim,
    required this.slot,
    required this.agg,
    this.needName = false,
    this.needDate = true,
    this.needOrg = false,
    this.needCat = false,
    this.qtyLabel,
    this.levels = const [],
    this.opts = const [],
    this.hint = '',
  });
}

String _fmtD(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

/// 类型注册表（顺序即「新增材料」选择顺序）。
final List<ZcTypeSpec> zcTypeSpecs = [
  // ---------- 智育 ----------
  ZcTypeSpec(
    id: ZcTypeId.contest,
    label: '学科竞赛获奖',
    section: '智育 · 学科技能竞赛（表 8）',
    dim: 'z',
    slot: 'contest',
    agg: ZcAgg.contest,
    needName: true,
    needOrg: true,
    needCat: true,
    levels: ['国家级', '省级', '校级'],
    opts: zcPrizeNames,
    hint: 'Ⅰ~Ⅳ 类统一口径：所有获奖最高项 >5 分只计最高项，否则可累加多项但封顶 5 分。比赛名称可自动识别类别，未收录时手动选 Ⅰ~Ⅳ 类。',
  ),
  ZcTypeSpec(
    id: ZcTypeId.paper,
    label: '论文 / 专利',
    section: '智育 · 学术能力（表 9）',
    dim: 'z',
    slot: 'paper',
    agg: ZcAgg.paper,
    needName: true,
    needOrg: true,
    levels: [for (final p in zcPaperLevels) '${p.$2}（系数 ${_fmtD(p.$3)}）'],
    opts: [
      '第 1 作者（×1）',
      '第 2 作者（×0.6）',
      '第 3 作者（×0.4）',
      '第 4 作者（×0.2）',
      '第 5 作者及以后（×0.1）',
    ],
    hint: '分值 = 等级系数 × 作者贡献系数。国内一般累计不超过 1.5 分；有国际/国内权威（或国际会议）成果可突破 5 分上限。',
  ),
  ZcTypeSpec(
    id: ZcTypeId.foreign,
    label: '外语水平',
    section: '智育 · 外语能力（表 10）',
    dim: 'z',
    slot: 'foreign',
    agg: ZcAgg.max,
    needName: true,
    levels: [for (final f in zcForeignLevels) '${f.$1}（${_fmtD(f.$2)} 分）'],
    hint: '外语加分单项取最高一次计分。',
  ),
  ZcTypeSpec(
    id: ZcTypeId.startup,
    label: '自主创业',
    section: '智育 · 创新创业（表 11）',
    dim: 'z',
    slot: 'startup',
    agg: ZcAgg.max,
    needName: true,
    levels: [for (final s in zcStartupLevels) '${s.$1}（${_fmtD(s.$2)} 分）'],
    hint: '认定依据：校内企业以企业登记证书及入驻众创空间时间为准；校外以登记证书及银行流水为准。',
  ),
  // ---------- 德育 ----------
  ZcTypeSpec(
    id: ZcTypeId.deed,
    label: '优秀事迹',
    section: '德育 · 优秀事迹（表 3）',
    dim: 'd',
    slot: 'deed',
    agg: ZcAgg.max,
    needName: true,
    levels: [for (final d in zcDeedLevels) '${d.$1}（${_fmtD(d.$2)} 分）'],
    hint: '单选就高一次。',
  ),
  ZcTypeSpec(
    id: ZcTypeId.eduCon,
    label: '思想教育 · 骨干培训',
    section: '德育 · 思想教育贡献度（表 4）',
    dim: 'd',
    slot: 'eduCon',
    agg: ZcAgg.max,
    needName: true,
    levels: [for (final e in zcEduConLevels) '${e.$1}（${_fmtD(e.$2)} 分）'],
    hint: '贡献度按最高一次计。',
  ),
  ZcTypeSpec(
    id: ZcTypeId.eduPart,
    label: '思想教育 · 活动参与',
    section: '德育 · 思想教育参与度（表 4）',
    dim: 'd',
    slot: 'eduPart',
    agg: ZcAgg.sum,
    needName: true,
    qtyLabel: '参与次数（0.5 分/次，上限 2 分）',
    hint: '参与思想教育类征文、演讲及出勤完整的教育活动，0.5 分/次，参与度合计上限 2 分。',
  ),
  ZcTypeSpec(
    id: ZcTypeId.servicePost,
    label: '公共服务职务',
    section: '德育 · 公共服务（表 5）',
    dim: 'd',
    slot: 'post',
    agg: ZcAgg.max,
    needName: false,
    needOrg: true,
    levels: [for (final p in zcPostLevels) '${p.$1}（${_fmtD(p.$2)} 分）'],
    opts: ['考核优秀（×1）', '考核合格（×0.75）'],
    hint: '单选就高、不可叠加；优秀比例不超过 30%，考核不合格不加分。',
  ),
  ZcTypeSpec(
    id: ZcTypeId.honorP,
    label: '荣誉称号 · 个人',
    section: '德育 · 荣誉称号（表 6）',
    dim: 'd',
    slot: 'honor',
    agg: ZcAgg.max,
    needName: true,
    needOrg: true,
    levels: [for (final h in zcHonorPLevels) '${h.$1}（${_fmtD(h.$2)} 分）'],
    hint: '个人荣誉选最高一次。',
  ),
  ZcTypeSpec(
    id: ZcTypeId.honorG,
    label: '荣誉称号 · 集体',
    section: '德育 · 荣誉称号（表 7）',
    dim: 'd',
    slot: 'honor',
    agg: ZcAgg.max,
    needName: true,
    needOrg: true,
    levels: [for (final h in zcHonorGLevels) '${h.$1}（${_fmtD(h.$2)} 分）'],
    opts: ['主要负责人（×1）', '其他负责人（×0.75）'],
    hint: '集体荣誉选最高一次。',
  ),
  // ---------- 体育 ----------
  ZcTypeSpec(
    id: ZcTypeId.sportComp,
    label: '体育竞赛名次',
    section: '体育 · 体育竞赛（表 12）',
    dim: 't',
    slot: 'sport',
    agg: ZcAgg.sum,
    needName: true,
    levels: ['国家级', '省级', '校级'],
    opts: zcSportPlaceNames,
  ),
  ZcTypeSpec(
    id: ZcTypeId.psych,
    label: '心理健康活动',
    section: '体育 · 心理健康活动（表 13）',
    dim: 't',
    slot: 'psych',
    agg: ZcAgg.sum,
    needName: true,
    levels: ['国家级', '省级', '校级', '院级'],
    opts: ['一等奖', '二等奖', '三等奖', '优胜奖'],
  ),
  ZcTypeSpec(
    id: ZcTypeId.sportTeam,
    label: '运动队 / 集体活动',
    section: '体育 · 集体活动（表 14）',
    dim: 't',
    slot: 'team',
    agg: ZcAgg.max,
    needName: true,
    needOrg: true,
    levels: [
      '校运动队（名单在列、每场必到）4 分',
      '院运动队（同上）2 分',
      '班级体育活动突出学生（≤10%，班主任+测评小组认定）1 分',
    ],
    hint: '运动队两次以上（含）不到者取消该项加分。',
  ),
  // ---------- 美育 ----------
  ZcTypeSpec(
    id: ZcTypeId.artsComp,
    label: '文艺竞赛',
    section: '美育 · 文艺竞赛（表 15）',
    dim: 'm',
    slot: 'arts',
    agg: ZcAgg.sum,
    needName: true,
    levels: ['国家级', '省级', '校级'],
    opts: ['一等奖', '二等奖', '三等奖', '未获奖'],
  ),
  ZcTypeSpec(
    id: ZcTypeId.media,
    label: '媒体作品发表',
    section: '美育 · 媒体艺术（表 16）',
    dim: 'm',
    slot: 'media',
    agg: ZcAgg.sum,
    needName: true,
    needOrg: true,
    levels: [
      for (final m in zcMediaLevels) '${m.$1}（${_fmtD(m.$2)} 分/篇）',
    ],
    hint: '须有刊物原件（录用通知无效）；不同作品可累计、同一作品只计最高；院级媒体加分上限 10 分。',
  ),
  ZcTypeSpec(
    id: ZcTypeId.artAct,
    label: '文艺活动参与',
    section: '美育 · 美育活动（表 17）',
    dim: 'm',
    slot: 'artAct',
    agg: ZcAgg.sum,
    needName: true,
    levels: [for (final a in zcArtActLevels) a.$1],
    opts: ['主持人', '表演者'],
    hint: '成功完成活动并被主办方认定为称职。',
  ),
  // ---------- 劳育 ----------
  ZcTypeSpec(
    id: ZcTypeId.social,
    label: '社会实践',
    section: '劳育 · 社会实践（表 19）',
    dim: 'l',
    slot: 'social',
    agg: ZcAgg.sum,
    needName: false,
    needOrg: true,
    levels: [for (final s in zcSocialTypes) s.$1],
    opts: ['国家级', '省部级', '市（校）级', '院级'],
    hint: '以第二课堂导出数据为准。',
  ),
  ZcTypeSpec(
    id: ZcTypeId.laborAct,
    label: '劳育活动',
    section: '劳育 · 实习实训劳动（表 20）',
    dim: 'l',
    slot: 'labor',
    agg: ZcAgg.sum,
    needName: true,
    needOrg: true,
    levels: [for (final a in zcLaborActLevels) a.$1],
    opts: ['优秀', '合格'],
  ),
  ZcTypeSpec(
    id: ZcTypeId.dorm,
    label: '文明寝室',
    section: '劳育 · 文明寝室（表 21）',
    dim: 'l',
    slot: 'dorm',
    agg: ZcAgg.max,
    needName: false,
    needOrg: true,
    levels: [for (final d in zcDormLevels) '${d.$1}（${_fmtD(d.$2)} 分）'],
    hint: '以证书和相关文件为准。',
  ),
];

/// 类型 id → 规格。
final Map<ZcTypeId, ZcTypeSpec> zcTypeSpecOf = {
  for (final s in zcTypeSpecs) s.id: s,
};

// ---------------------------------------------------------------------------
// 学科竞赛名自动匹配（移植 HTML norm/scanContest/matchContest）。
// ---------------------------------------------------------------------------

final RegExp _zcNormRe = RegExp(
  r'''[\s"'“”‘’《》〈〉「」『』·・—–—_()（）【】\[\]①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳,，.。:：;；/\\]''',
);

String _zcNorm(String s) {
  final lower = s.toLowerCase().replaceAll(_zcNormRe, '');
  final buf = StringBuffer();
  for (final code in lower.runes) {
    // 全角数字 → 半角。
    if (code >= 0xff10 && code <= 0xff19) {
      buf.writeCharCode(code - 0xfee0);
    } else {
      buf.writeCharCode(code);
    }
  }
  return buf.toString();
}

const Map<String, int> _zcCatRank = {'c1': 1, 'c2': 2, 'c3': 3, 'c4': 4};

class ZcContestEntry {
  final String cat;
  final String name;
  final String key;
  final bool needJx; // 需含「江西省」
  const ZcContestEntry(this.cat, this.name, this.key, [this.needJx = false]);
}

/// 竞赛命中结果。
class ZcContestHit {
  final String cat;
  final String name;
  const ZcContestHit(this.cat, this.name);
}

final List<ZcContestEntry> _zcContestIndex = _buildIndex();

List<ZcContestEntry> _buildIndex() {
  final out = <ZcContestEntry>[];
  final catOf = <String, String>{};
  for (final entry in zcContests.entries) {
    for (final n in entry.value) {
      final key = _zcNorm(n);
      catOf[key] = entry.key;
      out.add(ZcContestEntry(entry.key, n, key));
    }
  }
  zcContestAliases.forEach((al, main) {
    final c = catOf[_zcNorm(main)];
    if (c != null) out.add(ZcContestEntry(c, main, _zcNorm(al)));
  });
  out.add(const ZcContestEntry('c4', '江西省大学生科技创新竞赛', '江西省大学生科技创新竞赛'));
  for (final s in zcJxContestSubs) {
    out.add(ZcContestEntry('c4', '江西省大学生科技创新竞赛·$s', _zcNorm(s), true));
  }
  return out;
}

ZcContestHit? _scanContest(String q) {
  ZcContestHit? best;
  var bestSc = 0;
  for (final e in _zcContestIndex) {
    if (e.needJx && !q.contains('江西省')) continue;
    final catW = (4 - _zcCatRank[e.cat]!) * 10; // Ⅰ类30 Ⅱ类20 Ⅲ类10 Ⅳ类0
    int sc = 0;
    if (e.key == q) {
      sc = 1000;
    } else if (e.key.contains(q)) {
      sc = 500 + (60 - e.key.length) + catW;
    } else if (q.contains(e.key)) {
      sc = 200 + e.key.length + catW;
    }
    if (sc == 0) continue;
    if (best == null || sc > bestSc) {
      best = ZcContestHit(e.cat, e.name);
      bestSc = sc;
    }
  }
  return best;
}

/// 比赛名称自动识别：命中目录返回类别；未命中返回 null（UI 手动选类别兜底）。
ZcContestHit? zcMatchContest(String raw) {
  final q = _zcNorm(raw);
  if (q.isEmpty) return null;
  final hit = _scanContest(q);
  if (hit != null) return hit;
  // 回退：从长到短枚举子串（如「数学建模国赛」）。
  final seen = <String>{};
  for (var len = (q.length - 1 < 24 ? q.length - 1 : 24); len >= 3; len--) {
    for (var i = 0; i + len <= q.length; i++) {
      final sub = q.substring(i, i + len);
      if (seen.contains(sub)) continue;
      seen.add(sub);
      final m = _scanContest(sub);
      if (m != null) return m;
    }
  }
  return null;
}

/// 供筛选候选列表（自动识别失败时给出相近目录项）。
List<ZcContestEntry> zcFilterContests(String raw) {
  final nq = _zcNorm(raw);
  if (nq.isEmpty) {
    return _zcContestIndex.length > 80
        ? _zcContestIndex.sublist(0, 80)
        : _zcContestIndex;
  }
  final scored = <(int, ZcContestEntry)>[];
  for (final e in _zcContestIndex) {
    if (e.needJx && !nq.contains('江西省')) continue;
    final catW = (4 - _zcCatRank[e.cat]!) * 10;
    int sc = 0;
    if (e.key == nq) {
      sc = 100000;
    } else if (e.key.contains(nq)) {
      sc = 5000 + (60 - e.key.length) + catW;
    } else if (nq.contains(e.key) && e.key.length >= 3) {
      sc = 2000 + e.key.length + catW;
    }
    if (sc > 0) scored.add((sc, e));
  }
  scored.sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final s in scored.take(60)) s.$2];
}
