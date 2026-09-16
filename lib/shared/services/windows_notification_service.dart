import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:smarter_jxufe/shared/services/notification_service.dart';

class WindowsNotificationService extends NotificationService {
  FlutterLocalNotificationsPlugin? _plugin;
  bool _ready = false;

  @override
  Future<void> init() async {
    try {
      const windows = WindowsInitializationSettings(
        appName: '智慧er江财',
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

  /// 排定一条定时通知。
  ///
  /// ⚠ Windows 的定时通知由系统 toast 调度器投递，**App 未运行时能否触发取决于
  /// 应用是否已注册快捷方式**（本工程的 `WindowsInitializationSettings` 已给
  /// appUserModelId + guid）；桌面端主要用于开发期验证，真机提醒以 Android 为准。
  @override
  Future<bool> scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (!_ready || _plugin == null) return false;
    // 插件对「过去的时刻」直接抛 ArgumentError，这里先挡住。
    if (!when.isAfter(DateTime.now())) return false;
    try {
      await _plugin!.zonedSchedule(
        id: id,
        title: title,
        body: body,
        payload: payload,
        scheduledDate: tz.TZDateTime.from(when.toUtc(), tz.UTC),
        notificationDetails: const NotificationDetails(
          windows: WindowsNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return true;
    } catch (e) {
      debugPrint('🪟 Windows 定时通知排期失败: $e');
      return false;
    }
  }

  @override
  Future<void> cancelScheduled(Iterable<int> ids) async {
    if (!_ready || _plugin == null) return;
    for (final id in ids) {
      try {
        await _plugin!.cancel(id: id);
      } catch (_) {}
    }
  }

  @override
  Future<List<ScheduledNotificationInfo>> pendingScheduled() async {
    if (!_ready || _plugin == null) return const [];
    try {
      final list = await _plugin!.pendingNotificationRequests();
      return [
        for (final p in list)
          ScheduledNotificationInfo(id: p.id, payload: p.payload),
      ];
    } catch (_) {
      return const [];
    }
  }
}
