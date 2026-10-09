import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'package:smarter_jxufe/shared/services/android_notification_service.dart';
// ⚠ `windows_notification_service.dart` 的 import **刻意去掉**了：桌面端不再实例化它
// （原因见下面 `instance` 里的长注释与 AGENTS.md §1.3）。要恢复桌面通知就把这行加回来。

/// 已排定的**定时**通知（对账用，见 `scheduleAt`）。
@immutable
class ScheduledNotificationInfo {
  const ScheduledNotificationInfo({required this.id, this.payload});

  /// 通知 id。
  final int id;

  /// 排期时写入的负载（截止提醒写的是触发时刻的 epoch 毫秒）。
  final String? payload;
}

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

  /// 排定一条**定时**通知（绝对时刻 [when]）。
  ///
  /// 返回是否真的排上：服务未就绪 / 平台不支持 / 时刻已过 → `false`。
  /// [payload] 供 `pendingScheduled()` 对账（截止提醒写触发时刻的 epoch 毫秒）。
  ///
  /// 四个可选形态参数默认全部关闭，既有调用方行为不变：
  /// - [ongoing]：常驻（Android `ongoing: true` + `autoCancel: false`，用户划不掉）；
  /// - [autoDismissAfter]：常驻 [autoDismissAfter] 之后由**系统**自动撤下
  ///   （Android `timeoutAfter`）—— 课前提醒靠它实现「上课那一刻自动消失」；
  /// - [countdown]：用系统计时器走秒（Android `usesChronometer`，[when] 即目标时刻）；
  /// - [preferExact]：尽量用精确闹钟（Android 12+ 需要系统授权，拿不到就退回
  ///   非精确 —— 见 `AndroidNotificationService`）。Android 侧优先用
  ///   **系统闹钟档**（`setAlarmClock`，抗国产 ROM 省电策略），失败逐档降级。
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
  }) async => false;

  /// 撤销若干条定时通知（id 不存在时静默）。
  Future<void> cancelScheduled(Iterable<int> ids) async {}

  /// 当前已排定的定时通知（对账用；未就绪 / 失败返回空表）。
  Future<List<ScheduledNotificationInfo>> pendingScheduled() async => const [];

  /// 根据当前平台获取实例。
  static NotificationService get instance {
    if (_instance != null) return _instance!;
    if (Platform.isAndroid) {
      debugPrint('📱 通知平台: Android');
      _instance = AndroidNotificationService();
    } else if (Platform.isWindows) {
      // ⚠ 2026-10-07 实测（本机 Windows 11 25H2）：**桌面端不能碰
      // `flutter_local_notifications_windows` 的原生初始化** ——
      // 一调 `FlutterLocalNotificationsPlugin.initialize(windows: …)`，进程就原生
      // `abort()`（弹 `Microsoft Visual C++ Runtime Library — Debug Error!
      // abort() has been called`），窗口永远不出现，Dart 侧还**接不住**
      // （`abort()` 杀进程，不是异常，try/catch 无效）。
      //
      // 定位方式（可复现）：用一个「只画一行字」的探针入口替换 `main`，逐项二分 ——
      // 跳过这一步 → 2 秒出窗口；加上这一步 → 立刻 abort；引擎 / pdfium / Hive /
      // 主题 / 首页全部无关。同一台机器上该进程连 `%TEMP%` 建目录都被拒
      // （`PathAccessException … errno = 5`，而此时 `%TEMP%` 的 ACL 是干净的
      // 继承 FullControl），推测是安全软件 / 远程桌面限制了新生成 exe 的注册表
      // 与临时目录写入，插件注册 COM activator 失败后原生侧不处理 → `std::terminate`。
      //
      // 所以桌面端退回**空实现**：桌面本来也不需要系统通知（课前提醒只跑 Android，
      // Windows 通知一直是「开发期验证」性质，见 §35）。要恢复：把下面这行换成
      // `_instance = WindowsNotificationService();`（并把上面的 import 加回来），
      // **先在能正常注册 COM 的机器上验证**，别再让启动被它拖死。
      debugPrint('🪟 通知平台: Windows（桌面通知已停用，避免启动 abort · 见 AGENTS.md §1.3）');
      _instance = _NoopNotificationService();
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
