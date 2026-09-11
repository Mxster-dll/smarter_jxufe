import 'package:hive_flutter/hive_flutter.dart';

/// 入馆教育(tsgxs)平台会话 Cookie 本地存储(按账户)。
class TsgxsAuthLocalDataSource {
  final Box<String> _box;

  TsgxsAuthLocalDataSource(this._box);

  static String _cookieKey(String account) => 'tsgxs_ck_$account';

  /// 读取指定账户的会话 Cookie 串；无缓存返回 null。
  String? getCookie(String account) {
    final c = _box.get(_cookieKey(account));
    if (c == null || c.trim().isEmpty) return null;
    return c;
  }

  /// 保存会话 Cookie 串。
  Future<void> saveCookie(String account, String cookie) =>
      _box.put(_cookieKey(account), cookie);

  /// 清除指定账户的本地会话。
  Future<void> clearCookie(String account) => _box.delete(_cookieKey(account));
}
