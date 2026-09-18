/// 竞赛奖励模块 —— 获奖记录的账号级持久化 + providers（资料库取数）。
///
/// 存储照 `lib/features/recommendation/data/recommendation_store.dart` 的先例：
/// 账号级 box（基底 `competitionAwardData`）+ 单 key JSON 整表 + 容错解析。
///
/// 资料库取数（用户口径「自动资料库里获取竞赛信息」）：
/// - 目录：`rulesCatalogProvider` 里**标题含「竞赛目录」**的全部文档（2024-2025 / 2025-2026…），
///   逐个解析成版本，按年份降序 → [CompetitionCatalog]；
/// - 奖励标准：标题含「学科竞赛管理办法」的文档 → [AwardStandard]。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/core/storage/account_scoped_box.dart';
import 'package:smarter_jxufe/features/rules/data/rules_repository.dart';
import 'package:smarter_jxufe/features/rules/domain/rule_doc.dart';

import '../domain/award_coefficient.dart';
import '../domain/award_record.dart';
import '../domain/award_standard.dart';
import '../domain/competition_catalog.dart';
import 'award_standard_parser.dart';
import 'competition_catalog_parser.dart';

const String competitionAwardBoxBase = 'competitionAwardData';
const String competitionAwardRecordsKey = 'records';

/// 单 key：被「忽略」的材料 id 列表（自动带入的获奖记录里，用户不认的那些）。
///
/// 自动记录**不落库**（每次从材料库现算，见 `material_award_bridge.dart`），
/// 这里只记住「哪几条材料不要再自动计入」。
const String competitionAwardExcludedKey = 'excludedMaterials';

/// 单 key：赛事经验系数表（`[{name, factor}]`；用户 2026-09-18 要求手动设置）。
///
/// 口径 = **按赛事**（一个赛事的比例是固定的）：命中的记录等比缩减，
/// 未设过的赛事一律按 1（不缩减）。见 `domain/award_coefficient.dart`。
const String competitionAwardCoefficientsKey = 'coefficients';

Future<List<CompetitionAwardRecord>> loadCompetitionAwardRecords({
  String? account,
}) async {
  try {
    final box = await openAccountScopedBox(competitionAwardBoxBase, account);
    final raw = box.get(competitionAwardRecordsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final out = <CompetitionAwardRecord>[];
    for (final entry in decoded) {
      final record = CompetitionAwardRecord.fromJson(entry);
      if (record != null) out.add(record);
    }
    return out;
  } catch (e) {
    debugPrint('[competition_award] 读取获奖记录失败：$e');
    return const [];
  }
}

Future<void> saveCompetitionAwardRecords({
  String? account,
  required List<CompetitionAwardRecord> records,
}) async {
  try {
    final box = await openAccountScopedBox(competitionAwardBoxBase, account);
    await box.put(
      competitionAwardRecordsKey,
      jsonEncode([for (final r in records) r.toJson()]),
    );
  } catch (e) {
    debugPrint('[competition_award] 保存获奖记录失败：$e');
  }
}

/// 读取本账号的赛事经验系数表。
Future<List<AwardCoefficient>> loadCompetitionAwardCoefficients({
  String? account,
}) async {
  try {
    final box = await openAccountScopedBox(competitionAwardBoxBase, account);
    final raw = box.get(competitionAwardCoefficientsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final out = <AwardCoefficient>[];
    for (final entry in decoded) {
      final item = AwardCoefficient.fromJson(entry);
      if (item != null) out.add(item);
    }
    return out;
  } catch (e) {
    debugPrint('[competition_award] 读取赛事系数失败：$e');
    return const [];
  }
}

/// 写回本账号的赛事经验系数表（尽力而为，不抛）。
Future<void> saveCompetitionAwardCoefficients({
  String? account,
  required List<AwardCoefficient> coefficients,
}) async {
  try {
    final box = await openAccountScopedBox(competitionAwardBoxBase, account);
    await box.put(
      competitionAwardCoefficientsKey,
      jsonEncode([for (final c in coefficients) c.toJson()]),
    );
  } catch (e) {
    debugPrint('[competition_award] 保存赛事系数失败：$e');
  }
}

/// 获奖记录 store（增删改即时反映到界面）。
class CompetitionAwardStore extends ChangeNotifier {
  CompetitionAwardStore({this.account = ''});

  final String account;

  List<CompetitionAwardRecord> _records = const [];
  Set<String> _excludedMaterials = const {};
  List<AwardCoefficient> _coefficients = const [];
  bool _loaded = false;
  Future<void>? _loading;

  List<CompetitionAwardRecord> get records => _records;

  /// 被忽略的材料 id（自动带入时跳过，见 [competitionAwardExcludedKey]）。
  Set<String> get excludedMaterialIds => _excludedMaterials;

  /// 赛事经验系数（手动设置，见 [competitionAwardCoefficientsKey]）。
  List<AwardCoefficient> get coefficients => _coefficients;

  /// 计算层直接吃的表（查询唯一入口）。
  AwardCoefficientTable get coefficientTable =>
      AwardCoefficientTable(_coefficients);

  bool get loaded => _loaded;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    _records = await loadCompetitionAwardRecords(account: account);
    _excludedMaterials = await loadCompetitionAwardExcluded(account: account);
    _coefficients = await loadCompetitionAwardCoefficients(account: account);
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(CompetitionAwardRecord record) async {
    await ensureLoaded();
    _records = [..._records, record];
    notifyListeners();
    await _persist();
  }

  Future<void> update(CompetitionAwardRecord record) async {
    await ensureLoaded();
    _records = [
      for (final r in _records)
        if (r.id == record.id) record else r,
    ];
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    await ensureLoaded();
    _records = [
      for (final r in _records)
        if (r.id != id) r,
    ];
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() =>
      saveCompetitionAwardRecords(account: account, records: _records);

  /// 「忽略」一条材料自动带入的记录（不改材料库本身，只在本页不再自动计入）。
  Future<void> excludeMaterial(String materialId) async {
    await ensureLoaded();
    if (_excludedMaterials.contains(materialId)) return;
    _excludedMaterials = {..._excludedMaterials, materialId};
    notifyListeners();
    await _persistExcluded();
  }

  /// 取消忽略（自动记录会重新出现）。
  Future<void> includeMaterial(String materialId) async {
    await ensureLoaded();
    if (!_excludedMaterials.contains(materialId)) return;
    _excludedMaterials = {
      for (final id in _excludedMaterials)
        if (id != materialId) id,
    };
    notifyListeners();
    await _persistExcluded();
  }

  Future<void> _persistExcluded() => saveCompetitionAwardExcluded(
    account: account,
    materialIds: _excludedMaterials,
  );

  /// 设置 / 覆盖某赛事的经验系数（同名按归一后的名字覆盖）。
  Future<void> setCoefficient(String competitionName, double factor) async {
    await ensureLoaded();
    final next = coefficientTable
        .upsert(
          AwardCoefficient(
            competitionName: competitionName.trim(),
            factor: factor.clamp(kAwardCoefficientMin, kAwardCoefficientMax),
          ),
        )
        .entries;
    _coefficients = next;
    notifyListeners();
    await _persistCoefficients();
  }

  /// 删除某赛事的系数（该赛事恢复按办法标准全额计算）。
  Future<void> removeCoefficient(String competitionName) async {
    await ensureLoaded();
    final key = awardCoefficientKey(competitionName);
    final next = [
      for (final c in _coefficients)
        if (awardCoefficientKey(c.competitionName) != key) c,
    ];
    if (next.length == _coefficients.length) return;
    _coefficients = next;
    notifyListeners();
    await _persistCoefficients();
  }

  Future<void> _persistCoefficients() => saveCompetitionAwardCoefficients(
    account: account,
    coefficients: _coefficients,
  );
}

/// 读取本账号被忽略的材料 id。
Future<Set<String>> loadCompetitionAwardExcluded({String? account}) async {
  try {
    final box = await openAccountScopedBox(competitionAwardBoxBase, account);
    final raw = box.get(competitionAwardExcludedKey);
    if (raw == null || raw.trim().isEmpty) return const {};
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const {};
    return {for (final id in decoded) if (id is String) id};
  } catch (e) {
    debugPrint('[competition_award] 读取忽略名单失败：$e');
    return const {};
  }
}

/// 写回本账号被忽略的材料 id（尽力而为，不抛）。
Future<void> saveCompetitionAwardExcluded({
  String? account,
  required Set<String> materialIds,
}) async {
  try {
    final box = await openAccountScopedBox(competitionAwardBoxBase, account);
    await box.put(competitionAwardExcludedKey, jsonEncode(materialIds.toList()));
  } catch (e) {
    debugPrint('[competition_award] 保存忽略名单失败：$e');
  }
}

final competitionAwardStoreProvider =
    ChangeNotifierProvider<CompetitionAwardStore>((ref) {
      final account = ref.watch(currentAccountProvider);
      final store = CompetitionAwardStore(account: account);
      unawaited(store.ensureLoaded());
      return store;
    });

/// 资料库里的竞赛目录文档（标题含「竞赛目录」），按标题年份降序。
final competitionCatalogDocsProvider = FutureProvider<List<RuleDoc>>((ref) async {
  final catalog = await ref.watch(rulesCatalogProvider.future);
  final docs = [
    for (final d in catalog.docs)
      if (d.title.contains('竞赛目录')) d,
  ];
  docs.sort((a, b) => b.year.compareTo(a.year));
  return docs;
});

/// 竞赛目录（全部版本，新 → 旧）。
final competitionCatalogProvider = FutureProvider<CompetitionCatalog>((ref) async {
  final docs = await ref.watch(competitionCatalogDocsProvider.future);
  final editions = <CompetitionCatalogEdition>[];
  for (final doc in docs) {
    try {
      final edition = parseCompetitionCatalogEdition(
        await rootBundle.loadString(doc.mdAsset),
        sourceDocId: doc.id,
      );
      if (edition != null) editions.add(edition);
    } catch (e) {
      debugPrint('[competition_award] 解析 ${doc.title} 失败：$e');
    }
  }
  return competitionCatalogOf(editions);
});

/// 学科竞赛管理办法的文档（奖励标准出处）。
final awardStandardDocProvider = FutureProvider<RuleDoc?>((ref) async {
  final catalog = await ref.watch(rulesCatalogProvider.future);
  for (final family in catalog.families) {
    if (family.group == '学科竞赛' && family.name.contains('学科竞赛管理办法')) {
      return family.defaultDoc;
    }
  }
  for (final doc in catalog.docs) {
    if (doc.title.contains('学科竞赛管理办法')) return doc;
  }
  return null;
});

/// 奖励标准（解析自资料库文档）。
final awardStandardProvider = FutureProvider<AwardStandard>((ref) async {
  final doc = await ref.watch(awardStandardDocProvider.future);
  if (doc == null) return AwardStandard.empty;
  try {
    return parseAwardStandard(await rootBundle.loadString(doc.mdAsset));
  } catch (e) {
    debugPrint('[competition_award] 解析奖励标准失败：$e');
    return AwardStandard.empty;
  }
});
