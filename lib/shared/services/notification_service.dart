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
}
