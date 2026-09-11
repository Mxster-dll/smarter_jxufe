/// 阅读学分平台会话的本地持久化（Hive box `readCredit`，按账号存 Cookie 串）。
library;

import 'package:hive/hive.dart';

/// 阅读学分平台会话 Cookie 存储。
class ReadCreditAuthLocalDataSource {
  final Box<String> _box;

  const ReadCreditAuthLocalDataSource(this._box);

  static const String boxName = 'readCredit';

  static String keyFor(String account) => 'readCredit_ck_$account';

  String? getCookie(String account) {
    final value = _box.get(keyFor(account));
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> saveCookie(String account, String cookie) =>
      _box.put(keyFor(account), cookie);

  Future<void> clearCookie(String account) => _box.delete(keyFor(account));
}
