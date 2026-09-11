import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// 统一登录（CAS）的本机存储。
///
/// **一切与账号相关的值都按账号分键**（口径与 IMS 会话 `JSESSIONID|<账号>`
/// 一致）：TGC、缓存凭据都是「一个账号一份」，切换账号不会互相覆盖 ——
/// 这是「切回来 / 重启应用都不用重新登录」的前提。
///
/// 历史版本用无账号单键（`tgc` / `cachedUser` / `cachedPass`），第二个账号
/// 一登录就把前一个账号的 TGC 冲掉；旧键由 [claimLegacyCredentials] 一次性
/// 认领给**它真正属于的那个账号**（旧 `cachedUser` 记着账号）。
class AuthLocalDataSource {
  final Box<String> _box;

  /// 「信任此设备」标记（JSON: `{学号: true}`）。
  ///
  /// CAS 以免二次验证放行已信任的 `fpVisitorId`，而信任只在登录表单里
  /// 由 `trustAgent=true` 登记。自动重登没有用户在场，只能靠这份记忆
  /// 决定是否继续携带该标记，否则每次重登都要重新扫码/验证码。
  static const _keyTrustDevices = 'trustDevices';

  /// 账号级键前缀。
  static const tgcPrefix = 'TGC|';
  static const cachedUserPrefix = 'CACHEDUSER|';
  static const cachedPassPrefix = 'CACHEDPASS|';

  /// 历史无账号单键（迁移用：认领后即删除）。
  static const legacyTgcKey = 'tgc';
  static const legacyCachedUserKey = 'cachedUser';
  static const legacyCachedPassKey = 'cachedPass';

  AuthLocalDataSource(this._box);

  static String tgcKey(String account) => '$tgcPrefix$account';
  static String cachedUserKey(String account) => '$cachedUserPrefix$account';
  static String cachedPassKey(String account) => '$cachedPassPrefix$account';

  /// 保存该账号的 TGC。
  Future<void> saveTgc(String account, String tgc) =>
      _box.put(tgcKey(account), tgc);

  /// 读取该账号的 TGC（未登录 / 无记录 → null）。
  String? getTgc(String account) =>
      account.isEmpty ? null : _box.get(tgcKey(account));

  /// 删除该账号的 TGC（退出登录 / 注销账号）。
  Future<void> deleteTgc(String account) => _box.delete(tgcKey(account));

  /// 缓存该账号的登录凭据（用于 TGC 过期后自动重登）。
  Future<void> saveCachedCredentials(String account, String password) async {
    await _box.put(cachedUserKey(account), account);
    await _box.put(cachedPassKey(account), password);
  }

  /// 读取该账号缓存的登录凭据（未缓存 → `(null, null)`）。
  (String? username, String? password) getCachedCredentials(String account) {
    if (account.isEmpty) return (null, null);
    return (_box.get(cachedUserKey(account)), _box.get(cachedPassKey(account)));
  }

  /// 把历史无账号单键认领给 [account]（幂等；只认领一次）。
  ///
  /// 归属可精确判定：旧 `cachedUser` 里就记着账号，因此只有
  /// `cachedUser == account` 时才认领 —— 其余账号不动旧键，
  /// 避免把别人的 TGC / 凭据张冠李戴地算到自己头上。
  /// 旧 `cachedUser` 为空（无线索）时**不认领**。
  Future<void> claimLegacyCredentials(String account) async {
    if (account.isEmpty) return;
    final legacyUser = _box.get(legacyCachedUserKey);
    if (legacyUser == null || legacyUser != account) return;

    final legacyPass = _box.get(legacyCachedPassKey);
    if (legacyPass != null && _box.get(cachedPassKey(account)) == null) {
      await _box.put(cachedPassKey(account), legacyPass);
    }
    if (_box.get(cachedUserKey(account)) == null) {
      await _box.put(cachedUserKey(account), legacyUser);
    }
    final legacyTgc = _box.get(legacyTgcKey);
    if (legacyTgc != null && _box.get(tgcKey(account)) == null) {
      await _box.put(tgcKey(account), legacyTgc);
    }
    // 认领即清旧键：否则下一个账号还会再认领一次同一份 TGC。
    await _box.delete(legacyCachedUserKey);
    await _box.delete(legacyCachedPassKey);
    await _box.delete(legacyTgcKey);
  }

  /// 读取全部「信任此设备」标记（容错：损坏则视为空）。
  Map<String, bool> getTrustDevices() {
    final raw = _box.get(_keyTrustDevices);
    if (raw == null || raw.isEmpty) return <String, bool>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, bool>{};
      return {
        for (final entry in decoded.entries)
          if (entry.value == true) entry.key.toString(): true,
      };
    } catch (_) {
      return <String, bool>{};
    }
  }

  /// 该账号是否已登记「信任此设备」。
  bool isTrustDevice(String username) => getTrustDevices()[username] == true;

  /// 记录 / 取消该账号的「信任此设备」。
  Future<void> saveTrustDevice(String username, bool trusted) async {
    final devices = getTrustDevices();
    if (trusted) {
      devices[username] = true;
    } else {
      devices.remove(username);
    }
    await _box.put(_keyTrustDevices, jsonEncode(devices));
  }
}
