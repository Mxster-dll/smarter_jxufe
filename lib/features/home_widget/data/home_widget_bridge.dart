import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:smarter_jxufe/features/home_widget/domain/home_widget_snapshot.dart';

/// Flutter ↔ 原生桌面小组件的自研数据桥（零第三方依赖）。
///
/// 通道 `smarter_jxufe/home_widget`。
///
/// Dart → 原生：
/// - `updateSnapshot`：写一份快照并刷新该指标的小组件；
/// - `setAuthSnapshot`：写后台刷新所需的最小认证快照
///   （学号 / 密码 / TGC / JSESSIONID / 房间），供后台 isolate 免 Hive 使用；
/// - `clearSnapshots`：清空全部快照（退出登录）；
/// - `readStore`：读回原生存储（后台 isolate 入口用）；
/// - `pinnedCounts`：查每个「指标:尺寸」档位在桌面上已绑定的实例数
///   （设置页徽章 + 「刚请求的那次到底落桌面没有」的检测）；
/// - `consumeLaunchRoute`：取「点小组件唤起 App」的目标路由，取后即清。
///
/// 原生 → Dart：`routeChanged`（App 已在运行时被小组件唤起）。
///
/// 非 Android（如 Windows 桌面调试）一律静默降级：所有方法返回空值，
/// 不抛异常、不影响 App 其余功能。
class HomeWidgetBridge {
  HomeWidgetBridge._();

  static const MethodChannel channel = MethodChannel(
    'smarter_jxufe/home_widget',
  );

  static const Duration _timeout = Duration(seconds: 5);

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 把一份快照推给原生并刷新小组件。返回是否成功。
  static Future<bool> updateSnapshot(HomeWidgetSnapshot snapshot) async {
    if (!isSupported) return false;
    try {
      final ok = await channel
          .invokeMethod<bool>('updateSnapshot', snapshot.toJson())
          .timeout(_timeout);
      return ok ?? false;
    } catch (e) {
      debugPrint('[home_widget] updateSnapshot 失败: $e');
      return false;
    }
  }

  /// 写后台刷新所需的认证快照（App 侧每次登录/刷新后调用）。
  static Future<void> setAuthSnapshot(Map<String, Object?> auth) async {
    if (!isSupported) return;
    try {
      await channel
          .invokeMethod<void>('setAuthSnapshot', auth)
          .timeout(_timeout);
    } catch (e) {
      debugPrint('[home_widget] setAuthSnapshot 失败: $e');
    }
  }

  /// 清空全部快照（退出登录时调用，避免桌面残留他人数据）。
  static Future<void> clearSnapshots() async {
    if (!isSupported) return;
    try {
      await channel.invokeMethod<void>('clearSnapshots').timeout(_timeout);
    } catch (e) {
      debugPrint('[home_widget] clearSnapshots 失败: $e');
    }
  }

  /// 读回原生存储的原始 JSON 串（后台 isolate 用，主 isolate 不需要）。
  static Future<Map<String, Object?>> readStore() async {
    if (!isSupported) return const {};
    try {
      final raw = await channel
          .invokeMethod<Map<Object?, Object?>>('readStore')
          .timeout(_timeout);
      if (raw == null) return const {};
      return raw.map((k, v) => MapEntry(k.toString(), v));
    } catch (e) {
      debugPrint('[home_widget] readStore 失败: $e');
      return const {};
    }
  }

  /// 取「点小组件唤起 App」的目标路由（`electricity` / `grades`），取后即清。
  static Future<String?> consumeLaunchRoute() async {
    if (!isSupported) return null;
    try {
      return await channel
          .invokeMethod<String>('consumeLaunchRoute')
          .timeout(_timeout);
    } catch (e) {
      debugPrint('[home_widget] consumeLaunchRoute 失败: $e');
      return null;
    }
  }

  /// 各「指标:尺寸」档位当前在桌面上已绑定的实例数（键 = [homeWidgetPinKey]）。
  ///
  /// 为什么不用 `requestPinAppWidget` 的第三个参数（成功回调）：**华为桌面不
  /// 会触发那个 PendingIntent**（成功也不触发），所以只能靠「已绑定实例数」
  /// 的差值判断这次请求到底落桌面没有。返回空表 = 非 Android 或查询失败。
  static Future<Map<String, int>> pinnedCounts() async {
    if (!isSupported) return const {};
    try {
      final raw = await channel
          .invokeMethod<Map<Object?, Object?>>('pinnedCounts')
          .timeout(_timeout);
      if (raw == null) return const {};
      final counts = <String, int>{};
      for (final entry in raw.entries) {
        final value = entry.value;
        counts[entry.key.toString()] = value is int ? value : 0;
      }
      return counts;
    } catch (e) {
      debugPrint('[home_widget] pinnedCounts 失败: $e');
      return const {};
    }
  }

  /// 注册原生回调：App 已在运行时被小组件唤起 → 立即跳转。
  static void installRouteHandler(Future<void> Function(String route) onRoute) {
    if (!isSupported) return;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'routeChanged') return null;
      final route = call.arguments is String ? call.arguments as String : null;
      if (route != null && route.isNotEmpty) {
        await onRoute(route);
      }
      return null;
    });
  }

  /// 通知原生：后台刷新已完成（原生据此结束 JobService 并回收 headless 引擎）。
  static Future<void> notifyBackgroundDone() async {
    if (!isSupported) return;
    try {
      await channel.invokeMethod<void>('backgroundDone').timeout(_timeout);
    } catch (e) {
      debugPrint('[home_widget] backgroundDone 上报失败: $e');
    }
  }

  /// 请求系统把某个尺寸的小组件固定到桌面（设置页「添加到桌面」）。
  ///
  /// 走 `AppWidgetManager.requestPinAppWidget`（API 26+，需桌面支持该能力）。
  /// 返回 `(supported, requested)`：
  /// - `supported == false` → 该系统/桌面不支持一键固定，调用方应引导用户
  ///   长按桌面 → 服务卡片 手动添加；
  /// - `requested == true` → 请求已提交，系统会弹确认框，用户在桌面上确认后生效。
  static Future<({bool supported, bool requested})> requestPinWidget({
    required HomeWidgetMetric metric,
    required String size,
  }) async {
    const unsupported = (supported: false, requested: false);
    if (!isSupported) return unsupported;
    try {
      final raw = await channel
          .invokeMethod<Map<Object?, Object?>>('requestPinWidget', {
            'metric': metric.key,
            'size': size,
          })
          .timeout(_timeout);
      if (raw == null) return unsupported;
      return (
        supported: raw['supported'] == true,
        requested: raw['requested'] == true,
      );
    } catch (e) {
      debugPrint('[home_widget] requestPinWidget 失败: $e');
      return unsupported;
    }
  }
}
