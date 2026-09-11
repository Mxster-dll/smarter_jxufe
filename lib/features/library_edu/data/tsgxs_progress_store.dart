import 'package:hive/hive.dart';

/// 入馆教育本地已浏览节点记录(仅用于 UI 标记,服务端另有自己的学习记录)。
///
/// 存放于 Hive box `tsgxs`,key 为 `visited_<学号>`,值以逗号分隔节点 id。
class TsgxsVisitedStore {
  final Box<String> _box;
  final String _account;

  TsgxsVisitedStore(this._box, this._account);

  String get _key => 'visited_$_account';

  /// 已浏览节点 id 集合。
  Set<String> load() {
    final raw = _box.get(_key);
    if (raw == null || raw.isEmpty) return <String>{};
    return raw.split(',').where((e) => e.isNotEmpty).toSet();
  }

  /// 标记某节点已浏览。
  Future<void> markVisited(String nodeId) async {
    if (nodeId.isEmpty) return;
    final all = load()..add(nodeId);
    await _box.put(_key, all.join(','));
  }
}
