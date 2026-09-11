package com.example.smarter_jxufe.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import com.example.smarter_jxufe.R

/**
 * 尺寸档（宽 × 高，单位 = 桌面格子）。
 *
 * 每档一个独立 provider（而不是一个可缩放组件）：桌面不保证支持缩放时
 * （华为/HarmonyOS 尤其如此），八档尺寸仍能在添加面板里直接选到。
 *
 * 布局约定（渲染器 [MetricWidgetRenderer] 依赖）：
 * - 单值卡（电费 / 成绩）四套布局都保留同样的 6 个 id
 *   （widget_root / icon / label / value / unit / sub1 / sub2）；
 * - 仪表盘（数据一览）布局保留 dash_rowN / dash_cellN / dash_cellN_label /
 *   dash_cellN_value / dash_footer / dash_message。
 * 因此渲染代码不需要分支取 id，只按档位控制可见性。
 */
enum class WidgetSize(
    val cellWidth: Int,
    val cellHeight: Int,
    /** 单值卡（电费 / 成绩）布局。 */
    val metricLayoutRes: Int,
    /** 仪表盘（数据一览）布局。 */
    val dashboardLayoutRes: Int,
    /** 是否显示副文本第一行（房间号 / 专业排名）。 */
    val showSub1: Boolean,
    /** 是否显示副文本第二行（更新时间）。 */
    val showSub2: Boolean,
    /** 仪表盘该档的格子数（= 布局里 dash_cell<i> 的数量，也是能显示的项数上限）。 */
    val dashCells: Int,
    /** 仪表盘该档的行数（1 或 2；用于空态时整行隐藏）。 */
    val dashRows: Int,
    /** 仪表盘该档是否有「更新于 …」页脚（布局里有没有 dash_footer 这个 id）。 */
    val dashFooter: Boolean,
) {
    /** 2×1：只有标题 + 数值（窄到放不下 8 位小数，用 valueShort）。 */
    X2x1(
        2, 1, R.layout.home_widget_metric_2x1, R.layout.home_widget_dashboard_2x1,
        showSub1 = false, showSub2 = false, dashCells = 2, dashRows = 1, dashFooter = false,
    ),

    /** 3×1：单行条，标题 + 数值 + 单位。 */
    X3x1(
        3, 1, R.layout.home_widget_metric_3x1, R.layout.home_widget_dashboard_3x1,
        showSub1 = false, showSub2 = false, dashCells = 3, dashRows = 1, dashFooter = false,
    ),

    /** 4×1：单行条（较宽）。 */
    X4x1(
        4, 1, R.layout.home_widget_metric_4x1, R.layout.home_widget_dashboard_4x1,
        showSub1 = false, showSub2 = false, dashCells = 4, dashRows = 1, dashFooter = false,
    ),

    /** 5×1：单行条（最宽），仪表盘可横排 5 项。 */
    X5x1(
        5, 1, R.layout.home_widget_metric_5x1, R.layout.home_widget_dashboard_5x1,
        showSub1 = false, showSub2 = false, dashCells = 5, dashRows = 1, dashFooter = false,
    ),

    /** 2×2：标题 + 数值 + 一行副文本；仪表盘 2×2 格（前 4 项）。 */
    X2x2(
        2, 2, R.layout.home_widget_metric_2x2, R.layout.home_widget_dashboard_2x2,
        showSub1 = true, showSub2 = false, dashCells = 4, dashRows = 2, dashFooter = false,
    ),

    /** 3×2：标题 + 数值 + 副文本；仪表盘 3×2 格。 */
    X3x2(
        3, 2, R.layout.home_widget_metric_3x2, R.layout.home_widget_dashboard_3x2,
        showSub1 = true, showSub2 = false, dashCells = 6, dashRows = 2, dashFooter = false,
    ),

    /** 4×2：标题 + 数值 + 房间号/排名 + 更新时间；仪表盘 3×2 格 + 页脚。 */
    X4x2(
        4, 2, R.layout.home_widget_metric_4x2, R.layout.home_widget_dashboard_4x2,
        showSub1 = true, showSub2 = true, dashCells = 6, dashRows = 2, dashFooter = true,
    ),

    /** 5×2：同 4×2，字号与留白更宽松；仪表盘横排 5 项 + 页脚。 */
    X5x2(
        5, 2, R.layout.home_widget_metric_5x2, R.layout.home_widget_dashboard_5x2,
        showSub1 = true, showSub2 = true, dashCells = 5, dashRows = 1, dashFooter = true,
    );

    /** 单行档：一行放不下第二行副文本，非 ok 态由渲染器把说明写进数值位。 */
    val singleLine: Boolean get() = cellHeight == 1

    /** 最窄档（2×1）用短标题与短数值。 */
    val useShortValue: Boolean get() = this == X2x1

    /** 供日志与元数据描述用的档位名，如 `2x1`。 */
    val tag: String get() = "${cellWidth}x$cellHeight"
}

/**
 * 指标小组件基类。
 *
 * 3 个指标（数据一览 / 电费余额 / 课程加权）× 8 档尺寸 = 24 个 provider。
 * AppWidgetProvider 必须有无参构造（系统反射实例化），因此每档写成一个具体类。
 */
abstract class MetricWidgetProvider : AppWidgetProvider() {

    /** 指标 key，与 Dart 侧 `HomeWidgetMetric.key` 一致。 */
    abstract val metric: String

    /** 尺寸档。 */
    abstract val size: WidgetSize

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val views = MetricWidgetRenderer.render(context, metric, size)
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }
}

// ---------- 仪表盘（数据一览） ----------

class DashboardWidget2x1 : MetricWidgetProvider() {
    override val metric = HomeWidgetBridge.METRIC_DASHBOARD
    override val size = WidgetSize.X2x1
}

class DashboardWidget3x1 : MetricWidgetProvider() {
    override val metric = HomeWidgetBridge.METRIC_DASHBOARD
    override val size = WidgetSize.X3x1
}

class DashboardWidget4x1 : MetricWidgetProvider() {
    override val metric = HomeWidgetBridge.METRIC_DASHBOARD
    override val size = WidgetSize.X4x1
}

class DashboardWidget5x1 : MetricWidgetProvider() {
    override val metric = HomeWidgetBridge.METRIC_DASHBOARD
    override val size = WidgetSize.X5x1
}

class DashboardWidget2x2 : MetricWidgetProvider() {
    override val metric = HomeWidgetBridge.METRIC_DASHBOARD
    override val size = WidgetSize.X2x2
}

class DashboardWidget3x2 : MetricWidgetProvider() {
    override val metric = HomeWidgetBridge.METRIC_DASHBOARD
    override val size = WidgetSize.X3x2
}

class DashboardWidget4x2 : MetricWidgetProvider() {
    override val metric = HomeWidgetBridge.METRIC_DASHBOARD
    override val size = WidgetSize.X4x2
}

class DashboardWidget5x2 : MetricWidgetProvider() {
    override val metric = HomeWidgetBridge.METRIC_DASHBOARD
    override val size = WidgetSize.X5x2
}

// ---------- 电费余额 ----------

class ElectricityWidget2x1 : MetricWidgetProvider() {
    override val metric = "electricity"
    override val size = WidgetSize.X2x1
}

class ElectricityWidget3x1 : MetricWidgetProvider() {
    override val metric = "electricity"
    override val size = WidgetSize.X3x1
}

class ElectricityWidget4x1 : MetricWidgetProvider() {
    override val metric = "electricity"
    override val size = WidgetSize.X4x1
}

class ElectricityWidget5x1 : MetricWidgetProvider() {
    override val metric = "electricity"
    override val size = WidgetSize.X5x1
}

class ElectricityWidget2x2 : MetricWidgetProvider() {
    override val metric = "electricity"
    override val size = WidgetSize.X2x2
}

class ElectricityWidget3x2 : MetricWidgetProvider() {
    override val metric = "electricity"
    override val size = WidgetSize.X3x2
}

class ElectricityWidget4x2 : MetricWidgetProvider() {
    override val metric = "electricity"
    override val size = WidgetSize.X4x2
}

class ElectricityWidget5x2 : MetricWidgetProvider() {
    override val metric = "electricity"
    override val size = WidgetSize.X5x2
}

// ---------- 课程加权 ----------

class GradeWidget2x1 : MetricWidgetProvider() {
    override val metric = "grades"
    override val size = WidgetSize.X2x1
}

class GradeWidget3x1 : MetricWidgetProvider() {
    override val metric = "grades"
    override val size = WidgetSize.X3x1
}

class GradeWidget4x1 : MetricWidgetProvider() {
    override val metric = "grades"
    override val size = WidgetSize.X4x1
}

class GradeWidget5x1 : MetricWidgetProvider() {
    override val metric = "grades"
    override val size = WidgetSize.X5x1
}

class GradeWidget2x2 : MetricWidgetProvider() {
    override val metric = "grades"
    override val size = WidgetSize.X2x2
}

class GradeWidget3x2 : MetricWidgetProvider() {
    override val metric = "grades"
    override val size = WidgetSize.X3x2
}

class GradeWidget4x2 : MetricWidgetProvider() {
    override val metric = "grades"
    override val size = WidgetSize.X4x2
}

class GradeWidget5x2 : MetricWidgetProvider() {
    override val metric = "grades"
    override val size = WidgetSize.X5x2
}
