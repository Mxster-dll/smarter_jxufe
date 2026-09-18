package com.example.smarter_jxufe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
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

        // 「铺满整屏」（edge-to-edge）：Flutter 视图一直画到状态栏 / 导航栏底下。
        //
        // 为什么需要：默认装饰视图只占「两条系统栏之间」的区域，底部导航栏那一条
        // 露出的是窗口背景色（`NormalTheme.windowBackground`，浅色主题下是灰色），
        // 于是手机启动后底部出现一条**通屏宽、不显示内容**的灰带
        // （用户 2026-09-16 报「其他应用中没有这个问题」）。开启后 App 内容
        // （白色 Scaffold / 课表课格）会铺到屏幕最底边，灰带消失；同时把系统栏
        // 做成透明、关掉系统默认的对比度遮罩（那条遮罩本身也是灰的）。
        //
        // 系统栏内边距由 Flutter 侧按 MediaQuery 处理：AppBar 自动避开状态栏，
        // 课表则**刻意**用满全高（用户要求「竖排课表高度与屏幕同高」）。
        runCatching {
            WindowCompat.setDecorFitsSystemWindows(window, false)
            @Suppress("DEPRECATION")
            window.statusBarColor = Color.TRANSPARENT
            @Suppress("DEPRECATION")
            window.navigationBarColor = Color.TRANSPARENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                window.isStatusBarContrastEnforced = false
                window.isNavigationBarContrastEnforced = false
            }
            // 全应用浅色（纯白底）→ 系统栏图标用深色。
            WindowInsetsControllerCompat(window, window.decorView).apply {
                isAppearanceLightStatusBars = true
                isAppearanceLightNavigationBars = true
            }
        }.onFailure {
            Log.w("MainActivity", "edge-to-edge 设置失败（已忽略，不影响 App）", it)
        }

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
