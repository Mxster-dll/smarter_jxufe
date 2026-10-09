import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 原生桥返回的「最终打开了哪个系统设置页」。
///
/// 取值与 `AppSettingsBridge.kt` 里的 `PAGE_*` 常量逐字一致。
class AppSettingsPage {
  AppSettingsPage._();

  /// 品牌「应用启动管理 / 自启动管理」页（华为 `startupmgr` / 小米自启动）。
  static const String startup = 'startup';

  /// 应用详情页（`ACTION_APPLICATION_DETAILS_SETTINGS`，任何 Android 都有）。
  static const String appDetails = 'app_details';

  /// 电池优化设置列表页。
  static const String battery = 'battery';

  /// 一个候选都没打开（用户会停在原页面）。
  static const String none = 'none';
}

/// 一次「打开系统设置页」的结果。
@immutable
class AppSettingsResult {
  const AppSettingsResult({
    required this.opened,
    this.page = AppSettingsPage.none,
    this.message,
  });

  /// 是否真的打开了某个系统页面。
  final bool opened;

  /// 打开的是哪个页面（[AppSettingsPage] 里的常量）。
  final String page;

  /// 需要向用户显示的说明（原生侧给；缺失时按 [page] 兜底）。
  final String? message;

  /// 直接上屏用的一句话。
  String get label {
    final text = message?.trim();
    if (text != null && text.isNotEmpty) return text;
    return switch (page) {
      AppSettingsPage.startup => '已打开「应用启动管理」，请允许自启动与后台活动',
      AppSettingsPage.appDetails => '已打开应用详情页，请在权限 / 电池里允许后台运行',
      AppSettingsPage.battery => '已打开电池优化设置，请把本应用设为「不优化」',
      _ => '没能打开系统设置，请手动到「设置 → 应用 → 应用启动管理」里允许自启动',
    };
  }

  @override
  String toString() => 'AppSettingsResult(opened: $opened, page: $page)';
}

/// 「应用后台保护设置」桥（`smarter_jxufe/app_settings`）。
///
/// 为什么需要它（2026-10-08）：课前提醒在**华为 / 荣耀上、应用被从最近任务划掉后
/// 不触发**。这是系统级限制：华为官方支持文档（第三方闹钟类应用一节）写明
/// 「应用不被允许后台运行、或被从后台清理时，它不会排定闹钟」，解法是用户在系统里
/// 允许**自启动 / 关联启动 / 后台活动**，并在最近任务里下拉锁定该应用。
/// 第三方应用**没有任何 API 能自己改这些开关**，只能把用户送到那个设置页 ——
/// 本文件就是那个「送过去」的动作。
///
/// 候选顺序（全部在原生侧完成，逐条 `resolveActivity` 失败即换下一条，**不判断 ROM 品牌**）：
/// 华为 / 荣耀启动管理 → 小米自启动管理 → 品牌私有 action → 应用详情页 → 电池优化列表。
///
/// 非 Android 平台（Windows 桌面端）没有这些页面：直接返回未打开，由调用方给文字步骤。
class AppSettingsGuide {
  AppSettingsGuide._();

  /// 原生桥通道名（与 `AppSettingsBridge.kt` 的 `CHANNEL` 必须一致）。
  static const MethodChannel channel = MethodChannel(
    'smarter_jxufe/app_settings',
  );

  static const Duration _timeout = Duration(seconds: 8);

  /// 当前平台是否有这套系统设置页（与 `FileShare.isSupported` 同口径）。
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 打开「允许应用自启动 / 后台运行」的设置页。
  ///
  /// [allowAppDetailsFallback]：原生候选全部失败时，再用
  /// `ACTION_APPLICATION_DETAILS_SETTINGS` 兜一次（任何 Android 都有这一页）。
  /// 单测里把它关掉，可以精确验证「原生返回 none = 未打开」这条路径。
  static Future<AppSettingsResult> openBackgroundSettings({
    bool allowAppDetailsFallback = true,
  }) async {
    if (!isSupported) {
      return const AppSettingsResult(
        opened: false,
        message: '当前平台没有这个系统设置页（课前提醒只在 Android 上排期）',
      );
    }
    var result = await _invoke('openStartupSettings');
    if (!result.opened && allowAppDetailsFallback) {
      result = await _invoke('openAppDetails');
    }
    return result;
  }

  /// 打开系统「电池优化」设置列表。
  ///
  /// 用官方设置列表页（`ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`）而不是
  /// 「直接申请忽略优化」—— 后者要 `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` 权限，
  /// Google Play 对该权限有政策限制，本项目不引这个隐患。
  static Future<AppSettingsResult> openBatterySettings() =>
      _invoke('openBatteryOptimization');

  /// 厂商名（`Build.MANUFACTURER`，如 `HUAWEI` / `Xiaomi`）；取不到返回 null。
  ///
  /// 只用来决定设置页的说明文案要不要点名品牌 —— **不用来做任何控制流判断**
  /// （能不能跳过去由原生侧逐条 `resolveActivity` 决定）。
  static Future<String?> manufacturer() async {
    if (!isSupported) return null;
    try {
      final info = await channel
          .invokeMapMethod<String, Object?>('deviceInfo')
          .timeout(_timeout);
      final name = info?['manufacturer'] as String?;
      return (name == null || name.trim().isEmpty) ? null : name.trim();
    } catch (error) {
      debugPrint('[app_settings] 读取厂商信息失败: $error');
      return null;
    }
  }

  /// 发一次原生调用并把返回值收敛成 [AppSettingsResult]（任何异常都不外抛）。
  static Future<AppSettingsResult> _invoke(String method) async {
    try {
      final page = await channel.invokeMethod<String>(method).timeout(_timeout);
      final value = (page == null || page.isEmpty)
          ? AppSettingsPage.none
          : page;
      return AppSettingsResult(
        opened: value != AppSettingsPage.none,
        page: value,
      );
    } on MissingPluginException {
      // 桌面端 / 单测环境没有这个原生实现：不是错误，如实返回未打开。
      debugPrint('[app_settings] 原生桥不存在（$method）');
      return const AppSettingsResult(opened: false);
    } catch (error) {
      debugPrint('[app_settings] 打开系统设置失败（$method）: $error');
      return const AppSettingsResult(opened: false);
    }
  }
}
