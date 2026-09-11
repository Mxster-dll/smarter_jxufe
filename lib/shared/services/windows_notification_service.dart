import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:smarter_jxufe/shared/services/notification_service.dart';

class WindowsNotificationService extends NotificationService {
  FlutterLocalNotificationsPlugin? _plugin;
  bool _ready = false;

  @override
  Future<void> init() async {
    try {
      const windows = WindowsInitializationSettings(
        appName: '智慧尼采',
        appUserModelId: 'com.example.smarter_jxufe',
        guid: 'e8f3a2b1-6c4d-5e7f-8a9b-0c1d2e3f4a5b',
      );
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(windows: windows),
      );
      _plugin = plugin;
      _ready = true;
      debugPrint('✅ Windows 通知已就绪');
    } catch (e) {
      debugPrint('⚠ Windows 通知初始化失败');
      _ready = false;
    }
  }

  @override
  void showGradeChanges({
    required List<String> addedNames,
    required List<String> removedNames,
  }) {
    if (!_ready || _plugin == null) {
      debugPrint('Windows 通知未就绪');
      return;
    }

    final messages = <String>[];
    for (final name in addedNames) {
      messages.add('$name 出成绩了');
    }
    for (final name in removedNames) {
      messages.add('$name 成绩已撤回');
    }
    if (messages.isEmpty) return;

    try {
      _plugin!.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: '成绩更新',
        body: messages.join('；'),
        notificationDetails: const NotificationDetails(
          windows: WindowsNotificationDetails(),
        ),
      );
    } catch (_) {}
  }

  /// Windows 通知不支持常驻/进度/计时器，实况窗在桌面端为**空操作**。
  ///
  /// 桌面端仅用于开发期验证界面与状态机（`flutter run -d windows`），
  /// 实况窗的真实形态需在 Android 设备上验证。
  @override
  void showLiveClass({
    required String title,
    required String body,
    required DateTime countdownTo,
    int elapsedMinutes = 0,
    int totalMinutes = 0,
  }) {
    debugPrint('🪟 Windows 不支持实况窗（$title · $body）');
  }

  @override
  void cancelLiveClass() {}
}
