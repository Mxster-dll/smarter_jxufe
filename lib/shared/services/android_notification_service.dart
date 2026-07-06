import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:smarter_jxufe/shared/services/notification_service.dart';

class AndroidNotificationService extends NotificationService {
  FlutterLocalNotificationsPlugin? _plugin;
  bool _ready = false;

  @override
  Future<void> init() async {
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: ios),
      );
      _plugin = plugin;

      // Android 13+ 运行时请求通知权限
      final androidImpl = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidImpl?.requestNotificationsPermission();

      _ready = true;
      debugPrint('✅ Android 通知已就绪');
    } catch (e) {
      debugPrint('⚠ Android 通知初始化失败: $e');
      _ready = false;
    }
  }

  @override
  void showGradeChanges({
    required List<String> addedNames,
    required List<String> removedNames,
  }) {
    if (!_ready || _plugin == null) {
      debugPrint('Android 通知未就绪');
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
          android: AndroidNotificationDetails(
            'grades_changes',
            '成绩变动',
            channelDescription: '成绩增加或撤回时通知',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
      debugPrint('📬 已发送成绩通知');
    } catch (e) {
      debugPrint('Android 通知发送失败: $e');
    }
  }
}
