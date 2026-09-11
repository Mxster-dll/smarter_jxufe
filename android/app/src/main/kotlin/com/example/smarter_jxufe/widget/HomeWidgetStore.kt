package com.example.smarter_jxufe.widget

import android.content.Context

/**
 * 桌面小组件本地存储（SharedPreferences，进程安全、跨 Flutter isolate 可用）。
 *
 * 三类内容：
 * - 每个指标一份快照 JSON（Flutter 侧算好，原生只渲染）；
 * - 后台刷新所需的最小认证快照（学号 / 密码 / TGC / JSESSIONID / 房间号）；
 * - 待处理路由（点小组件唤起 App 时写入，Flutter 取一次即清）。
 *
 * 之所以不用 Hive：后台刷新跑在独立的 FlutterEngine（另一个 isolate），
 * 与主 isolate 同时打开同一个 Hive box 会有写冲突风险。
 */
object HomeWidgetStore {
    private const val PREFS = "smarter_home_widget"
    private const val KEY_AUTH = "auth"
    private const val KEY_PENDING_ROUTE = "pending_route"

    fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun snapshotKey(metric: String) = "snapshot_$metric"

    fun readSnapshot(context: Context, metric: String): String? =
        prefs(context).getString(snapshotKey(metric), null)

    fun writeSnapshot(context: Context, metric: String, json: String) {
        prefs(context).edit().putString(snapshotKey(metric), json).apply()
    }

    fun readAuth(context: Context): String = prefs(context).getString(KEY_AUTH, "") ?: ""

    fun writeAuth(context: Context, json: String) {
        prefs(context).edit().putString(KEY_AUTH, json).apply()
    }

    fun setPendingRoute(context: Context, route: String) {
        prefs(context).edit().putString(KEY_PENDING_ROUTE, route).apply()
    }

    /** 取出待处理路由并清空（保证只消费一次）。 */
    fun consumePendingRoute(context: Context): String? {
        val route = prefs(context).getString(KEY_PENDING_ROUTE, null)
        if (route != null) prefs(context).edit().remove(KEY_PENDING_ROUTE).apply()
        return route
    }

    /** 退出登录等场景：清空全部（避免桌面残留上一个账号的数据）。 */
    fun clearAll(context: Context) {
        prefs(context).edit().clear().apply()
    }
}
