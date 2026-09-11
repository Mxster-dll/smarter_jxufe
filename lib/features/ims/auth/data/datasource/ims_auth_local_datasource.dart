import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ims/auth/data/ims_session.dart';

/// IMS 会话的本地持久化（Hive box `imsAuth`）。
///
/// **按账号隔离**：键 = `JSESSIONID|<账号>`（另有 `JSESSIONID|<账号>|at` 记落盘
/// 时间）。切换账号**不清除任何账号的会话**——切回来还能直接复用；只有退出登录
/// 才 [forget]。
///
/// 历史版本用的是不带账号的单键 `JSESSIONID`（切号会串号）。
/// [migrateLegacy] 把它认领给**第一个读到它的账号**并删除旧键：因为只成功一次，
/// 不会出现「B 账号继承 A 账号会话」。
class ImsAuthLocalDataSource implements ImsSessionStore {
  /// 历史版本的公共键（无账号）。
  static const legacyJsessionIdKey = 'JSESSIONID';

  /// 会话键前缀。
  static const jsessionIdPrefix = 'JSESSIONID|';

  /// 某账号的会话键。
  static String jsessionIdKey(String account) => '$jsessionIdPrefix$account';

  /// 某账号的落盘时间键。
  static String issuedAtKey(String account) => '$jsessionIdPrefix$account|at';

  final Box<String> _box;

  ImsAuthLocalDataSource(this._box);

  @override
  Future<String?> read(String account) async {
    if (account.isEmpty) return null;
    final value = _box.get(jsessionIdKey(account));
    return (value == null || value.isEmpty) ? null : value;
  }

  /// 该账号会话的落盘时间（未记录时 null）。
  DateTime? issuedAt(String account) {
    if (account.isEmpty) return null;
    final raw = _box.get(issuedAtKey(account));
    return raw == null ? null : DateTime.tryParse(raw);
  }

  @override
  Future<void> write(String account, String jsessionId) async {
    if (account.isEmpty) return;
    await _box.put(jsessionIdKey(account), jsessionId);
    await _box.put(issuedAtKey(account), DateTime.now().toIso8601String());
  }

  @override
  Future<String?> migrateLegacy(String account) async {
    if (account.isEmpty) return null;
    final legacy = _box.get(legacyJsessionIdKey);
    if (legacy == null || legacy.isEmpty) return null;
    await write(account, legacy);
    await _box.delete(legacyJsessionIdKey);
    return legacy;
  }

  @override
  Future<void> forget(String account) async {
    if (account.isEmpty) return;
    await _box.delete(jsessionIdKey(account));
    await _box.delete(issuedAtKey(account));
  }
}
