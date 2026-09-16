/// 畅想之星个人会话（统一认证换来的 JWT）本地持久化。
///
/// 与项目其它平台会话一致：**按账号**存 key（`cxstar_tk_<账号>`），
/// 换号不串号；token 有效期 24 小时，过期由仓库重新换证覆盖。
library;

import 'package:hive/hive.dart';

class CxstarAuthLocalDataSource {
  /// 会话存储 box（与手工令牌共用 box，key 前缀区分）。
  static const String boxName = 'cxstar';

  static const String keyPrefix = 'cxstar_tk_';

  final Box<String> _box;

  CxstarAuthLocalDataSource(this._box);

  /// 指定账号的会话 key。
  static String keyOf(String account) => '$keyPrefix$account';

  String? getToken(String account) {
    final value = _box.get(keyOf(account));
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> saveToken(String account, String token) =>
      _box.put(keyOf(account), token);

  Future<void> clearToken(String account) => _box.delete(keyOf(account));
}
