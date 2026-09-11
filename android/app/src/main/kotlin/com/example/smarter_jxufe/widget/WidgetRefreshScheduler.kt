package com.example.smarter_jxufe.widget

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.os.Build

/**
 * 小组件后台刷新排程（framework `JobScheduler`，零第三方依赖）。
 *
 * - **周期任务**：兜底刷新，16 分钟一次（JobScheduler 周期下限 15 分钟）；
 *   `setPersisted(true)` 让它在重启后由系统自动恢复（需 RECEIVE_BOOT_COMPLETED）。
 * - **一次性任务**：解锁、开 App 等时机立即刷一次。
 *
 * 为什么不只用「解锁时刷新」：`ACTION_USER_PRESENT` 不在隐式广播豁免名单里，
 * 只能运行时注册（进程活着才有效）。App 被系统回收后就再也收不到解锁广播，
 * 小组件会永久停在旧值 —— 周期任务就是为此兜底。
 */
object WidgetRefreshScheduler {
    private const val PERIODIC_JOB_ID = 8802
    private const val ONE_SHOT_JOB_ID = 8803
    private const val PERIOD_MS = 16 * 60 * 1000L

    private fun scheduler(context: Context): JobScheduler? =
        context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler

    private fun hasPending(scheduler: JobScheduler, jobId: Int): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            scheduler.getPendingJob(jobId) != null
        } else {
            scheduler.allPendingJobs.any { it.id == jobId }
        }

    /** 保证周期兜底任务已排程（幂等，重复调用不会重置周期）。 */
    fun ensurePeriodic(context: Context) {
        val scheduler = scheduler(context) ?: return
        if (hasPending(scheduler, PERIODIC_JOB_ID)) return
        val job = JobInfo.Builder(
            PERIODIC_JOB_ID,
            ComponentName(context, WidgetRefreshJobService::class.java),
        )
            .setPeriodic(PERIOD_MS)
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setPersisted(true)
            .build()
        runCatching { scheduler.schedule(job) }
    }

    /** 立即刷新一次（已在排队则忽略，避免解锁/开 App 时重复拉起引擎）。 */
    fun refreshNow(context: Context) {
        val scheduler = scheduler(context) ?: return
        if (hasPending(scheduler, ONE_SHOT_JOB_ID)) return
        val job = JobInfo.Builder(
            ONE_SHOT_JOB_ID,
            ComponentName(context, WidgetRefreshJobService::class.java),
        )
            .setMinimumLatency(0)
            .setOverrideDeadline(20_000)
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .build()
        runCatching { scheduler.schedule(job) }
    }
}
