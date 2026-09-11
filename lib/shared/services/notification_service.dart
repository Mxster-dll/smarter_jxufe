import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'package:smarter_jxufe/shared/services/android_notification_service.dart';
import 'package:smarter_jxufe/shared/services/windows_notification_service.dart';

/// 系统通知服务接口。
abstract class NotificationService {
  /// 初始化通知服务。
  Future<void> init();

  /// 显示成绩变更通知。
  /// [addedNames] 新增课程名，[removedNames] 撤回课程名。
  void showGradeChanges({
    required List<String> addedNames,
    required List<String> removedNames,
  });

  /// 显示/更新「上课中 · 下一节课」实况窗（常驻倒计时通知）。
  ///
  /// [countdownTo] 是系统计时器的目标时刻：Android 侧用 `usesChronometer`
  /// 让**系统自己走秒**，App 不必常驻、也不必反复刷新，这与鸿蒙实况窗
  /// 「计时型胶囊由系统推进」是同一思路。
  ///
  /// [elapsedMinutes]/[totalMinutes] 供进度条使用；`totalMinutes <= 0` 时不显示进度。
  /// 同一节课复用固定通知 id，重复调用即**原地更新**，不会重复提醒。
  void showLiveClass({
    required String title,
    required String body,
    required DateTime countdownTo,
    int elapsedMinutes = 0,
    int totalMinutes = 0,
  });

  /// 撤销实况窗（今日无课或用户关闭时调用）。
  void cancelLiveClass();

  /// 根据当前平台获取实例。
  static NotificationService get instance {
    if (_instance != null) return _instance!;
    if (Platform.isAndroid) {
      debugPrint('📱 通知平台: Android');
      _instance = AndroidNotificationService();
    } else if (Platform.isWindows) {
      debugPrint('🪟 通知平台: Windows');
      _instance = WindowsNotificationService();
    } else {
      debugPrint('⚠ 通知平台: 不支持 (${Platform.operatingSystem})');
      _instance = _NoopNotificationService();
    }
    return _instance!;
  }

  static NotificationService? _instance;
}

/// 不支持平台的空实现。
class _NoopNotificationService extends NotificationService {
  @override
  Future<void> init() async {}

  @override
  void showGradeChanges({
    required List<String> addedNames,
    required List<String> removedNames,
  }) {}

  @override
  void showLiveClass({
    required String title,
    required String body,
    required DateTime countdownTo,
    int elapsedMinutes = 0,
    int totalMinutes = 0,
  }) {}

  @override
  void cancelLiveClass() {}
}
