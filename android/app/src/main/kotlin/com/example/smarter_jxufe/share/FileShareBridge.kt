package com.example.smarter_jxufe.share

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 「导出文件 + 调起系统分享」桥（自研，零第三方依赖）。
 *
 * 用途：把 Dart 侧拿到的文件字节（如学校平台下发的志愿服务时长认定登记表 Word 原件）
 * 落到应用缓存目录，再经 [FileProvider] 生成 `content://` URI，
 * 交给 `ACTION_SEND` 系统分享面板（微信 / QQ / 邮件…）。
 *
 * 为什么不用 `share_plus`：项目纪律是能用自研原生桥解决的就不加依赖
 * （同 `HomeWidgetBridge`）。这里只用到 FileProvider + Intent，
 * androidx.core 已随其它插件进入依赖树。
 *
 * 缓存策略：文件写在 `cacheDir/shared/`，每次分享前清掉同名以外的旧文件，
 * 既避免缓存目录无限增长，也保证同名学生重新导出时拿到的是新内容。
 */
class FileShareBridge(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    companion object {
        /** 必须与 Dart 侧 `FileShare.channel` 一致。 */
        const val CHANNEL = "smarter_jxufe/file_share"

        /** FileProvider authority 后缀（与 AndroidManifest 中 `\${applicationId}.fileprovider` 对应）。 */
        const val AUTHORITY_SUFFIX = ".fileprovider"

        private const val TAG = "FileShareBridge"
        private const val DIR_NAME = "shared"

        fun authority(context: Context): String =
            context.packageName + AUTHORITY_SUFFIX
    }

    private val appContext: Context = context.applicationContext

    /** 调起分享面板必须要有 Activity 上下文（否则得加 FLAG_ACTIVITY_NEW_TASK）。 */
    private val uiContext: Context = context

    private val channel: MethodChannel =
        MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareBytes" -> shareBytes(call, result)
            else -> result.notImplemented()
        }
    }

    private fun shareBytes(call: MethodCall, result: MethodChannel.Result) {
        try {
            val bytes = call.argument<ByteArray>("bytes")
            if (bytes == null || bytes.isEmpty()) {
                result.success(mapOf("shared" to false, "message" to "文件内容为空"))
                return
            }
            val rawName = call.argument<String>("fileName") ?: "share.doc"
            // 兜底再取一次末段，避免任何形式的路径穿越
            val fileName = rawName
                .substringAfterLast('/')
                .substringAfterLast('\\')
                .ifBlank { "share.doc" }
            val mimeType =
                call.argument<String>("mimeType") ?: "application/octet-stream"
            val subject = call.argument<String>("subject")
            val text = call.argument<String>("text")

            val dir = File(appContext.cacheDir, DIR_NAME)
            if (!dir.exists() && !dir.mkdirs()) {
                result.success(mapOf("shared" to false, "message" to "无法创建缓存目录"))
                return
            }
            // 清掉上一次导出的其它文件，避免缓存堆积
            dir.listFiles()?.forEach { old ->
                if (old.isFile && old.name != fileName) {
                    runCatching { old.delete() }
                }
            }

            val file = File(dir, fileName)
            file.writeBytes(bytes)

            val uri = FileProvider.getUriForFile(
                appContext,
                authority(appContext),
                file,
            )

            val send = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                // 部分 OEM（含华为）只认 ClipData 上的 URI 授权，
                // 不设它时接收方可能「打不开 / 无权限读该文件」
                clipData = ClipData.newRawUri("", uri)
                subject?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
                text?.let { putExtra(Intent.EXTRA_TEXT, it) }
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(send, "分享志愿时长认定登记表").apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            uiContext.startActivity(chooser)

            Log.i(TAG, "已调起分享：$fileName（${bytes.size} 字节）")
            result.success(
                mapOf(
                    "shared" to true,
                    "path" to file.absolutePath,
                ),
            )
        } catch (t: Throwable) {
            // 分享失败绝不能带崩 App（同小组件的纪律）
            Log.w(TAG, "分享失败", t)
            result.success(
                mapOf("shared" to false, "message" to (t.message ?: t.toString())),
            )
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
