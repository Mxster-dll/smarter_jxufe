package com.example.smarter_jxufe.settings

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 「应用后台保护设置」桥（自研，零第三方依赖）。
 *
 * 背景（2026-10-08）：课前提醒在华为 / 荣耀上**应用被从最近任务划掉后不触发**。
 * 这是系统级限制，不是代码缺陷 —— 华为官方支持文档写明：「If the app is not allowed
 * to run in the background, or is cleared from the background, it will not schedule an
 * alarm.」（第三方闹钟类应用一节），解法是用户在系统里允许**自启动 / 关联启动 /
 * 后台活动**，并在最近任务里下拉锁定该应用。第三方应用**没有任何 API 能自己打开
 * 这些开关**，只能把用户送到那个设置页。
 *
 * 本桥就做一件事：**按候选顺序尝试打开「应用启动管理」，全部失败再退到应用详情页**
 * （任何 Android 都有）。
 *
 * 候选顺序按「用户少走路」排：华为 / 荣耀启动管理 → 小米自启动 → 通用应用详情页 →
 * 电池优化列表 → 应用列表。每个候选都先 `resolveActivity` 再 `startActivity`，
 * 任何异常都吞掉换下一个（**绝不允许带崩 App** —— 同小组件 / 分享桥的纪律）。
 *
 * 为什么不用 `app_settings` / `permission_handler` 之类的包：
 * 项目纪律是能用自研原生桥解决的就不加依赖（同 `FileShareBridge` / `HomeWidgetBridge`），
 * 这里只用到 Intent + Settings 常量。
 */
class AppSettingsBridge(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    companion object {
        /** 必须与 Dart 侧 `AppSettingsGuide.channel` 一致。 */
        const val CHANNEL = "smarter_jxufe/app_settings"

        private const val TAG = "AppSettingsBridge"

        // ── 返回给 Dart 的「最终打开了哪个页面」标记（与 Dart 侧常量逐字一致）──
        const val PAGE_STARTUP = "startup"
        const val PAGE_APP_DETAILS = "app_details"
        const val PAGE_BATTERY = "battery"
        const val PAGE_NONE = "none"

        /**
         * 直连候选：`包名/Activity 全名`。
         *
         * 逐个 `resolveActivity`，不存在的直接跳过 —— 因此**不需要判断 ROM 品牌**，
         * 华为机上会命中第一条，小米机上华为那两条解析不到、自动落到小米那条。
         * 这些类名在对应 ROM 上都是稳定的：① 华为/荣耀「应用启动管理」列表页
         * （`startupmgr`，即设置里「应用 - 应用启动管理」）；② 小米「自启动管理」。
         */
        private val DIRECT_CANDIDATES: List<Pair<String, String>> = listOf(
            // 华为 / 荣耀：应用启动管理（列表面板）
            "com.huawei.systemmanager" to
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            // 华为 / 荣耀：应用启动管理（异常提示版，部分 EMUI 版本只有这个）
            "com.huawei.systemmanager" to
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivityEx",
            // 小米 / 红米：自启动管理
            "com.miui.securitycenter" to
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
        )
    }

    private val appContext: Context = context.applicationContext

    /** 调起另一个应用（系统设置）必须带上 Activity 上下文或 `NEW_TASK` 标志。 */
    private val uiContext: Context = context

    private val channel: MethodChannel =
        MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openStartupSettings" -> result.success(openStartupSettings())
            "openAppDetails" -> result.success(openAppDetails())
            "requestIgnoreBatteryOptimizations" -> result.success(openBatteryOptimization())
            "deviceInfo" -> result.success(deviceInfo())
            else -> result.notImplemented()
        }
    }

    /**
     * 打开「允许应用自启动 / 后台运行」的设置页（按候选顺序尝试）。
     *
     * 返回最终打开的是哪个页面（见 [PAGE_STARTUP] 等常量）；全失败返回 [PAGE_NONE]。
     * 调用方按返回值给用户不同的提示文案。
     */
    private fun openStartupSettings(): String {
        // ① 直连具体 Activity（用户少走一层；无第三方应用可解析这些组件）
        for ((pkg, cls) in DIRECT_CANDIDATES) {
            val intent = Intent().apply {
                component = ComponentName(pkg, cls)
            }
            if (launch(intent)) return PAGE_STARTUP
        }
        // ② / ③ 品牌私有 action（靠系统包管理器找接收方，不做硬编码包名匹配）
        for (action in listOf(
            "com.huawei.systemmanager.startupmgr.action.ALLOW_STARTUP",
            "com.huawei.systemmanager.startupmgr.action.SHOW_STARTUP_APPS",
        )) {
            val intent = Intent(action).apply {
                // 少数 EMUI 版本用 extra 指定目标包名
                putExtra("packageName", appContext.packageName)
            }
            if (launch(intent)) return PAGE_STARTUP
        }
        // ④ 兜底：应用详情页（任何 Android 都有，用户可在此进「权限 / 电池」）
        return openAppDetails()
    }

    /**
     * 打开本应用的系统「应用详情」页（`ACTION_APPLICATION_DETAILS_SETTINGS`）。
     *
     * 这是唯一**所有 Android 都保证存在**的落点，也是 [openStartupSettings] 的兜底。
     */
    private fun openAppDetails(): String {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", appContext.packageName, null)
        }
        return if (launch(intent)) PAGE_APP_DETAILS else PAGE_NONE
    }

    /**
     * 打开「电池优化」设置列表。
     *
     * 刻意用 `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`（**官方设置列表页**）而不是
     * `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`：后者需要
     * `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` 权限，而 Google Play 对该权限有政策限制
     * （本项目是公开仓库 + 可能上架，不引这个隐患）；列表页用不着任何权限，
     * 用户自己在里面把本应用设为「不优化」即可。
     */
    private fun openBatteryOptimization(): String {
        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        if (launch(intent)) return PAGE_BATTERY
        // 更老的设备只有「电池用量」总览页
        if (launch(Intent(Intent.ACTION_POWER_USAGE_SUMMARY))) return PAGE_BATTERY
        return openAppDetails()
    }

    /** 设备信息（Dart 侧用来决定说明文案要不要点名品牌）。 */
    private fun deviceInfo(): Map<String, Any?> = mapOf(
        "manufacturer" to Build.MANUFACTURER,
        "brand" to Build.BRAND,
        "model" to Build.MODEL,
        "sdkInt" to Build.VERSION.SDK_INT,
    )

    /**
     * 真的把 Intent 发出去：先 `resolveActivity` 探一下，再 `startActivity`。
     *
     * 用 `uiContext`（Activity）而不是 application context —— 从 Activity 启动，
     * 目标页与设置同级返回栈，用户按返回能回到 App。`NEW_TASK` 作为保险：
     * 万一 `resolveActivity` 认了、`startActivity` 因上下文原因抛异常，也能落到下一候选。
     */
    private fun launch(intent: Intent): Boolean {
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (intent.resolveActivity(appContext.packageManager) == null) return false
            uiContext.startActivity(intent)
            Log.i(TAG, "已跳转系统设置：${intent.component ?: intent.action}")
            true
        } catch (t: Throwable) {
            // 单条候选失败不是错误（换下一个）：只在 debug 打一行，绝不抛给 Dart。
            Log.d(TAG, "跳转失败（换下一候选）：${intent.component ?: intent.action}", t)
            false
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
