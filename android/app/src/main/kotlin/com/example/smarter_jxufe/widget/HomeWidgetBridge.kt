package com.example.smarter_jxufe.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import com.example.smarter_jxufe.R
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Flutter ↔ 桌面小组件的自研数据桥（零第三方依赖）。
 *
 * 通道 `smarter_jxufe/home_widget`，方法见 [onMethodCall]；
 * 反向通知（App 已在运行时被点开）走 `routeChanged`。
 */
class HomeWidgetBridge(
    private val context: Context,
    messenger: BinaryMessenger,
    /** 后台刷新引擎回调：收到 Dart 的 `backgroundDone` 后结束 JobService。 */
    private val onBackgroundDone: (() -> Unit)? = null,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "smarter_jxufe/home_widget"

        /** 点小组件唤起 App 时携带的路由 extra。 */
        const val EXTRA_ROUTE = "widget_route"

        /** 仪表盘（数据一览）指标 key，与 Dart 侧 `HomeWidgetMetric.dashboard.key` 一致。 */
        const val METRIC_DASHBOARD = "dashboard"

        /**
         * 指标 → 该指标的小组件 provider 与其尺寸档。
         *
         * 3 指标 × 8 档（2×1 / 3×1 / 4×1 / 5×1 / 2×2 / 3×2 / 4×2 / 5×2）= 24 个。
         */
        private val METRIC_PROVIDERS:
            Map<String, List<Pair<Class<out MetricWidgetProvider>, WidgetSize>>> = mapOf(
            METRIC_DASHBOARD to listOf(
                DashboardWidget2x1::class.java to WidgetSize.X2x1,
                DashboardWidget3x1::class.java to WidgetSize.X3x1,
                DashboardWidget4x1::class.java to WidgetSize.X4x1,
                DashboardWidget5x1::class.java to WidgetSize.X5x1,
                DashboardWidget2x2::class.java to WidgetSize.X2x2,
                DashboardWidget3x2::class.java to WidgetSize.X3x2,
                DashboardWidget4x2::class.java to WidgetSize.X4x2,
                DashboardWidget5x2::class.java to WidgetSize.X5x2,
            ),
            "electricity" to listOf(
                ElectricityWidget2x1::class.java to WidgetSize.X2x1,
                ElectricityWidget3x1::class.java to WidgetSize.X3x1,
                ElectricityWidget4x1::class.java to WidgetSize.X4x1,
                ElectricityWidget5x1::class.java to WidgetSize.X5x1,
                ElectricityWidget2x2::class.java to WidgetSize.X2x2,
                ElectricityWidget3x2::class.java to WidgetSize.X3x2,
                ElectricityWidget4x2::class.java to WidgetSize.X4x2,
                ElectricityWidget5x2::class.java to WidgetSize.X5x2,
            ),
            "grades" to listOf(
                GradeWidget2x1::class.java to WidgetSize.X2x1,
                GradeWidget3x1::class.java to WidgetSize.X3x1,
                GradeWidget4x1::class.java to WidgetSize.X4x1,
                GradeWidget5x1::class.java to WidgetSize.X5x1,
                GradeWidget2x2::class.java to WidgetSize.X2x2,
                GradeWidget3x2::class.java to WidgetSize.X3x2,
                GradeWidget4x2::class.java to WidgetSize.X4x2,
                GradeWidget5x2::class.java to WidgetSize.X5x2,
            ),
        )

        /**
         * 「指标:尺寸」键，与 Dart 侧 `homeWidgetPinKey(metric, size)` 一致。
         *
         * 刻意写成显式拼接（不用 Kotlin 字符串模板）：守卫测试按这段原文匹配，
         * 保证两端键格式不会各自漂移。
         */
        fun pinKey(metric: String, size: WidgetSize): String = metric + ":" + size.tag

        /**
         * 每个（指标 × 尺寸）档位当前在桌面上已绑定的实例数。
         *
         * 用途见 Dart 侧 `HomeWidgetBridge.pinnedCounts` 的注释：华为桌面不触发
         * `requestPinAppWidget` 的成功回调，只能靠这个差值判断是否真的落桌面。
         */
        fun pinnedCounts(context: Context): Map<String, Int> {
            val manager = AppWidgetManager.getInstance(context)
            val counts = HashMap<String, Int>()
            for ((metric, providers) in METRIC_PROVIDERS) {
                for ((clazz, size) in providers) {
                    val ids = manager.getAppWidgetIds(ComponentName(context, clazz))
                    counts[pinKey(metric, size)] = ids?.size ?: 0
                }
            }
            return counts
        }

        /**
         * 把 MethodChannel 传来的参数转成 JSON。
         *
         * ⚠️ 每个值都要过 [JSONObject.wrap]：Android 的 `JSONStringer` 遇到不认识的
         * 类型（如 `ArrayList<HashMap>`）会**退化成 `toString()`**，于是仪表盘的
         * `cells` 会被写成字符串 `"[{label=电费, value=120.9}]"` 而不是数组，
         * 原生 `optJSONArray("cells")` 拿不到 → 仪表盘只剩「暂无数据」。
         * （2026-09-11 实测踩过：自检与单测都过，只有落盘核对能发现。）
         */
        private fun toJson(args: Map<*, *>): JSONObject {
            val json = JSONObject()
            for ((key, value) in args) {
                if (key != null && value != null) {
                    json.put(key.toString(), JSONObject.wrap(value))
                }
            }
            return json
        }

        /**
         * 数据形状自检：模拟 Dart 侧 `updateSnapshot` 的参数，确认嵌套列表
         * 不会在落盘时退化成字符串。debug 启动时打印到 logcat。
         */
        fun shapeCheck(): String {
            val args = mapOf(
                "metric" to "dashboard",
                "cells" to listOf(
                    mapOf("label" to "电费", "value" to "120.9"),
                    mapOf("label" to "今日", "value" to "3 节"),
                ),
            )
            val json = toJson(args)
            val cells = json.optJSONArray("cells")
            val ok = cells != null &&
                cells.length() == 2 &&
                cells.optJSONObject(1)?.optString("value") == "3 节"
            return if (ok) {
                "OK（cells 为数组，2 格）"
            } else {
                "失败：cells 未按数组写入 → ${json.opt("cells")}"
            }
        }

        /**
         * 深色模式自检：把配置强制成 night 再读小组件配色，确认资源真的分了两套。
         *
         * 桌面小组件的颜色全部走 `@color`（布局在宿主进程按系统 uiMode 取值，
         * 运行时由渲染器取色），这里验证的是资源确实存在且夜间值与浅色不同 ——
         * 否则「适配深色模式」只是一句口号。debug 启动时打印到 logcat。
         */
        @Suppress("DEPRECATION")
        fun nightCheck(context: Context): String {
            fun nightContext(night: Boolean): Context {
                val base = context.resources.configuration
                return context.createConfigurationContext(
                    Configuration(base).apply {
                        uiMode = (base.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
                            if (night) {
                                Configuration.UI_MODE_NIGHT_YES
                            } else {
                                Configuration.UI_MODE_NIGHT_NO
                            }
                    },
                )
            }

            fun hex(color: Int) = String.format("#%06X", color and 0xFFFFFF)
            // 两边都显式指定，避免被「当前系统就是深色」这种情况蒙混过关。
            val day = nightContext(false)
            val night = nightContext(true)
            val dayBg = day.resources.getColor(R.color.home_widget_bg)
            val nightBg = night.resources.getColor(R.color.home_widget_bg)
            val dayText = day.resources.getColor(R.color.home_widget_text_primary)
            val nightText = night.resources.getColor(R.color.home_widget_text_primary)
            val verdict = when {
                dayBg == nightBg || dayText == nightText -> "失败：夜间配色未生效"
                else -> "OK"
            }
            return "$verdict 底色 ${hex(dayBg)}→${hex(nightBg)} · " +
                "正文 ${hex(dayText)}→${hex(nightText)} · " +
                "点缀 电费${hex(night.resources.getColor(R.color.home_widget_accent_electricity))} " +
                "成绩${hex(night.resources.getColor(R.color.home_widget_accent_grade))} " +
                "一览${hex(night.resources.getColor(R.color.home_widget_accent_dashboard))}"
        }

        /** 刷新某指标的全部桌面小组件（桌面上没有该小组件时静默返回）。 */
        fun refreshMetric(context: Context, metric: String) {
            val providers = METRIC_PROVIDERS[metric] ?: return
            val manager = AppWidgetManager.getInstance(context)
            for ((clazz, size) in providers) {
                val ids = manager.getAppWidgetIds(ComponentName(context, clazz))
                if (ids == null || ids.isEmpty()) continue
                val views = MetricWidgetRenderer.render(context, metric, size)
                for (id in ids) manager.updateAppWidget(id, views)
            }
        }

        /** 刷新全部小组件（清理快照后用）。 */
        fun refreshAll(context: Context) {
            for (metric in METRIC_PROVIDERS.keys) refreshMetric(context, metric)
        }

        /**
         * 布局自检：把每个（指标 × 尺寸）组合各渲染 + inflate 一次，返回结果串。
         *
         * 为什么要它：桌面不一定会立刻渲染小组件（没人放到桌面时 onUpdate 根本
         * 不会被调用），布局写错 / id 对不上就会一直潜伏。debug 构建启动时跑一次，
         * 结果直接进 logcat（`小组件自检: 24/24 OK`）。
         */
        fun selfCheck(context: Context): String {
            val failures = mutableListOf<String>()
            var total = 0
            for ((metric, providers) in METRIC_PROVIDERS) {
                for ((_, size) in providers) {
                    total++
                    runCatching {
                        MetricWidgetRenderer.render(context, metric, size)
                            .apply(context, null)
                    }.onFailure { failures += "$metric/${size.tag} → ${it.message}" }
                }
            }
            return if (failures.isEmpty()) {
                "$total/$total OK"
            } else {
                "${failures.size} 项失败: ${failures.joinToString("; ")}"
            }
        }
    }

    private val channel = MethodChannel(messenger, CHANNEL).also {
        it.setMethodCallHandler(this)
    }

    /** 通知 Flutter：App 已在运行，点小组件要跳到某页。 */
    fun notifyRouteChanged(route: String) {
        channel.invokeMethod("routeChanged", route)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updateSnapshot" -> {
                val args = call.arguments as? Map<*, *>
                val metric = args?.get("metric") as? String
                if (args == null || metric.isNullOrEmpty()) {
                    result.success(false)
                    return
                }
                HomeWidgetStore.writeSnapshot(context, metric, toJson(args).toString())
                refreshMetric(context, metric)
                result.success(true)
            }

            "setAuthSnapshot" -> {
                val args = call.arguments as? Map<*, *>
                if (args == null) {
                    result.success(null)
                    return
                }
                HomeWidgetStore.writeAuth(context, toJson(args).toString())
                result.success(null)
            }

            "clearSnapshots" -> {
                HomeWidgetStore.clearAll(context)
                refreshAll(context)
                result.success(null)
            }

            "readStore" -> {
                result.success(
                    mapOf(
                        "auth" to HomeWidgetStore.readAuth(context),
                        METRIC_DASHBOARD to
                            (HomeWidgetStore.readSnapshot(context, METRIC_DASHBOARD) ?: ""),
                        "electricity" to
                            (HomeWidgetStore.readSnapshot(context, "electricity") ?: ""),
                        "grades" to (HomeWidgetStore.readSnapshot(context, "grades") ?: ""),
                    )
                )
            }

            "consumeLaunchRoute" -> result.success(HomeWidgetStore.consumePendingRoute(context))

            // 设置页徽章 + 落地检测：返回 {「指标:尺寸」→ 已绑定实例数}。
            // 键格式与 Dart 的 homeWidgetPinKey 一致（见 pinKey）。
            "pinnedCounts" -> result.success(pinnedCounts(context))

            // 设置页「添加到桌面」：请求系统固定指定指标 × 尺寸的小组件。
            // 返回 {supported, requested}：不支持时由 Dart 侧引导用户手动添加。
            "requestPinWidget" -> {
                val args = call.arguments as? Map<*, *>
                val metric = args?.get("metric") as? String ?: ""
                val sizeTag = args?.get("size") as? String ?: ""
                val manager = AppWidgetManager.getInstance(context)
                val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    manager.isRequestPinAppWidgetSupported
                if (!supported) {
                    result.success(mapOf("supported" to false, "requested" to false))
                    return
                }
                val size = WidgetSize.entries.firstOrNull { it.tag == sizeTag }
                val provider = METRIC_PROVIDERS[metric]?.firstOrNull { it.second == size }?.first
                if (provider == null) {
                    result.success(mapOf("supported" to true, "requested" to false))
                    return
                }
                val requested = runCatching {
                    manager.requestPinAppWidget(ComponentName(context, provider), null, null)
                }.getOrDefault(false)
                result.success(mapOf("supported" to true, "requested" to requested))
            }

            // 后台 isolate 完成刷新（仅后台引擎会用到）
            "backgroundDone" -> {
                result.success(null)
                onBackgroundDone?.invoke()
            }

            else -> result.notImplemented()
        }
    }
}
