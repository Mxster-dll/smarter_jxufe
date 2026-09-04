import 'package:hive_flutter/hive_flutter.dart';

/// 综合管理服务平台（ssp.jxufe.edu.cn）会话的本地持久化。
///
/// 按账户分别保存 JSESSIONID 及其获取时间，
/// 便于账户切换后互不干扰，也方便排查会话新鲜度。
class SspAuthLocalDataSource {
  final Box<String> _box;

  SspAuthLocalDataSource(this._box);

  static String _sessionKey(String account) => 'ssp_$account';
  static String _timeKey(String account) => 'ssp_ts_$account';

  /// 读取指定账户已持久化的 JSESSIONID；未保存时返回 null。
  String? getSessionId(String account) => _box.get(_sessionKey(account));

  /// 该账户 JSESSIONID 最近一次获取/刷新时间；未保存时返回 null。
  DateTime? getUpdatedAt(String account) {
    final millis = int.tryParse(_box.get(_timeKey(account)) ?? '');
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// 保存会话 ID 并记录当前时间。
  Future<void> saveSessionId(String account, String sessionId) async {
    await _box.put(_sessionKey(account), sessionId);
    await _box.put(
      _timeKey(account),
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  /// 清除指定账户的会话记录。
  Future<void> clearSessionId(String account) async {
    await _box.delete(_sessionKey(account));
    await _box.delete(_timeKey(account));
  }
}
