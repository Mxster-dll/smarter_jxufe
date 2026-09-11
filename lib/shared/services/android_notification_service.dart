import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:smarter_jxufe/shared/services/notification_service.dart';

class AndroidNotificationService extends NotificationService {
  /// 实况窗通知通道 id。
  static const liveClassChannelId = 'live_class';

  /// 实况窗固定通知 id —— 复用同一 id 即可原地更新同一条通知。
  static const liveClassNotificationId = 8801;

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

  @override
  void showLiveClass({
    required String title,
    required String body,
    required DateTime countdownTo,
    int elapsedMinutes = 0,
    int totalMinutes = 0,
  }) {
    if (!_ready || _plugin == null) {
      debugPrint('Android 通知未就绪，跳过实况窗');
      return;
    }

    try {
      _plugin!.show(
        id: liveClassNotificationId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            liveClassChannelId,
            '上课实况',
            channelDescription: '上课中 / 下一节课的常驻倒计时',
            // 静默常驻：不响铃、不出横幅，只在通知栏与锁屏上安静地走秒
            importance: Importance.low,
            priority: Priority.low,
            silent: true,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            // 系统计时器：countdownTo 之前由系统自己走秒，App 无需刷新
            showWhen: true,
            when: countdownTo.millisecondsSinceEpoch,
            usesChronometer: true,
            chronometerCountDown: true,
            // 进度条：一节课走了多少
            showProgress: totalMinutes > 0,
            maxProgress: totalMinutes > 0 ? totalMinutes : 0,
            progress: elapsedMinutes.clamp(0, totalMinutes > 0 ? totalMinutes : 0),
            category: AndroidNotificationCategory.progress,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Android 实况窗发送失败: $e');
    }
  }

  @override
  void cancelLiveClass() {
    if (!_ready || _plugin == null) return;
    try {
      _plugin!.cancel(id: liveClassNotificationId);
    } catch (e) {
      debugPrint('Android 实况窗取消失败: $e');
    }
  }
}
