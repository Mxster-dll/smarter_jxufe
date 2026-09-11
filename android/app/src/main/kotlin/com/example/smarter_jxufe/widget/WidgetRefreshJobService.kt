package com.example.smarter_jxufe.widget

import android.app.job.JobParameters
import android.app.job.JobService
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * 后台刷新执行体：拉起一个 headless FlutterEngine，跑 Dart 入口
 * `homeWidgetBackgroundMain`（命名入口点），刷新完由 Dart 回调
 * `backgroundDone` 通知本服务结束。
 *
 * 注意：Flutter 3.38 的嵌入层已移除 `FlutterCallbackInformation` 与回调句柄
 * 那套 API，只能用命名入口点（`DartEntrypoint(pathToBundle, functionName)`）。
 */
class WidgetRefreshJobService : JobService() {

    companion object {
        private const val TAG = "WidgetRefreshJob"

        /** Dart 侧入口函数名（lib/features/home_widget/data/home_widget_background.dart）。 */
        private const val ENTRY_POINT = "homeWidgetBackgroundMain"

        /** 兜底超时：Dart 侧异常没上报也一定会结束，避免占着引擎不放。 */
        private const val TIMEOUT_MS = 60_000L
    }

    private var engine: FlutterEngine? = null
    private var engineGroup: FlutterEngineGroup? = null
    private var params: JobParameters? = null
    private var finished = false
    private val handler = Handler(Looper.getMainLooper())
    private val timeoutRunnable = Runnable { finishJob() }

    override fun onStartJob(params: JobParameters): Boolean {
        this.params = params
        Log.i(TAG, "onStartJob 收到请求（准备拉起 headless 引擎）")
        return try {
            val loader = FlutterInjector.instance().flutterLoader()
            // findAppBundlePath() 需要 loader 已初始化（FlutterEngine 内部也会做，
            // 但我们要在构造入口点之前拿到 assets 路径）。
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            Log.i(TAG, "FlutterLoader 就绪，bundle=${loader.findAppBundlePath()}")

            // ⚠️ 不能用 FlutterEngine(context)：单参构造会立刻执行默认入口点
            // `main`，headless 场景下解析失败（实测日志：
            // "Could not resolve main entrypoint function." → 根 isolate 建不起来）。
            // createAndRunEngine 只跑我们指定的入口点。
            val entrypoint = DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                ENTRY_POINT,
            )
            val group = FlutterEngineGroup(applicationContext)
            val flutterEngine = group.createAndRunEngine(applicationContext, entrypoint)
            engineGroup = group
            engine = flutterEngine
            Log.i(TAG, "headless 引擎已创建，入口点=$ENTRY_POINT，等待 Dart 侧回报")

            // 后台引擎同样挂数据桥：读认证快照、写新快照、上报完成。
            HomeWidgetBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger) {
                Log.i(TAG, "Dart 侧回报 backgroundDone")
                finishJob()
            }
            handler.postDelayed(timeoutRunnable, TIMEOUT_MS)
            true
        } catch (e: Throwable) {
            // 兜住 Throwable：引擎/插件注册失败可能是 Error（如缺类）。
            Log.e(TAG, "启动后台刷新引擎失败", e)
            finishJob()
            false
        }
    }

    override fun onStopJob(params: JobParameters): Boolean {
        // 被系统中断（如约束不再满足）→ 销毁引擎并允许重试。
        Log.i(TAG, "onStopJob 被系统中断，销毁引擎并重试")
        finishJob()
        return true
    }

    private fun finishJob() {
        if (finished) return
        finished = true
        Log.i(TAG, "后台刷新结束（销毁引擎）")
        handler.removeCallbacks(timeoutRunnable)
        try {
            engine?.destroy()
        } catch (e: Exception) {
            Log.w(TAG, "销毁后台引擎失败", e)
        }
        engine = null
        engineGroup = null
        params?.let { jobFinished(it, false) }
        params = null
    }
}
