/// 材料库 → 推免加分项 / 竞赛奖励获奖记录：**自动带入**（唯一实现）。
///
/// 用户 2026-09-18 原话：「我希望推免和竞赛奖励的加分项自动从资料库中获取」，
/// 澄清后选定口径 = **自动带入「材料库」里已登记的证明材料** + **直接按自动识别
/// 结果计入**（不再逐条手填）。所以本文件是「我的数据 → 两个测算页」的唯一桥梁：
/// 页面只调这里的纯函数，不要各自再拼一套映射。
///
/// 口径（改动前先读）：
/// - 来源只有**材料库**（`zcMaterialsProvider`，账号隔离的 `zongce_<账号>` box）；
///   自动条目的 id 一律 = [kMaterialAwardIdPrefix] + 材料 id，页面据此显示「材料库」徽标、
///   去重、以及「忽略」回写（忽略名单见两个 store 的 `excludedMaterialIds`）。
/// - **竞赛类别**：材料里的 `cat`（综测口径 c1~c4 = Ⅰ~Ⅳ 类）优先，缺失时用
///   `zcMatchContest` 按名称识别（与材料库录入时的自动识别同一套）。
/// - **赛别**：国家级 → 国赛、省级 → 省赛；**校级不计入**（《学科竞赛管理办法》
///   第九条只列国赛 / 省赛，没有校赛标准）。
/// - **等次**：材料的 `opt` 索引 → `特等奖/一等奖/二等奖/三等奖`；「参与(未获奖)」不计入。
/// - **认不出的一律不静默丢弃**：返回 `value == null` + `reason`，页面照原样列出，
///   用户要么去材料库改材料，要么在页面上「忽略」。
library;

import '../../competition_award/domain/award_record.dart';
import '../../competition_award/domain/award_standard.dart';
import '../../competition_award/domain/competition_catalog.dart';
import '../../recommendation/domain/bonus_catalog.dart';
import '../../recommendation/domain/recommendation_item.dart';
import '../../zongce/domain/zc_catalog.dart';
import '../../zongce/domain/zc_models.dart';
import '../../zongce/domain/zc_rules.dart';

/// 自动条目 id 前缀（`material:<材料 id>`）。
const String kMaterialAwardIdPrefix = 'material:';

/// 被「忽略」的材料在 [MaterialAwardLink.reason] 里的文案。
///
/// 页面**不靠这段文字**判断谁被忽略了（那是忽略名单 `excludedMaterialIds` 的事，
/// 见 [splitIgnoredMaterials]），它只用于「认不出的一律给原因」这条兜底口径。
const String kMaterialIgnoredReason = '已在页面上忽略这条材料';

String materialAwardIdOf(String materialId) =>
    '$kMaterialAwardIdPrefix$materialId';

/// 自动条目 id → 材料 id（手填条目返回 null）。
String? materialIdOfAwardId(String awardId) => awardId.startsWith(
  kMaterialAwardIdPrefix,
)
    ? awardId.substring(kMaterialAwardIdPrefix.length)
    : null;

/// 材料 → 自动条目（或「为什么没计入」）的统一结果。
class MaterialAwardLink<T> {
  final ZcMaterial material;

  /// null = 没生成条目（原因见 [reason]）。
  final T? value;

  final String? reason;

  const MaterialAwardLink({required this.material, this.value, this.reason});

  bool get linked => value != null;
}

/// 取出所有生成的条目（页面合并手填条目时用）。
List<T> linkedValuesOf<T>(List<MaterialAwardLink<T>> links) => [
  for (final l in links)
    if (l.value != null) l.value as T,
];

/// 未计入的材料（页面「未计入」小节用）。
List<MaterialAwardLink<T>> unlinkedOf<T>(List<MaterialAwardLink<T>> links) => [
  for (final l in links)
    if (l.value == null) l,
];

/// 把「未计入」的材料拆成两拨（页面渲染用）：
/// - `ignored` = 用户**手动忽略**的 → 必须给「恢复」入口（用户 2026-09-18：
///   「竞赛奖励功能里可以忽略某些项，但是没有恢复手段」），否则忽略了就再也回不来；
/// - `skipped` = 其它没算进来的（认不出 / 不达标 / 与手填重复），只列原因。
///
/// 判据用**忽略名单**而不是 `reason` 文案：名单是持久化的真来源，文案只是给用户看的；
/// 材料库改过之后某条材料可能已经认不出了，但它仍在忽略名单里，仍要能被恢复。
({List<MaterialAwardLink<T>> ignored, List<MaterialAwardLink<T>> skipped})
splitIgnoredMaterials<T>(
  List<MaterialAwardLink<T>> links,
  Set<String> excludedMaterialIds,
) {
  final ignored = <MaterialAwardLink<T>>[];
  final skipped = <MaterialAwardLink<T>>[];
  for (final l in links) {
    if (l.value != null) continue;
    if (excludedMaterialIds.contains(l.material.id)) {
      ignored.add(l);
    } else {
      skipped.add(l);
    }
  }
  return (ignored: ignored, skipped: skipped);
}

String _norm(String s) =>
    s.replaceAll(RegExp(r'\s+'), '').replaceAll('＋', '+').toLowerCase();

/// 材料是否属于「学科竞赛获奖」（只有它进竞赛奖励口径）。
bool materialCountsAsContest(ZcMaterial m) => m.typeId == ZcTypeId.contest;

/// 竞赛类别 Ⅰ~Ⅳ：材料 `cat`（c1~c4）优先，缺失时按名称识别（与材料库同一套识别）。
CompetitionClass? materialCompetitionClass(ZcMaterial m) {
  final cat = m.cat.trim().toLowerCase();
  switch (cat) {
    case 'c1':
    case '1':
    case 'Ⅰ':
    case 'i':
      return CompetitionClass.i;
    case 'c2':
    case '2':
    case 'Ⅱ':
    case 'ii':
      return CompetitionClass.ii;
    case 'c3':
    case '3':
    case 'Ⅲ':
    case 'iii':
      return CompetitionClass.iii;
    case 'c4':
    case '4':
    case 'Ⅳ':
    case 'iv':
      return CompetitionClass.iv;
  }
  // 名称兜底：与材料库录入时的自动识别同一套（命中后按识别出的 cat 再走一遍）。
  final hit = zcMatchContest(m.name);
  if (hit == null) return null;
  return materialCompetitionClass(m.copyWith(cat: hit.cat));
}

/// 赛别：国家级 → 国赛、省级 → 省赛、校级（及认不出）→ null。
AwardScope? materialAwardScope(ZcMaterial m) {
  final levels = m.spec.levels;
  final label = (m.level >= 0 && m.level < levels.length)
      ? levels[m.level]
      : '';
  if (label.isEmpty) return null;
  return AwardScope.parse(label);
}

/// 获奖等次名（`opt` → `特等奖/一等奖/二等奖/三等奖`）；「参与(未获奖)」→ null。
String? materialAwardTierName(ZcMaterial m) {
  if (m.opt < 0 || m.opt >= zcPrizeNames.length) return null;
  final name = zcPrizeNames[m.opt];
  return name.startsWith('参与') ? null : name;
}

/// 等次名 → 档位下标（特等 0 / 一等 1 / 二等 2 / 三等 3）。
int? materialAwardTierIndex(ZcMaterial m) {
  final name = materialAwardTierName(m);
  if (name == null) return null;
  if (name.contains('特等')) return 0;
  if (name.contains('一等')) return 1;
  if (name.contains('二等')) return 2;
  return 3;
}

/// 材料备注里若写了排名（`第 3 名` / `排名第 3` / `队内第 2`），取出来给推免排名系数用。
int? materialRankOf(ZcMaterial m) {
  final text = '${m.name} ${m.note}';
  final strong = RegExp(r'第\s*([0-9]{1,2})\s*(?:名|位)').firstMatch(text);
  final weak = RegExp(
    r'(?:排名|队内|个人|作者)\s*第?\s*([0-9]{1,2})',
  ).firstMatch(text);
  final match = strong ?? weak;
  if (match == null) return null;
  final v = int.tryParse(match.group(1)!);
  return (v == null || v < 1) ? null : v;
}

// ---------------------------------------------------------------------------
// 竞赛奖励：材料 → 获奖记录
// ---------------------------------------------------------------------------

/// 材料 → 竞赛奖励获奖记录（认不出 / 不达条件时给 [MaterialAwardLink.reason]）。
///
/// [existing] = 已手工登记的记录，用于去重（同竞赛名 + 同日期视为同一条，
/// 手填优先，自动条目不重复计入）。**只在手填记录之间去重**：材料库同一天登记
/// 同赛事的不同级别（国赛 / 省赛）是两条真记录，要各自交给办法第十条去取最高。
List<MaterialAwardLink<CompetitionAwardRecord>> materialAwardRecordLinks(
  List<ZcMaterial> materials, {
  Set<String> excludedMaterialIds = const {},
  Iterable<CompetitionAwardRecord> existing = const [],
}) {
  final manualKeys = <String>{
    for (final r in existing)
      if (r.date != null) '${_norm(r.competitionName)}@${_dayKey(r.date!)}',
  };
  final out = <MaterialAwardLink<CompetitionAwardRecord>>[];
  for (final m in materials) {
    CompetitionAwardRecord? record;
    String? reason;
    if (excludedMaterialIds.contains(m.id)) {
      reason = kMaterialIgnoredReason;
    } else if (!materialCountsAsContest(m)) {
      reason = '不是学科竞赛获奖材料（竞赛奖励只奖学科竞赛）';
    } else if (m.name.trim().isEmpty) {
      reason = '材料没填名称，认不出是哪项竞赛';
    } else {
      final klass = materialCompetitionClass(m);
      final scope = materialAwardScope(m);
      final tier = materialAwardTierName(m);
      if (klass == null) {
        reason = '认不出竞赛类别（在材料库把「竞赛类别」选成 Ⅰ~Ⅳ 类即可）';
      } else if (scope == null) {
        reason = m.level == 2
            ? '校级竞赛不在奖励标准内（办法只列国赛 / 省赛）'
            : '材料没填级别（国家级 / 省级），无法判定赛别';
      } else if (tier == null) {
        reason = m.opt >= zcPrizeNames.length
            ? '认不出获奖等次'
            : '材料填的是「参与(未获奖)」，办法第十条不计入奖项';
      } else {
        final dedupKey = m.date == null
            ? null
            : '${_norm(m.name)}@${_dayKey(m.date!)}';
        if (dedupKey != null && manualKeys.contains(dedupKey)) {
          reason = '与已登记的手填记录重复，自动条目已跳过';
        } else {
          record = CompetitionAwardRecord(
            id: materialAwardIdOf(m.id),
            competitionName: m.name.trim(),
            klass: klass,
            tierLabel: tier,
            scope: scope,
            date: m.date,
            adjustment: _adjustmentOf(m, klass),
            note: _sourceNote(m),
          );
        }
      }
    }
    out.add(MaterialAwardLink(material: m, value: record, reason: reason));
  }
  return out;
}

/// 第九条两个折减口径：材料里写明了才套（`非主体赛道` / `专项赛` / `国际项目`）。
AwardAdjustment _adjustmentOf(ZcMaterial m, CompetitionClass klass) {
  if (klass != CompetitionClass.i) return AwardAdjustment.none;
  final text = _norm('${m.name} ${m.note}');
  if (text.contains('国际项目')) return AwardAdjustment.international70;
  if (text.contains('非主体赛道') || text.contains('专项赛')) {
    return AwardAdjustment.nonMainTrackAsClassII;
  }
  return AwardAdjustment.none;
}

String _sourceNote(ZcMaterial m) {
  final note = m.note.trim();
  return note.isEmpty ? '来自材料库' : '来自材料库 · $note';
}

/// 去掉目录标签里的括号注记（`（第三发明人以下不加分）` / `（前 2-5 名）`）。
String _stripParens(String s) =>
    s.replaceAll(RegExp(r'[（(][^）)]*[）)]'), '').trim();

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------
// 推免成绩：材料 → 附加分条目
// ---------------------------------------------------------------------------

/// 材料 → 推免加分项（认不出 / 不达条件时给 [MaterialAwardLink.reason]）。
///
/// [existing] = 已手工登记的加分项，用于去重（同项目 + 同日期视为同一条）。
List<MaterialAwardLink<RecommendationBonusItem>> materialBonusItemLinks(
  List<ZcMaterial> materials,
  BonusCatalog catalog, {
  Set<String> excludedMaterialIds = const {},
  Iterable<RecommendationBonusItem> existing = const [],
}) {
  final manualKeys = <String>{
    for (final i in existing)
      if (i.awardDate != null) '${i.optionId}@${_dayKey(i.awardDate!)}',
  };
  final out = <MaterialAwardLink<RecommendationBonusItem>>[];
  for (final m in materials) {
    RecommendationBonusItem? item;
    String? reason;
    if (excludedMaterialIds.contains(m.id)) {
      reason = kMaterialIgnoredReason;
    } else if (m.typeId == ZcTypeId.foreign) {
      reason = '外语水平不在附加分目录里（附加分只认竞赛 / 专利 / 著作权 / 综合 / 科研）';
    } else if (m.name.trim().isEmpty) {
      reason = '材料没填名称，认不出对应哪个加分项目';
    } else {
      final match = _bonusMatchOf(m, catalog);
      if (match == null) {
        reason = _bonusMissReason(m);
      } else {
        final key = m.date == null
            ? null
            : '${match.option.id}@${_dayKey(m.date!)}';
        if (key != null && manualKeys.contains(key)) {
          reason = '与已登记的手填加分项重复，自动条目已跳过';
        } else {
          item = RecommendationBonusItem(
            id: materialAwardIdOf(m.id),
            category: match.option.category,
            optionId: match.option.id,
            // ⚠ 行标题用**我登记的名字**（竞赛名 / 荣誉名 / 专利名），不是目录里那条
            // 加分标准原文——「1.国家级Ⅰ类赛中的专项赛等非主体赛道竞赛；2.列入…」
            // 这种整段文字当标题会连着重复好几行（2026-09-18 实测）。命中的目录项
            // 仍由 optionId 保留、判定依据写进 note，计分不读 label。
            optionLabel: m.name.trim(),
            tierLabel: match.tierLabel,
            rank: materialRankOf(m),
            awardDate: m.date,
            note: _bonusSourceNote(m, match.basis),
          );
        }
      }
    }
    out.add(MaterialAwardLink(material: m, value: item, reason: reason));
  }
  return out;
}

/// 加分项匹配结果：命中的目录选项 + 档位 + 判定依据（页面照原样展示）。
class BonusMatch {
  final BonusOption option;
  final String? tierLabel;

  /// 判定依据（如「国家级 · 排行榜目录 / 非主体赛道档」）。
  final String basis;

  const BonusMatch({required this.option, this.tierLabel, required this.basis});
}

BonusMatch? _bonusMatchOf(ZcMaterial m, BonusCatalog catalog) {
  if (catalog.options.isEmpty) return null;
  return switch (m.typeId) {
    ZcTypeId.contest => _contestMatch(m, catalog),
    ZcTypeId.paper => _paperMatch(m, catalog),
    ZcTypeId.foreign => null,
    _ => _honorMatch(m, catalog),
  };
}

String _bonusMissReason(ZcMaterial m) {
  if (m.typeId == ZcTypeId.contest) {
    final scope = materialAwardScope(m);
    if (scope != AwardScope.national) {
      return '竞赛类加分标准只认国家级（Ⅰ类主体赛道 / Ⅱ类及排行榜目录内竞赛），省级 / 校级不计入';
    }
    if (materialAwardTierName(m) == null) return '材料填的是「参与(未获奖)」，不计入加分';
    return '加分标准里没有与这项竞赛对应的条目';
  }
  if (m.typeId == ZcTypeId.paper) {
    return '论文 / 专利类加分标准里没有与这项对应的条目（发明专利 / 实用新型 / 外观设计 / 核心期刊 / 大创项目）';
  }
  return '综合类加分标准里没有这个荣誉名称（可到材料库把名称写成标准里的原文）';
}

/// 竞赛类：先认三个单列赛项，其余国家级走「排行榜目录 / 非主体赛道」兜底档。
BonusMatch? _contestMatch(ZcMaterial m, BonusCatalog catalog) {
  final opts = catalog.optionsOf(BonusCategory.contest);
  if (opts.isEmpty) return null;
  final text = _norm('${m.name} ${m.note}');
  final tierIndex = materialAwardTierIndex(m);
  if (tierIndex == null) return null;

  BonusOption? option;
  var basis = '';
  BonusOption? byLabel(String needle) {
    for (final o in opts) {
      if (_norm(o.label).contains(needle)) return o;
    }
    return null;
  }

  if (text.contains('创业计划')) {
    option = byLabel('创业计划');
    basis = '“挑战杯”创业计划竞赛';
  } else if (text.contains('课外学术')) {
    option = byLabel('课外学术');
    basis = '“挑战杯”课外学术科技作品竞赛';
  } else if (text.contains('创新大赛') || text.contains('互联网+')) {
    // ⚠ 加分标准原文写「中国国际大学生创新**创业**大赛」，用户口头都叫「创新大赛」，
    // 竞赛目录又写「中国国际大学生创新大赛」——**别去统一名字**，这里只用共同片段定位。
    option = byLabel('大学生创新');
    basis = '中国国际大学生创新大赛';
  }
  if (option == null) {
    if (materialAwardScope(m) != AwardScope.national) return null;
    option = byLabel('排行榜');
    basis = '国家级 · 排行榜目录 / 非主体赛道档';
  }
  if (option == null) return null;
  return BonusMatch(
    option: option,
    tierLabel: bonusTierOf(option, tierIndex),
    basis: basis,
  );
}

/// 材料等次 → 目录档位标签（三种档位命名各自的对应关系，见测试）。
String? bonusTierOf(BonusOption option, int tierIndex) {
  if (!option.hasTiers) return null;
  final tiers = option.tiers;
  final labels = [for (final t in tiers) _norm(t.label)];
  // ① 金 / 银 / 铜：特等→金、一等→银、二等→铜，三等无对应档。
  final medals = ['金', '银', '铜'];
  if (labels.any((l) => medals.any(l.startsWith))) {
    if (tierIndex >= medals.length) return null;
    for (final t in tiers) {
      if (_norm(t.label).startsWith(medals[tierIndex])) return t.label;
    }
    return null;
  }
  // ② 第一 / 二 / 三等次奖：特等与一等都落到第一等次。
  if (labels.any((l) => l.contains('等次'))) {
    final index = tierIndex <= 1 ? 0 : tierIndex - 1;
    return index < tiers.length ? tiers[index].label : null;
  }
  // ③ 特等 / 一等 / 二等 / 三等：同名对位。
  return tierIndex < tiers.length ? tiers[tierIndex].label : null;
}

/// 论文 / 专利类：按材料名称里的关键词落到专利 3 小类 / 著作权 / 核心期刊 / 大创项目。
BonusMatch? _paperMatch(ZcMaterial m, BonusCatalog catalog) {
  final text = _norm('${m.name} ${m.note}');
  BonusOption? pick(BonusCategory category, bool Function(BonusOption) test) {
    for (final o in catalog.optionsOf(category)) {
      if (test(o)) return o;
    }
    return null;
  }

  if (text.contains('著作权') || text.contains('软件登记') || text.contains('版权')) {
    if (m.opt != 0) return null; // 第二登记人及以下不加分
    final option = pick(
      BonusCategory.copyright,
      (o) => _norm(o.label).contains('著作权'),
    );
    if (option == null) return null;
    return BonusMatch(option: option, basis: '著作权第一登记人');
  }

  if (text.contains('专利')) {
    final group = text.contains('发明')
        ? '发明专利'
        : text.contains('实用新型')
        ? '实用新型专利'
        : text.contains('外观')
        ? '外观设计专利'
        : null;
    if (group == null) return null;
    const order = ['第一', '第二', '第三', '第四'];
    final who = m.opt >= 0 && m.opt < order.length ? order[m.opt] : null;
    if (who == null) return null;
    // ⚠ 必须拿**去掉括号注记**后的名字做全等比较：目录里的标签写成
    // 「实用新型专利第二发明人（第三发明人以下不加分）」，用 `contains('第三发明人')`
    // 会把这档误配给第三发明人（实测踩过）。
    final want = _norm('$group$who发明人');
    BonusOption? option;
    for (final o in catalog.optionsOf(BonusCategory.patent)) {
      if (_norm(_stripParens(o.label)) == want) {
        option = o;
        break;
      }
    }
    // 实用新型 / 外观只有第一、第二发明人两档：更后的序位没有对应档，
    // **不回落到第一发明人**（那会把第三发明人算成第一发明人的分值）。
    if (option == null) return null;
    return BonusMatch(option: option, basis: '$group · $who发明人');
  }

  final firstAuthor = m.opt == 0;
  final journal = text.contains('cssci')
      ? 'CSSCI'
      : text.contains('cscd')
      ? 'CSCD'
      : text.contains('北大核心') || text.contains('中文核心')
      ? '北大核心'
      : null;
  if (journal != null) {
    if (!firstAuthor) return null; // 目录里只列第一作者
    final option = pick(
      BonusCategory.research,
      (o) => _norm(o.label).contains(_norm(journal)),
    );
    if (option == null) return null;
    return BonusMatch(option: option, basis: '$journal 期刊文章第一作者');
  }

  final isProject =
      text.contains('大创') ||
      text.contains('创新创业训练计划') ||
      text.contains('创新训练');
  if (isProject) {
    final national = text.contains('国家级');
    final provincial = text.contains('省级');
    if (!national && !provincial) return null;
    final key = national ? '国家级' : '省级';
    final leader = m.opt == 0;
    var option = pick(
      BonusCategory.research,
      (o) =>
          _norm(o.label).contains(_norm(key)) &&
          _norm(o.label).contains('训练计划') &&
          _norm(o.label).contains(leader ? '负责人' : '成员'),
    );
    if (option == null) return null;
    return BonusMatch(
      option: option,
      basis: '$key 大创项目${leader ? '课题负责人' : '课题组成员'}',
    );
  }

  return null;
}

/// 综合类：荣誉 / 奖学金 / 职务 / 事迹等，按名称与目录条目匹配。
///
/// 匹配优先级（**顺序是口径，别改成「最长包含」一把梭**）：
/// 1. **完全相同** → 直接命中（材料写「校优秀学生干部」时不能落到「校优秀学生干部标兵」）；
/// 2. 材料名**包含**目录名 → 取最长的目录名（材料写「2026 年校优秀学生干部」）；
/// 3. 目录名包含材料名 → 取**最短**的目录名（材料只写了「优秀学生干部」）。
BonusMatch? _honorMatch(ZcMaterial m, BonusCatalog catalog) {
  final name = _norm(m.name);
  if (name.length < 3) return null;
  final options = catalog.optionsOf(BonusCategory.honor);
  BonusOption? longer;
  var longerLen = 0;
  for (final o in options) {
    final label = _norm(o.label);
    if (label.length < 3) continue;
    if (label == name) {
      return BonusMatch(option: o, basis: '综合类荣誉称号：${o.label}');
    }
    if (name.contains(label) && label.length > longerLen) {
      longer = o;
      longerLen = label.length;
    }
  }
  if (longer != null) {
    return BonusMatch(option: longer, basis: '综合类荣誉称号：${longer.label}');
  }
  BonusOption? shorter;
  var shorterLen = 1 << 30;
  for (final o in options) {
    final label = _norm(o.label);
    if (label.length < 3) continue;
    if (label.contains(name) && label.length < shorterLen) {
      shorter = o;
      shorterLen = label.length;
    }
  }
  if (shorter == null) return null;
  return BonusMatch(option: shorter, basis: '综合类荣誉称号：${shorter.label}');
}

String _bonusSourceNote(ZcMaterial m, String basis) {
  final note = m.note.trim();
  return [
    '来自材料库 · $basis',
    if (note.isNotEmpty) note,
  ].join(' · ');
}
