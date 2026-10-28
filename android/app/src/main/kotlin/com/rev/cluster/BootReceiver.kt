package com.rev.cluster

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 开机自启接收器（v2.14.0，车机通电即进仪表盘）。
 *
 * 触发：BOOT_COMPLETED（+ 部分厂商的 QUICKBOOT / LOCKED_BOOT）。
 * 行为：仅当"开机自启"开关打开（默认开）时拉起 MainActivity；
 *       MainActivity.onCreate 会自动启动前台保活服务，故这里只拉起 Activity 即可。
 *
 * 开关持久化在 Flutter shared_preferences（文件名 FlutterSharedPreferences.xml，
 * key 前缀 flutter.），与 Dart 端 BootAutostartService 共用。
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "RevBootReceiver"
        /** 与 Dart 端一致的开关 key（Flutter 存储时加 flutter. 前缀）。 */
        const val PREFS_NAME = "FlutterSharedPreferences"
        const val KEY_AUTOSTART = "flutter.rev_boot_autostart"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> Unit
            else -> return
        }

        if (!isAutostartEnabled(context)) {
            Log.i(TAG, "开机自启开关已关，不拉起 App")
            return
        }

        try {
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            launch.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
            )
            context.startActivity(launch)
            // 同时兜底拉前台保活服务（车机上有时 Activity 被后台限制，先保活）。
            RevForegroundService.start(context, preferConnected = false)
            Log.i(TAG, "开机自启：已拉起 App + 前台保活")
        } catch (e: Exception) {
            // 车机厂商可能禁止后台拉起，兜底不崩溃。
            Log.w(TAG, "开机自启拉起失败（厂商限制）: ${e.message}")
        }
    }

    /** 读开关；缺省视为 true（默认开）。 */
    private fun isAutostartEnabled(context: Context): Boolean {
        return try {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_AUTOSTART, true)
        } catch (e: Exception) {
            true
        }
    }
}
