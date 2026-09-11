/// 入馆教育答题模式偏好（全局设置页维护，业务页面只读）。
///
/// 用户 2026-09-11 裁定：「公共模式 / 后门模式的切换不应该显示在任何页面，
/// 只能显示在设置页」。故模式是**账号无关的全局偏好**，持久化在 Hive
/// `tsgxsPrefs` box 的单 key `answerMode`（存 [TsgxsAnswerMode.name]）。
///
/// 与校历 / 校区偏好同构：`ChangeNotifier` + `ChangeNotifierProvider`，
/// 页面读同一个控制器实例 → 设置页一改，答题页下一帧即生效
/// （不用 `FutureProvider`：中间有异步空窗，页面会先闪一次旧模式）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_exam.dart';

/// 偏好 box 名。
const String tsgxsPrefsBoxName = 'tsgxsPrefs';

/// 答题模式 key。
const String tsgxsAnswerModeKey = 'answerMode';

/// 入馆教育偏好存储（落盘尽力而为：Hive 打不开也不影响本次会话）。
class TsgxsExamPrefsStore extends ChangeNotifier {
  TsgxsAnswerMode _mode = TsgxsAnswerMode.normal;
  Box<String>? _box;
  Future<void>? _loading;

  /// 当前答题模式（默认公共模式）。
  TsgxsAnswerMode get mode => _mode;

  /// 是否后门模式（便捷判断）。
  bool get isBackdoor => _mode == TsgxsAnswerMode.backdoor;

  /// 懒加载偏好（多次调用只跑一次）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final box = await _openBoxQuietly();
    if (box == null) return;
    _box = box;
    final parsed = TsgxsAnswerMode.fromName(box.get(tsgxsAnswerModeKey));
    if (parsed != null && parsed != _mode) {
      _mode = parsed;
      notifyListeners();
    }
  }

  /// 切换并落盘。
  Future<void> save(TsgxsAnswerMode next) async {
    if (next == _mode) return;
    _mode = next;
    notifyListeners();
    final box = _box ?? await _openBoxQuietly();
    if (box == null) return;
    _box = box;
    try {
      await box.put(tsgxsAnswerModeKey, next.name);
    } catch (_) {
      // 落盘失败仅本次生效。
    }
  }
}

/// 安静地打开偏好 box：Hive 不可用（未初始化，如 widget 测试）时返回 null。
///
/// 为什么需要 [runZonedGuarded]：Hive 2.2.3 的 `HiveImpl._openBox`（`hive_impl.dart:92/101/118`）
/// 先建内部 completer，随后在 `rethrow` **之前**对它调 `completeError`，而那条 future
/// 无人监听 → 变成 **zone 级未处理异常**（widget 测试会直接判失败，生产环境则是噪音日志）。
/// 真正的失败仍由 try/catch 兜住，调用方拿默认值继续。
Future<Box<String>?> _openBoxQuietly() async {
  Box<String>? box;
  try {
    await runZonedGuarded<Future<void>>(
      () async {
        box = await Hive.openBox<String>(tsgxsPrefsBoxName);
      },
      (_, _) {
        // 吞掉上面那条副作用异常；结果由 box 是否为 null 表达。
      },
    );
  } catch (_) {
    return null;
  }
  return box;
}

/// 入馆教育偏好控制器（设置页写入、答题页读取）。
final tsgxsExamPrefsProvider = ChangeNotifierProvider<TsgxsExamPrefsStore>((
  ref,
) {
  final store = TsgxsExamPrefsStore();
  unawaited(store.ensureLoaded());
  return store;
});
