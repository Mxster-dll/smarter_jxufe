import 'package:hive_flutter/hive_flutter.dart';

class AuthLocalDataSource {
  final Box<String> _box;

  AuthLocalDataSource(this._box);

  Future<void> saveTgc(String tgc) => _box.put('tgc', tgc);
  String? getTgc() => _box.get('tgc');
  Future<void> deleteTgc() => _box.delete('tgc');

  /// 缓存登录凭据（用于 TGC 过期后自动重登）。
  Future<void> saveCachedCredentials(String username, String password) async {
    await _box.put('cachedUser', username);
    await _box.put('cachedPass', password);
  }

  /// 读取缓存的登录凭据。
  (String? username, String? password) getCachedCredentials() {
    return (_box.get('cachedUser'), _box.get('cachedPass'));
  }
}
