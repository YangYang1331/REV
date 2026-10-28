package com.rev.cluster

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

/**
 * REV 前台保活服务。
 *
 * 关键：前台服务类型必须与"已授予的运行时权限"匹配，否则 Android 14+ 会在
 * startForeground 时抛 SecurityException 直接闪退。
 *  - 已连接 OBD（已授予 BLUETOOTH_CONNECT）→ connectedDevice；
 *  - 刚启动、还没授权蓝牙 → dataSync（仅需普通权限，用来保活云上报），
 *    待 OBD 连接成功后再通过 onStartCommand 重新 startForeground 升级为 connectedDevice。
 * 任何 startForeground 异常都被兜底，绝不让进程崩溃。
 */
class RevForegroundService : Service() {

    companion object {
        private const val TAG = "RevFgService"
        private const val CHANNEL_ID = "rev_cluster"
        private const val NOTIF_ID = 2601
        private const val WAKE_TIMEOUT = 12 * 60 * 60 * 1000L // 12h 兜底

        /** 安全启动前台服务。preferConnected=true 表示 OBD 已连接（蓝牙权限已授予）。 */
        fun start(context: Context, preferConnected: Boolean) {
            val intent = Intent(context, RevForegroundService::class.java).apply {
                putExtra("preferConnected", preferConnected)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.w(TAG, "启动前台服务失败（忽略，不影响主界面）: ${e.message}")
            }
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val preferConnected = intent?.getBooleanExtra("preferConnected", false) ?: false
        safeStartForeground(preferConnected)
        Log.i(TAG, "REV 前台保活服务运行中(preferConnected=$preferConnected)")
        return START_STICKY
    }

    private fun safeStartForeground(preferConnected: Boolean) {
        val notification = buildNotification()
        val type = chooseForegroundType(preferConnected)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && type != 0) {
                startForeground(NOTIF_ID, notification, type)
            } else {
                startForeground(NOTIF_ID, notification)
            }
        } catch (e: SecurityException) {
            // 权限不满足（例如 connectedDevice 但蓝牙权限被回收），降级到 dataSync。
            Log.w(TAG, "前台服务类型 $type 被拒，降级 dataSync: ${e.message}")
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    startForeground(
                        NOTIF_ID, notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                    )
                } else {
                    startForeground(NOTIF_ID, notification)
                }
            } catch (e2: Exception) {
                giveUpGracefully(e2)
            }
        } catch (e: Exception) {
            giveUpGracefully(e)
        }
    }

    /** 按系统版本与已授予权限选择一个"一定合法"的前台服务类型。 */
    private fun chooseForegroundType(preferConnected: Boolean): Int {
        val hasBt = hasBluetoothConnectPermission()
        return when {
            // Android 11+（API 30）：DATA_SYNC 存在，按蓝牙权限二选一。
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                if (preferConnected && hasBt)
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                else
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            // Android 10（API 29）：只有 connectedDevice，且系统不强制运行时权限。
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            // 更早版本：不使用类型。
            else -> 0
        }
    }

    private fun hasBluetoothConnectPermission(): Boolean {
        // BLUETOOTH_CONNECT 是 Android 12（API 31）才引入的运行时权限。
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
    }

    /** 前台服务最终也无法启动时，优雅停止，避免 5 秒 ANR 崩溃。 */
    private fun giveUpGracefully(e: Exception) {
        Log.w(TAG, "前台服务无法启动，优雅停止: ${e.message}")
        try {
            releaseWakeLock()
        } catch (_: Exception) {
        }
        try {
            stopSelf()
        } catch (_: Exception) {
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // 用户划掉任务后重新拉起，保持看板在线（START_STICKY 兜底）。
        val restart = Intent(applicationContext, RevForegroundService::class.java)
        val pi = PendingIntent.getService(
            this, 1, restart,
            PendingIntent.FLAG_ONE_SHOT or immutableFlag(),
        )
        val am = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        try {
            am.set(android.app.AlarmManager.RTC, System.currentTimeMillis() + 1000, pi)
        } catch (e: Exception) {
            Log.w(TAG, "安排重启失败: ${e.message}")
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID, "REV 车载仪表",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "保持 OBD 连接与车队看板在线"
                setShowBadge(false)
                enableVibration(false)
                enableLights(false)
            }
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentPi = PendingIntent.getActivity(
            this, 0, launchIntent ?: Intent(),
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("REV 车载仪表运行中")
            .setContentText("OBD 连接保持 · 车队看板在线")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_LOW)
            .setContentIntent(contentPi)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "rev:cluster").apply {
                setReferenceCounted(false)
                acquire(WAKE_TIMEOUT)
            }
        } catch (e: Exception) {
            Log.w(TAG, "获取 WakeLock 失败: ${e.message}")
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (e: Exception) {
            Log.w(TAG, "释放 WakeLock 失败: ${e.message}")
        }
        wakeLock = null
    }

    private fun immutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
}
