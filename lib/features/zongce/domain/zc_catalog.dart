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

  /// 分值**手动填写**（用户 2026-09-17：外语「不要分成 xxx≥aaa/xxx>bbb，直接按证书
  /// 名字，然后手动填入分数」）——`levels` 只作参考文案，表单给一个「得分」输入框，
  /// 分数存进 `ZcMaterial.manualScore`。
  final bool manualScore;

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
    this.manualScore = false,
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
    // 用户 2026-09-17：按证书名目选，得分自己填（levels 只作参考文案）。
    manualScore: true,
    levels: [for (final f in zcForeignLevels) '${f.$1}（${_fmtD(f.$2)} 分）'],
    hint: '按证书名目录入，得分自行填写（表 10 档位仅供参考）；单项取最高一次计分。',
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
  r'''[\s\u200b-\u200d\ufeff"'“”‘’《》〈〉「」『』·・—–—_()（）【】\[\]①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳,，.。:：;；/\\]''',
);

/// 名称归一化（**自动识别与搜索共用**）：小写、去全部空白与零宽字符、去标点、
/// 全角数字转半角。
///
/// ⚠ 学科竞赛目录是人工从校发文件（含 PDF/网页换行）抄来的，名字里夹着空白
/// （`华为 ICT 大赛`、`中国机器人大赛暨 RoboCup 机器人世界杯中国赛`）与
/// 换行残留（`团体程序设计天梯 赛`）→ **两侧都要过这个函数**再比较，
/// 否则「华为ICT大赛」永远搜不到「华为 ICT 大赛」（用户 2026-09-18 报告）。
String zcNameKey(String s) {
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

/// 是否为「中文侧」字符（CJK 汉字 / 中文标点 / 全角符号）。
bool _zcIsCjkSide(int code) =>
    (code >= 0x4e00 && code <= 0x9fff) ||
    (code >= 0x3400 && code <= 0x4dbf) ||
    (code >= 0xf900 && code <= 0xfaff) ||
    (code >= 0x3000 && code <= 0x303f) ||
    (code >= 0xff01 && code <= 0xff5e);

/// 清理**原稿换行**留下的空白（显示与回填用，不动目录数据）。
///
/// 规则：两侧都是中文的空白 = 换行残留 → 删除（`团体程序设计天梯 赛` →
/// `团体程序设计天梯赛`）；其余空白（中英之间）折叠成一个空格并保留
/// （`华为 ICT 大赛` 原样，这种间隔是排版需要）。零宽字符一律删除。
String zcCleanName(String raw) {
  final noZeroWidth = raw.replaceAll(RegExp(r'[\u200b-\u200d\ufeff]'), '');
  final collapsed = noZeroWidth.replaceAll(RegExp(r'\s+'), ' ');
  final buf = StringBuffer();
  for (var i = 0; i < collapsed.length; i++) {
    final ch = collapsed[i];
    if (ch == ' ' && i > 0 && i < collapsed.length - 1) {
      final prev = collapsed.codeUnitAt(i - 1);
      final next = collapsed.codeUnitAt(i + 1);
      if (_zcIsCjkSide(prev) && _zcIsCjkSide(next)) continue;
    }
    buf.write(ch);
  }
  return buf.toString().trim();
}

/// 带圈序号（复合赛事名的子项标记）。
const String _zcCompositeMarks = '①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳';

/// 复合赛事名拆解：`主名一①子项、②子项…` / `主名（子项A、子项B）` →
/// 显示用主名 + 可搜索子项。
///
/// 真实样例（用户 2026-09-18 原话）：`中国高校计算机大赛一①大数据挑战赛、
/// ②团体程序设计天梯 赛、③移动应用创新赛、④网络技术挑战赛、⑤人工智能创意 赛`
/// —— 材料名显示主名（`中国高校计算机大赛`）是对的，但**搜索**要能被
/// 「大数据挑战赛」「团体程序设计天梯赛」这类子项命中。
({String main, List<String> subs}) zcSplitCompositeContest(String raw) {
  final s = zcCleanName(raw);
  final markAt = s.split('').toList().indexWhere(_zcCompositeMarks.contains);
  if (markAt > 0) {
    final main = _zcTrimCompositeHead(s.substring(0, markAt));
    final subs = <String>[];
    final buf = StringBuffer();
    for (final ch in s.substring(markAt).split('')) {
      if (_zcCompositeMarks.contains(ch) || '、，,；;/'.contains(ch)) {
        _zcFlushSub(subs, buf);
      } else {
        buf.write(ch);
      }
    }
    _zcFlushSub(subs, buf);
    if (main.isNotEmpty && subs.isNotEmpty) return (main: main, subs: subs);
  }
  final split = _zcSplitParenEnum(s);
  if (split != null) return (main: split.$1, subs: split.$2);
  return (main: s, subs: const []);
}

/// `主名（子项A、子项B）` 形态：取第一个内容含 ≥2 个枚举项的括号。
///
/// 与 `zc_activity.dart` 的 `zcSplitExample` 同口径，但**不 import 它**：
/// zc_activity 依赖本文件，反向 import 会形成库循环。
(String, List<String>)? _zcSplitParenEnum(String s) {
  final open = s.indexOf('（');
  final openEn = s.indexOf('(');
  int at;
  String close;
  if (open == -1 && openEn == -1) return null;
  if (openEn == -1 || (open != -1 && open < openEn)) {
    at = open;
    close = '）';
  } else {
    at = openEn;
    close = ')';
  }
  final end = s.indexOf(close, at + 1);
  if (end == -1) return null;
  final subs = [
    for (final part in s.substring(at + 1, end).split(RegExp(r'[、，,；;|/\\]')))
      if (part.trim().isNotEmpty) part.trim(),
  ];
  if (subs.length < 2) return null;
  final main = s.substring(0, at).trim();
  if (main.isEmpty) return null;
  return (main, subs);
}

String _zcTrimCompositeHead(String head) {
  var h = head.trim();
  const trailing = '一-—–－:：·、，,（(【[《<';
  while (h.isNotEmpty && trailing.contains(h[h.length - 1])) {
    h = h.substring(0, h.length - 1).trim();
  }
  return h;
}

void _zcFlushSub(List<String> out, StringBuffer buf) {
  var t = buf.toString().trim();
  buf.clear();
  while (t.length > 1 && t.endsWith('等')) {
    t = t.substring(0, t.length - 1).trim();
  }
  if (t.isNotEmpty) out.add(t);
}

/// 某竞赛名的**全部可搜索词**：复合名子项 + 指向它的别名
/// （`大数据挑战赛 → 中国高校计算机大赛`，见 [zcContestAliases]）。
List<String> zcContestKeywords(String name) {
  final key = zcNameKey(name);
  final comp = zcSplitCompositeContest(name);
  final keys = <String>{key, for (final sub in comp.subs) zcNameKey(sub)};
  final out = <String>{};
  for (final sub in comp.subs) {
    if (zcNameKey(sub) != key) out.add(sub);
  }
  zcContestAliases.forEach((alias, main) {
    if (keys.contains(zcNameKey(main)) && zcNameKey(alias) != key) out.add(alias);
  });
  return out.toList();
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
  final seenKeys = <String>{};
  // 目录名先清洗（去原稿换行残留的空白），再按「主名 + 复合子项」建索引：
  // 子项各自成一条（name 仍是主名）→ 用户输入「大数据挑战赛」「团体程序设计
  // 天梯赛」也能识别出类别（用户 2026-09-18 要求）。
  for (final entry in zcContests.entries) {
    for (final raw in entry.value) {
      final clean = zcCleanName(raw);
      final key = zcNameKey(clean);
      catOf[key] = entry.key;
      if (seenKeys.add(key)) out.add(ZcContestEntry(entry.key, clean, key));
      final comp = zcSplitCompositeContest(clean);
      final mainKey = zcNameKey(comp.main);
      if (mainKey.isNotEmpty && mainKey != key) {
        catOf[mainKey] = entry.key;
        if (seenKeys.add(mainKey)) {
          out.add(ZcContestEntry(entry.key, comp.main, mainKey));
        }
      }
      for (final sub in comp.subs) {
        final subKey = zcNameKey(sub);
        if (subKey.isEmpty || subKey == key || subKey == mainKey) continue;
        catOf[subKey] = entry.key;
        if (seenKeys.add(subKey)) {
          out.add(ZcContestEntry(entry.key, comp.main, subKey));
        }
      }
    }
  }
  zcContestAliases.forEach((al, main) {
    final c = catOf[zcNameKey(main)];
    if (c != null) out.add(ZcContestEntry(c, main, zcNameKey(al)));
  });
  out.add(const ZcContestEntry('c4', '江西省大学生科技创新竞赛', '江西省大学生科技创新竞赛'));
  for (final s in zcJxContestSubs) {
    out.add(
      ZcContestEntry('c4', '江西省大学生科技创新竞赛·$s', zcNameKey(s), true),
    );
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
  final q = zcNameKey(raw);
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
  final nq = zcNameKey(raw);
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
