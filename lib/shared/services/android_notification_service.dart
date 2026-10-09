import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:smarter_jxufe/shared/services/notification_service.dart';

class AndroidNotificationService extends NotificationService {
  /// 实况窗通知通道 id。
  static const liveClassChannelId = 'live_class';

  /// 截止提醒通知通道 id。
  static const reminderChannelId = 'deadline_reminders';

  /// 课前提醒（常驻）通知通道 id。
  ///
  /// 与实况窗分开：实况窗是「安静走秒」的低优先级常驻，课前提醒要**响一次**，
  /// 用户也可以单独关掉其中一条通道。
  static const classStartChannelId = 'class_start';

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

  @override
  Future<bool> scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    bool ongoing = false,
    Duration? autoDismissAfter,
    bool countdown = false,
    bool preferExact = false,
  }) async {
    if (!_ready || _plugin == null) return false;
    // 已过去的时刻不排：AlarmManager 会立刻弹出（Windows 侧则会抛异常）。
    if (!when.isAfter(DateTime.now())) return false;

    final details = NotificationDetails(
      android: ongoing
          ? _ongoingDetails(
              when: when,
              autoDismissAfter: autoDismissAfter,
              countdown: countdown,
            )
          : const AndroidNotificationDetails(
              reminderChannelId,
              '截止提醒',
              channelDescription: '网课 / 作业 / 考试截止前的提醒',
              importance: Importance.high,
              priority: Priority.high,
            ),
      iOS: const DarwinNotificationDetails(),
    );

    // 逐档降级（最可靠 → 次之 → 兜底），理由见 [_scheduleModes]。
    final modes = await _scheduleModes(preferExact: preferExact);
    for (var i = 0; i < modes.length; i++) {
      final mode = modes[i];
      try {
        await _zonedSchedule(
          id: id,
          title: title,
          body: body,
          when: when,
          payload: payload,
          details: details,
          mode: mode,
        );
        if (i > 0) {
          debugPrint('🔔 定时通知 #$id 已降级为 $mode（${modes.first} 不可用）');
        }
        return true;
      } catch (e) {
        final last = i == modes.length - 1;
        if (last) {
          debugPrint('Android 定时通知排期失败（已试遍 ${modes.length} 档）: $e');
        } else {
          debugPrint('Android 定时通知 $mode 档失败，继续降级: $e');
        }
      }
    }
    return false;
  }

  /// 真正调插件排一条（所有降级档共用同一份参数）。
  Future<void> _zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required NotificationDetails details,
    required AndroidScheduleMode mode,
    String? payload,
  }) => _plugin!.zonedSchedule(
    id: id,
    title: title,
    body: body,
    payload: payload,
    // 用 **UTC Location** 承载绝对时刻：不依赖设备时区名，
    // 因此无需 flutter_timezone / setLocalLocation（`tz.UTC` 也无需载时区库）。
    scheduledDate: tz.TZDateTime.from(when.toUtc(), tz.UTC),
    notificationDetails: details,
    androidScheduleMode: mode,
  );

  /// 课前提醒的常驻通知详情（用户 2026-09-22 需求）。
  ///
  /// 形态：开课时**响一次**（importance high）→ 之后安静常驻（`onlyAlertOnce`）
  /// → 到上课那一刻由系统按 [autoDismissAfter] 自动撤下，不需要 App 再排一条撤销。
  AndroidNotificationDetails _ongoingDetails({
    required DateTime when,
    Duration? autoDismissAfter,
    required bool countdown,
  }) => AndroidNotificationDetails(
    classStartChannelId,
    '上课提醒',
    channelDescription: '上课前提醒：下节课的课程名与教室（上课时自动消失）',
    importance: Importance.high,
    priority: Priority.high,
    ongoing: true,
    autoCancel: false,
    onlyAlertOnce: true,
    showWhen: true,
    when: when.millisecondsSinceEpoch,
    usesChronometer: countdown,
    chronometerCountDown: countdown,
    // 到点自动撤下（Android `Notification.Builder.setTimeoutAfter`）。
    timeoutAfter: autoDismissAfter?.inMilliseconds,
    category: AndroidNotificationCategory.reminder,
  );

  /// 排期档位（**从最可靠到兜底，逐档降级**）。
  ///
  /// ⚠ 2026-10-08 真机教训（华为 / 荣耀 / HarmonyOS）：课前提醒在**应用被从最近任务
  /// 划掉后完全不触发**。华为官方支持文档（第三方闹钟类应用一节）写明「应用不被允许
  /// 后台运行、或被从后台清理时，它不会排定闹钟」，解法是用户在系统里允许自启动 /
  /// 关联启动 / 后台活动。
  ///
  /// 代码侧能做的就是**换一种闹钟注册方式**：`setExactAndAllowWhileIdle` 是普通
  /// 精确闹钟（`AlarmManager` 的通用档，国产 ROM 的省电策略会把它连同应用一起冻结），
  /// 而 `AndroidScheduleMode.alarmClock` 走 `AlarmManager.setAlarmClock()`
  /// ——**系统闹钟档**：状态栏会出现一个闹钟图标、系统把它当「用户看得见的闹钟」对待，
  /// 是各 ROM 最不敢丢的一类（丢了用户真的会起不来床）。代价就是这个图标。
  ///
  /// 拿不到精确闹钟授权（Android 12+ 需系统设置授权，14 起默认拒绝）时，
  /// `setAlarmClock` 会抛 `ExactAlarmPermissionException` → 自动落到 `exactAllowWhileIdle`
  /// → 再不行落 `inexactAllowWhileIdle`，**绝不因为一档失败就整条不排**。
  Future<List<AndroidScheduleMode>> _scheduleModes({
    required bool preferExact,
  }) async {
    if (!preferExact) return const [AndroidScheduleMode.inexactAllowWhileIdle];
    if (await _canScheduleExact()) {
      return const [
        AndroidScheduleMode.alarmClock,
        AndroidScheduleMode.exactAllowWhileIdle,
      ];
    }
    return const [AndroidScheduleMode.inexactAllowWhileIdle];
  }

  /// 能不能排精确闹钟（拿不到授权 / 查询抛异常都算不能）。
  Future<bool> _canScheduleExact() async {
    try {
      final android = _plugin
          ?.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.canScheduleExactNotifications() == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> cancelScheduled(Iterable<int> ids) async {
    if (!_ready || _plugin == null) return;
    for (final id in ids) {
      try {
        await _plugin!.cancel(id: id);
      } catch (e) {
        debugPrint('Android 撤销定时通知 #$id 失败: $e');
      }
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
    } catch (e) {
      debugPrint('Android 查询已排定通知失败: $e');
      return const [];
    }
  }
}
