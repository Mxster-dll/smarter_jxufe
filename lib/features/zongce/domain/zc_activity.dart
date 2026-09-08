import 'zc_catalog.dart';
import 'zc_rules.dart';

/// 「材料添加向导」二级页的候选数据源与复合格式拆分。
///
/// 目录规则（用户拍板）：
/// - 一级 = 材料类型（活动大类）；二级 = 该类型下「各种具体活动/档位」候选；
/// - 档位文案里凡带「枚举括号」的复合选项（真实样例：
///   `国家级（征兵入伍/西部计划/三支一扶等）`、
///   `国家级（征兵入伍/西部计划/三支一扶等）（5 分）`、
///   `国家级（征兵入伍/退役证书、西部计划、三支一扶）5 分`）——
///   取出括号内各项（征兵入伍/西部计划/三支一扶），扁平化为独立候选
///   （各自继承原档位，点选即回填名称），并追加「其他 国家级」兜底项；
/// - 竞赛类型候选 = 内置竞赛目录（Ⅰ~Ⅳ 类，可搜索）；其余类型候选 =
///   现有 `levels` 档位（点选即预选档位，名称仍在表单填写）。

/// 二级页一个候选行（已扁平化，不含复合格式）。
class ZcActivityItem {
  const ZcActivityItem({
    required this.title,
    this.group,
    this.namePrefill,
    this.levelIdx,
    this.cat,
    this.other = false,
  });

  /// 显示文案。
  final String title;

  /// 分组标题（竞赛目录：Ⅰ 类…Ⅳ 类）。
  final String? group;

  /// 选中后回填材料名称（仅语义即为「活动名」的候选，如竞赛/外语证书）。
  final String? namePrefill;

  /// 选中后预选「级别/档位」索引。
  final int? levelIdx;

  /// 选中后回填竞赛类别（c1~c4）。
  final String? cat;

  /// 「其他 xxx（手动填写）」兜底项。
  final bool other;
}

/// 例项清理：去首尾空白；尾部单字「等」（列举未完标记）剥除，
/// 如 `三支一扶等 → 三支一扶`。
String _cleanEx(String e) {
  var x = e.trim();
  while (x.length > 1 && x.endsWith('等')) {
    x = x.substring(0, x.length - 1).trim();
  }
  return x;
}

/// 把复合文案拆成「主体 + 具体活动清单」。
///
/// 依次扫描括号，取**第一个内容含 ≥2 个枚举项**的括号作为活动枚举：
/// - 括号前文本为「主体」（档位名/活动族，如 国家级、志愿服务）；
/// - 括号内各项为具体活动（分隔符：`\ / 、 ， ， ； |`），可选 `例` 前缀；
/// - 例项末尾「等」剥除；空例剔除。
///
/// 兼容真实形态：`xxx（例 aaaa\bbbb）`、
/// `国家级（征兵入伍/西部计划/三支一扶等）（5 分）`（后半截分数字样所在
/// 括号只有 1 项，自动跳过）、HTML 原稿 `…）5 分`。
/// 未命中（无枚举括号 / 括号内单一项）时 has = false，base 为整串原样。
({String base, List<String> examples, bool has}) zcSplitExample(String raw) {
  final s = raw.trim();
  const seps = r'[、，,；;|/\\]';
  final exLead = RegExp(r'^例\s*[:：]?\s*');
  var pos = 0;
  while (pos < s.length) {
    final oCn = s.indexOf('（', pos);
    final oEn = s.indexOf('(', pos);
    int open;
    String close;
    if (oCn == -1 && oEn == -1) break;
    if (oEn == -1 || (oCn != -1 && oCn < oEn)) {
      open = oCn;
      close = '）';
    } else {
      open = oEn;
      close = ')';
    }
    final c = s.indexOf(close, open + 1);
    if (c == -1) break;
    var inner = s.substring(open + 1, c).trim();
    final lead = exLead.firstMatch(inner);
    if (lead != null) inner = inner.substring(lead.end).trim();
    final exs = inner
        .split(RegExp(seps))
        .map(_cleanEx)
        .where((e) => e.isNotEmpty)
        .toList();
    if (exs.length >= 2) {
      return (
        base: s.substring(0, open).trim(),
        examples: exs,
        has: true,
      );
    }
    pos = c + close.length;
  }
  return (base: s, examples: const [], has: false);
}

/// 竞赛目录（Ⅰ~Ⅳ 类）作为候选。
List<ZcActivityItem> _contestItems() {
  final out = <ZcActivityItem>[];
  final seen = <String>{};
  for (final cat in const ['c1', 'c2', 'c3']) {
    final group = zcCatNames[cat] ?? cat;
    for (final n in zcContests[cat] ?? const <String>[]) {
      if (!seen.add(n)) continue;
      out.add(ZcActivityItem(
        title: n,
        group: group,
        namePrefill: n,
        cat: cat,
      ));
    }
  }
  // Ⅳ 类 = 江西省大学生科技创新竞赛子项目。
  for (final s in zcJxContestSubs) {
    final name = '江西省大学生科技创新竞赛 $s';
    out.add(ZcActivityItem(
      title: name,
      group: 'Ⅳ类（江西省赛）',
      namePrefill: name,
      cat: 'c4',
    ));
  }
  out.add(const ZcActivityItem(title: '其他比赛（手动录入）', other: true));
  return out;
}

/// 某类型在二级页展示的候选（数据层已做「枚举括号」拆分与去重）。
///
/// - 竞赛：内置目录（每个候选带类别，选中即回填名称 + 类别）。
/// - 档位带枚举的（如 优秀事迹国家级（征兵入伍/西部计划/三支一扶等））：
///   各例项独立成候选并回填名称，另追加「其他 档位」兜底。
/// - 其余：`levels` 档位逐项作为候选（点选预选档位），名称留表单填写。
/// - 外语：levels 语义即为证书名，候选名目直接回填为材料名称。
List<ZcActivityItem> zcActivityItems(ZcTypeSpec spec) {
  if (spec.id == ZcTypeId.contest) return _contestItems();
  final out = <ZcActivityItem>[];
  // 外语：levels 语义即证书名（如「雅思（≥6.5）2 分」），
  // 点选即回填证书名，无需再到表单手输名称。
  if (spec.id == ZcTypeId.foreign) {
    final n =
        spec.levels.length < zcForeignLevels.length
            ? spec.levels.length
            : zcForeignLevels.length;
    for (var i = 0; i < n; i++) {
      out.add(ZcActivityItem(
        title: spec.levels[i],
        levelIdx: i,
        namePrefill: zcForeignLevels[i].$1,
      ));
    }
    return out;
  }
  for (var i = 0; i < spec.levels.length; i++) {
    final raw = spec.levels[i];
    final split = zcSplitExample(raw);
    if (split.has) {
      for (final ex in split.examples) {
        out.add(ZcActivityItem(
          title: ex,
          levelIdx: i,
          namePrefill: ex,
        ));
      }
      if (split.base.isNotEmpty) {
        out.add(ZcActivityItem(
          title: '其他 ${split.base}',
          other: true,
          levelIdx: i,
        ));
      }
    } else {
      out.add(ZcActivityItem(title: raw, levelIdx: i));
    }
  }
  return out;
}
