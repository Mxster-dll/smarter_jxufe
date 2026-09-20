/// 学习通快照的 Hive 缓存（**按账号隔离**）。
///
/// 口径照 `libsp_local_store` / `GeStore`：
/// - box 名 `<base>_<账号>`（`openAccountScopedBox`，未登录时 `chaoxing__none`），
///   切账号不会读到别人的数据；
/// - `Box<String>` 单 key 存整表 JSON；
/// - **任何异常都不抛** —— 缓存坏了当「没缓存」处理，界面自己会重新取数。
///
/// ⚠ 这里**只缓存业务数据**（课程 / 作业 / 通知），**不缓存会话 Cookie**：
/// 会话是凭据，重建只要 4 个请求（`auth.hive` 里的 TGC 还在），
/// 落盘反而多一处泄露面。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/storage/account_scoped_box.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_snapshot.dart';

/// 账号级 box 的基名（实际 box 名 = `chaoxing_<账号>`）。
const String kChaoxingBoxName = 'chaoxing';

/// 整表 JSON 的 key。
const String kChaoxingSnapshotKey = 'snapshot';

/// 学习通快照存储。
class ChaoxingStore {
  const ChaoxingStore(this._box);

  final Box<String> _box;

  /// 读缓存；无缓存/损坏 → null。
  Future<ChaoxingSnapshot?> load() async {
    try {
      final raw = _box.get(kChaoxingSnapshotKey);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return ChaoxingSnapshot.fromJson(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
    } catch (e) {
      debugPrint('[chaoxing] 读快照缓存失败：$e');
      return null;
    }
  }

  /// 写缓存；失败只记日志（不阻塞界面）。
  Future<void> save(ChaoxingSnapshot snapshot) async {
    try {
      await _box.put(
        kChaoxingSnapshotKey,
        jsonEncode(snapshot.toJson()),
      );
    } catch (e) {
      debugPrint('[chaoxing] 写快照缓存失败：$e');
    }
  }

  /// 清缓存（「清除本机学习通数据」用）。
  Future<void> clear() async {
    try {
      await _box.delete(kChaoxingSnapshotKey);
    } catch (e) {
      debugPrint('[chaoxing] 清快照缓存失败：$e');
    }
  }

  /// 打开当前账号的 box（账号未定 → `chaoxing__none`）。
  static Future<ChaoxingStore> open(String? account) async =>
      ChaoxingStore(await openAccountScopedBox(kChaoxingBoxName, account));
}
