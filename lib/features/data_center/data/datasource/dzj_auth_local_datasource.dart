import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_auth_remote_datasource.dart';

/// 竹简数据中台（dzj）会话本地存储（按账户分别保存）。
///
/// 每个账户保存服务端下发的 SESSION 与 fixedSalt（AES 会话密钥派生盐），
/// 以及最近一次换取时间。键名带账户后缀，互不干扰。
class DzjAuthLocalDataSource {
  final Box<String> _box;

  DzjAuthLocalDataSource(this._box);

  static String _sessionKey(String account) => 'dzj_session_$account';
  static String _saltKey(String account) => 'dzj_salt_$account';
  static String _timeKey(String account) => 'dzj_ts_$account';

  /// 读取指定账户的会话；无缓存返回 null。
  DzjSession? getSession(String account) {
    final session = _box.get(_sessionKey(account));
    final salt = _box.get(_saltKey(account));
    if (session == null || session.isEmpty || salt == null || salt.isEmpty) {
      return null;
    }
    return DzjSession(session: session, fixedSalt: salt);
  }

  /// 最近一次会话换取时间（毫秒时间戳）。
  DateTime? getUpdatedAt(String account) {
    final raw = _box.get(_timeKey(account));
    if (raw == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(int.tryParse(raw) ?? 0);
  }

  /// 保存会话（同时记录当前时间）。
  Future<void> saveSession(String account, DzjSession session) async {
    await _box.put(_sessionKey(account), session.session);
    await _box.put(_saltKey(account), session.fixedSalt);
    await _box.put(
      _timeKey(account),
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  /// 清除指定账户的本地会话。
  Future<void> clearSession(String account) async {
    await _box.delete(_sessionKey(account));
    await _box.delete(_saltKey(account));
    await _box.delete(_timeKey(account));
  }
}
