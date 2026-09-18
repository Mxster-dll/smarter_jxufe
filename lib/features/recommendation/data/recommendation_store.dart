/// 推免成绩模块 —— 加分项的账号级持久化。
///
/// 存储口径（照 `lib/features/score_estimate/data/ge_prior_grades.dart` 的先例）：
/// - box 名 = `recommendationData`，用 `core/storage/account_scoped_box.dart` 的
///   [openAccountScopedBox] 加账号后缀（`recommendationData_2022xxxx`），
///   **账号未确定时落 `__none`**，绝不回落到别的账号；
/// - 单 key JSON 整表读写（[recommendationItemsKey]），条目本身容错解析；
/// - 任何异常都吞掉（打日志），读取失败按「空列表」处理，落盘失败不影响界面。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/core/storage/account_scoped_box.dart';

import '../domain/recommendation_item.dart';

/// 账号级 box 名基底（真正打开的 box 名由 [openAccountScopedBox] 加后缀）。
const String recommendationBoxBase = 'recommendationData';

/// 单 key：整表 JSON。
const String recommendationItemsKey = 'items';

/// 单 key：被「忽略」的材料 id 列表（自动带入的条目里，用户不认的那些）。
///
/// 自动条目**不落库**（每次都从材料库现算，见 `material_award_bridge.dart`），
/// 这里只记住「哪几条材料不要再自动计入」，这样用户既不用逐条录入、也能纠正
/// 自动识别的错判（改材料库则自动条目跟着变）。
const String recommendationExcludedKey = 'excludedMaterials';

/// 读取本账号已登记的加分项。
Future<List<RecommendationBonusItem>> loadRecommendationItems({
  String? account,
}) async {
  try {
    final box = await openAccountScopedBox(recommendationBoxBase, account);
    final raw = box.get(recommendationItemsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final out = <RecommendationBonusItem>[];
    for (final entry in decoded) {
      final item = RecommendationBonusItem.fromJson(entry);
      if (item != null) out.add(item);
    }
    return out;
  } catch (e) {
    debugPrint('[recommendation] 读取加分项失败：$e');
    return const [];
  }
}

/// 写回本账号的加分项（尽力而为，不抛）。
Future<void> saveRecommendationItems({
  String? account,
  required List<RecommendationBonusItem> items,
}) async {
  try {
    final box = await openAccountScopedBox(recommendationBoxBase, account);
    await box.put(
      recommendationItemsKey,
      jsonEncode([for (final i in items) i.toJson()]),
    );
  } catch (e) {
    debugPrint('[recommendation] 保存加分项失败：$e');
  }
}

/// 推免成绩页的加分项存储（ChangeNotifier：增删改即时反映到界面）。
class RecommendationStore extends ChangeNotifier {
  RecommendationStore({this.account = ''});

  /// 当前账号（学号）；空 = 账号未确定。
  final String account;

  List<RecommendationBonusItem> _items = const [];
  Set<String> _excludedMaterials = const {};
  bool _loaded = false;
  Future<void>? _loading;

  List<RecommendationBonusItem> get items => _items;

  /// 被忽略的材料 id（自动带入时跳过，见 [recommendationExcludedKey]）。
  Set<String> get excludedMaterialIds => _excludedMaterials;

  /// 是否已从磁盘读过一次（未读完时不要写盘，否则会覆盖掉旧数据）。
  bool get loaded => _loaded;

  /// 幂等加载（多次调用只读一次盘）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    _items = await loadRecommendationItems(account: account);
    _excludedMaterials = await loadRecommendationExcluded(account: account);
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(RecommendationBonusItem item) async {
    await ensureLoaded();
    _items = [..._items, item];
    notifyListeners();
    await _persist();
  }

  Future<void> update(RecommendationBonusItem item) async {
    await ensureLoaded();
    _items = [
      for (final i in _items)
        if (i.id == item.id) item else i,
    ];
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    await ensureLoaded();
    _items = [
      for (final i in _items)
        if (i.id != id) i,
    ];
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() =>
      saveRecommendationItems(account: account, items: _items);

  /// 「忽略」一条材料自动带入的条目（不改材料库本身，只在本页不再自动计入）。
  Future<void> excludeMaterial(String materialId) async {
    await ensureLoaded();
    if (_excludedMaterials.contains(materialId)) return;
    _excludedMaterials = {..._excludedMaterials, materialId};
    notifyListeners();
    await _persistExcluded();
  }

  /// 取消忽略（自动条目会重新出现）。
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

  Future<void> _persistExcluded() => saveRecommendationExcluded(
    account: account,
    materialIds: _excludedMaterials,
  );
}

/// 读取本账号被忽略的材料 id。
Future<Set<String>> loadRecommendationExcluded({String? account}) async {
  try {
    final box = await openAccountScopedBox(recommendationBoxBase, account);
    final raw = box.get(recommendationExcludedKey);
    if (raw == null || raw.trim().isEmpty) return const {};
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const {};
    return {for (final id in decoded) if (id is String) id};
  } catch (e) {
    debugPrint('[recommendation] 读取忽略名单失败：$e');
    return const {};
  }
}

/// 写回本账号被忽略的材料 id（尽力而为，不抛）。
Future<void> saveRecommendationExcluded({
  String? account,
  required Set<String> materialIds,
}) async {
  try {
    final box = await openAccountScopedBox(recommendationBoxBase, account);
    await box.put(recommendationExcludedKey, jsonEncode(materialIds.toList()));
  } catch (e) {
    debugPrint('[recommendation] 保存忽略名单失败：$e');
  }
}

/// 加分项 store（切账号自动换实例）。
final recommendationStoreProvider = ChangeNotifierProvider<RecommendationStore>(
  (ref) {
    final account = ref.watch(currentAccountProvider);
    final store = RecommendationStore(account: account);
    // 立即预载：页面首帧就能显示已登记的条目，不会先闪一次空列表。
    unawaited(store.ensureLoaded());
    return store;
  },
);
