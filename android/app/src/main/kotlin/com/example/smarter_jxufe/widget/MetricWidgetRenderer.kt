package com.example.smarter_jxufe.widget

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import com.example.smarter_jxufe.MainActivity
import com.example.smarter_jxufe.R
import org.json.JSONObject

/**
 * 快照 JSON → RemoteViews（按尺寸档渲染）。
 *
 * 渲染约定（与 Dart 侧 `HomeWidgetSnapshot` 对齐）：
 * - 单值卡（电费 / 成绩）：`state == ok` 时大字 `value`（2×1 用 `valueShort`）
 *   + 小字 `unit`，副文本按档位显示（见 [WidgetSize.showSub1] / [WidgetSize.showSub2]）；
 *   **单行档**（cellHeight == 1）放不下第二行，非 ok 态直接把 `message` 写进数值位；
 * - 仪表盘（数据一览）：读 `cells`（最多 5 项）填 `dash_cell<i>_label/_value`，
 *   页脚显示 `sub2`；整卡非 ok 时隐藏所有行、改显示 `dash_message`。
 *
 * 配色一律取自资源：`values/colors.xml` 与 `values-night/colors.xml`
 * （桌面宿主按系统深色模式自动取值），因此本文件不写死任何色值。
 *
 * ⚠️ RemoteViews 只支持有限的方法集合：这里只用 setTextViewText /
 * setTextColor / setImageViewResource / setViewVisibility /
 * setOnClickPendingIntent，避免反射调用被系统拒绝。
 * 图标颜色不使用 setColorFilter，而是每个指标各有一份对应品牌色的矢量图
 * （矢量图内部同样引用 @color，深色模式自动提亮）。
 */
object MetricWidgetRenderer {

    /** id 名 → 资源 id（仪表盘格子是 `dash_cell<i>_label` 这类规律名，逐个手写易漂移）。 */
    private val idCache = HashMap<String, Int>()

    fun render(context: Context, metric: String, size: WidgetSize): RemoteViews =
        if (metric == HomeWidgetBridge.METRIC_DASHBOARD) {
            renderDashboard(context, size)
        } else {
            renderMetric(context, metric, size)
        }

    // ---------- 单值卡（电费 / 成绩） ----------

    private fun renderMetric(
        context: Context,
        metric: String,
        size: WidgetSize,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, size.metricLayoutRes)
        val snapshot = parse(HomeWidgetStore.readSnapshot(context, metric))

        val label = if (size.useShortValue) {
            // 2 格宽放不下「电费余额」四个字 + 数值，最窄档改用两字短标题。
            shortLabel(metric)
        } else {
            snapshot?.optString("label").orEmpty().ifEmpty { defaultLabel(metric) }
        }
        val state = snapshot?.optString("state").orEmpty().ifEmpty { "error" }
        val ok = state == "ok"
        val accent = accentColor(context, if (ok) accentRes(metric) else R.color.home_widget_accent_muted)

        views.setImageViewResource(R.id.widget_icon, defaultIcon(metric))
        views.setTextViewText(R.id.widget_label, label)
        views.setTextColor(R.id.widget_label, accent)

        val raw = snapshot?.optString("value").orEmpty()
        val short = snapshot?.optString("valueShort").orEmpty()
        val message = snapshot?.optString("message").orEmpty().ifEmpty { "暂无数据" }

        if (size.singleLine) {
            val value = when {
                !ok -> message
                size.useShortValue && short.isNotEmpty() -> short
                else -> raw
            }
            views.setTextViewText(R.id.widget_value, value)
            views.setTextViewText(
                R.id.widget_unit,
                if (ok) snapshot?.optString("unit").orEmpty() else "",
            )
            views.setViewVisibility(R.id.widget_sub1, View.GONE)
            views.setViewVisibility(R.id.widget_sub2, View.GONE)
        } else if (ok) {
            views.setTextViewText(
                R.id.widget_value,
                if (size.useShortValue && short.isNotEmpty()) short else raw,
            )
            views.setTextViewText(R.id.widget_unit, snapshot?.optString("unit").orEmpty())
            views.setTextViewText(R.id.widget_sub1, snapshot?.optString("sub1").orEmpty())
            views.setViewVisibility(
                R.id.widget_sub1,
                if (size.showSub1) View.VISIBLE else View.GONE,
            )
            views.setTextViewText(R.id.widget_sub2, snapshot?.optString("sub2").orEmpty())
            views.setViewVisibility(
                R.id.widget_sub2,
                if (size.showSub2) View.VISIBLE else View.GONE,
            )
        } else {
            // 空态 / 失败态：把说明放进副文本行，并强制可见（窄档否则只剩一个标题）。
            views.setTextViewText(R.id.widget_value, "")
            views.setTextViewText(R.id.widget_unit, "")
            views.setTextViewText(R.id.widget_sub1, message)
            views.setViewVisibility(R.id.widget_sub1, View.VISIBLE)
            views.setTextViewText(R.id.widget_sub2, snapshot?.optString("sub2").orEmpty())
            views.setViewVisibility(
                R.id.widget_sub2,
                if (size.showSub2) View.VISIBLE else View.GONE,
            )
        }

        views.setOnClickPendingIntent(R.id.widget_root, launchIntent(context, metric))
        return views
    }

    // ---------- 仪表盘（数据一览） ----------

    private fun renderDashboard(context: Context, size: WidgetSize): RemoteViews {
        val views = RemoteViews(context.packageName, size.dashboardLayoutRes)
        val snapshot = parse(
            HomeWidgetStore.readSnapshot(context, HomeWidgetBridge.METRIC_DASHBOARD),
        )
        val state = snapshot?.optString("state").orEmpty().ifEmpty { "error" }
        val cells = snapshot?.optJSONArray("cells")
        if (snapshot != null && snapshot.has("cells") && cells == null) {
            // 形状不对（例如被写成了字符串）时给个明确信号，别让它静默变成空态。
            Log.w(
                "MetricWidgetRenderer",
                "仪表盘快照的 cells 不是数组：${snapshot.opt("cells")}",
            )
        }
        val ok = state == "ok" && cells != null && cells.length() > 0

        if (!ok) {
            for (row in 1..size.dashRows) {
                views.setViewVisibility(id(context, "dash_row$row"), View.GONE)
            }
            if (size.dashFooter) views.setViewVisibility(R.id.dash_footer, View.GONE)
            views.setTextViewText(
                R.id.dash_message,
                snapshot?.optString("message").orEmpty().ifEmpty { "暂无数据" },
            )
            views.setViewVisibility(R.id.dash_message, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.dash_message, View.GONE)
            for (i in 1..size.dashCells) {
                val cell = cells.optJSONObject(i - 1)
                views.setTextViewText(
                    id(context, "dash_cell${i}_label"),
                    cell?.optString("label").orEmpty(),
                )
                views.setTextViewText(
                    id(context, "dash_cell${i}_value"),
                    cell?.optString("value").orEmpty(),
                )
                // 缺项用 INVISIBLE 而非 GONE：保留权重，格子对齐不塌。
                views.setViewVisibility(
                    id(context, "dash_cell$i"),
                    if (cell == null) View.INVISIBLE else View.VISIBLE,
                )
            }
            if (size.dashFooter) {
                views.setTextViewText(R.id.dash_footer, snapshot.optString("sub2"))
                views.setViewVisibility(R.id.dash_footer, View.VISIBLE)
            }
        }

        views.setOnClickPendingIntent(
            R.id.widget_root,
            launchIntent(context, HomeWidgetBridge.METRIC_DASHBOARD),
        )
        return views
    }

    // ---------- 工具 ----------

    /** 点击 → 打开 App 并带上路由，由 Flutter 侧跳到对应页面。 */
    private fun launchIntent(context: Context, metric: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            putExtra(HomeWidgetBridge.EXTRA_ROUTE, metric)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context,
            metric.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun id(context: Context, name: String): Int = idCache.getOrPut(name) {
        context.resources.getIdentifier(name, "id", context.packageName)
    }

    /**
     * 取色（自动套用当前配置：系统深色模式会命中 `values-night/colors.xml`）。
     *
     * 用 `Resources.getColor` 而非 `Context.getColor`：前者对 minSdk 无要求，
     * 小组件要在各种 ROM 上都能渲染。
     */
    @Suppress("DEPRECATION")
    private fun accentColor(context: Context, resId: Int): Int =
        context.resources.getColor(resId)

    private fun parse(raw: String?): JSONObject? {
        if (raw.isNullOrEmpty()) return null
        return try {
            JSONObject(raw)
        } catch (_: Exception) {
            null
        }
    }

    private fun accentRes(metric: String): Int = when (metric) {
        "grades" -> R.color.home_widget_accent_grade
        HomeWidgetBridge.METRIC_DASHBOARD -> R.color.home_widget_accent_dashboard
        else -> R.color.home_widget_accent_electricity
    }

    private fun defaultLabel(metric: String): String = when (metric) {
        "grades" -> "课程加权"
        HomeWidgetBridge.METRIC_DASHBOARD -> "数据一览"
        else -> "电费余额"
    }

    /** 2×1 档用的两字短标题。 */
    private fun shortLabel(metric: String): String = when (metric) {
        "grades" -> "成绩"
        HomeWidgetBridge.METRIC_DASHBOARD -> "一览"
        else -> "电费"
    }

    private fun defaultIcon(metric: String): Int = when (metric) {
        "grades" -> R.drawable.home_widget_ic_grade
        HomeWidgetBridge.METRIC_DASHBOARD -> R.drawable.home_widget_ic_dashboard
        else -> R.drawable.home_widget_ic_electricity
    }
}
