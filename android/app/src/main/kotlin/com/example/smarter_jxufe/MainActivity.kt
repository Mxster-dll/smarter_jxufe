package com.example.smarter_jxufe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.util.Log
import com.example.smarter_jxufe.share.FileShareBridge
import com.example.smarter_jxufe.widget.HomeWidgetBridge
import com.example.smarter_jxufe.widget.HomeWidgetStore
import com.example.smarter_jxufe.widget.WidgetRefreshScheduler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var widgetBridge: HomeWidgetBridge? = null
    private var fileShareBridge: FileShareBridge? = null
    private var unlockReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ⚠️ 小组件是锦上添花的能力，任何一环失败都不允许带崩 App：
        // 曾因 dex 缺类（NoClassDefFoundError）在这里崩成「屡次停止运行」，
        // 故统一兜住 Throwable（NoClassDefFoundError 是 Error，不是 Exception）。
        runCatching {
            // 小组件周期兜底刷新（幂等）：App 进程被回收后唯一还能更新的途径。
            WidgetRefreshScheduler.ensurePeriodic(this)

            // 「解锁即刷新」：ACTION_USER_PRESENT 不在隐式广播豁免名单里，
            // 清单注册收不到，只能运行时注册 —— 因此仅在 App 进程存活期间有效，
            // 进程被杀后由上面的周期任务兜底。
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == Intent.ACTION_USER_PRESENT) {
                        runCatching { WidgetRefreshScheduler.refreshNow(this@MainActivity) }
                    }
                }
            }
            registerReceiver(receiver, IntentFilter(Intent.ACTION_USER_PRESENT))
            unlockReceiver = receiver

            // debug 构建启动时自检小组件布局（3 指标 × 8 尺寸 = 24 组合全渲染 + inflate），
            // 以及深色模式配色是否真的命中 values-night。
            val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            if (debuggable) {
                Log.i("MainActivity", "小组件自检: " + HomeWidgetBridge.selfCheck(this))
                Log.i("MainActivity", "小组件数据桥: " + HomeWidgetBridge.shapeCheck())
                Log.i("MainActivity", "小组件深色模式: " + HomeWidgetBridge.nightCheck(this))
            }
        }.onFailure {
            Log.w("MainActivity", "小组件排程初始化失败（已忽略，不影响 App）", it)
        }
    }

    override fun onDestroy() {
        unlockReceiver?.let { runCatching { unregisterReceiver(it) } }
        unlockReceiver = null
        fileShareBridge?.dispose()
        fileShareBridge = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 桌面小组件数据桥（自研，零第三方依赖）
        widgetBridge = HomeWidgetBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        // 「导出文件 + 调起系统分享」桥（自研，零第三方依赖）
        fileShareBridge = FileShareBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        handleWidgetIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // launchMode=singleTop：App 已在运行时点小组件会走这里
        handleWidgetIntent(intent)
    }

    /**
     * 点小组件唤起 App：把目标路由先落到本地存储（冷启动由 Flutter 主动取），
     * 再通过通道通知 Flutter（热启动立即跳转）。
     */
    private fun handleWidgetIntent(intent: Intent?) {
        val route = intent?.getStringExtra(HomeWidgetBridge.EXTRA_ROUTE) ?: return
        intent.removeExtra(HomeWidgetBridge.EXTRA_ROUTE)
        HomeWidgetStore.setPendingRoute(this, route)
        widgetBridge?.notifyRouteChanged(route)
    }
}
