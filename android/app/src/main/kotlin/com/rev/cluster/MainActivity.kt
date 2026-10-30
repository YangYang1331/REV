package com.rev.cluster

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val reqNotifications = 2601
    private val foregroundChannelName = "rev/foreground"
    private val deviceChannelName = "rev/device"
    private val audioFocusChannelName = "rev/audio_focus"
    private val ttsChannelName = "rev/tts"

    private var audioFocus: AudioFocusManager? = null
    private var audioFocusSink: EventChannel.EventSink? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureNotificationPermission()
        // 启动即保活（此时还没有蓝牙权限，内部用 dataSync 安全类型，绝不闪退）。
        RevForegroundService.start(this, preferConnected = false)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 既有：前台服务通道 ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, foregroundChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // OBD 真实连接成功（蓝牙权限已授予）→ 升级为 connectedDevice 前台服务。
                    "onObdConnected" -> {
                        RevForegroundService.start(this, preferConnected = true)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── 新增：设备通道（开机自启开关 / 厂商自启引导 / 音频焦点）──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBootAutostart" -> result.success(getBootAutostart())
                    "setBootAutostart" -> {
                        setBootAutostart(call.arguments as? Boolean ?: true)
                        result.success(true)
                    }
                    "openBootAutostartSettings" -> {
                        openBootAutostartSettings()
                        result.success(true)
                    }
                    "requestAudioFocus" -> result.success(audioFocus?.request() ?: false)
                    "abandonAudioFocus" -> {
                        audioFocus?.abandon(); result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── 语音播报（Android 原生 TTS，不引第三方依赖）──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ttsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> {
                        val args = call.arguments as? Map<*, *>
                        val text = (args?.get("text") as? String) ?: ""
                        result.success(speak(text))
                    }
                    "stop" -> {
                        try { tts?.stop() } catch (_: Exception) {}
                        result.success(true)
                    }
                    "isAvailable" -> result.success(ttsReady)
                    else -> result.notImplemented()
                }
            }
        initTts()

        // ── 新增：音频焦点事件流 ──
        audioFocus = AudioFocusManager(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, audioFocusChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    audioFocusSink = sink
                    audioFocus?.onEvent = { ev -> runOnUiThread { sink?.success(ev) } }
                    audioFocus?.request()
                }
                override fun onCancel(arguments: Any?) {
                    audioFocus?.abandon()
                    audioFocusSink = null
                }
            })
    }

    // ── 开机自启开关（与 BootReceiver 共用同一份 SharedPreferences）──
    private fun bootPrefs() =
        getSharedPreferences(BootReceiver.PREFS_NAME, Context.MODE_PRIVATE)

    private fun getBootAutostart(): Boolean =
        bootPrefs().getBoolean(BootReceiver.KEY_AUTOSTART, true)

    private fun setBootAutostart(on: Boolean) {
        bootPrefs().edit().putBoolean(BootReceiver.KEY_AUTOSTART, on).apply()
    }

    /**
     * 引导用户到厂商"自启动管理"页。国产 ROM（小米/华为/OPPO/vivo 等）默认
     * 禁止第三方 App 开机自启，需用户手动放行；这里逐个尝试已知 Intent，
     * 失败则退到应用详情页让用户自行找到"自启动"开关。
     */
    private fun openBootAutostartSettings() {
        val candidates = mutableListOf(
            // 通用：应用详情页
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null)),
        )
        val brand = Build.MANUFACTURER.lowercase()
        try {
            when {
                brand.contains("xiaomi") || brand.contains("redmi") ->
                    candidates.add(0, Intent().setComponent(ComponentName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.autostart.AutoStartManagementActivity")))
                brand.contains("huawei") || brand.contains("honor") ->
                    candidates.add(0, Intent().setComponent(ComponentName(
                        "com.huawei.systemmanager",
                        ".startupmgr.ui.StartupNormalAppListActivity")))
                brand.contains("oppo") ->
                    candidates.add(0, Intent().setComponent(ComponentName(
                        "com.coloros.safecenter",
                        "com.coloros.safecenter.permission.startup.StartupAppListActivity")))
                brand.contains("vivo") ->
                    candidates.add(0, Intent().setComponent(ComponentName(
                        "com.vivo.permissionmanager",
                        "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")))
                brand.contains("samsung") ->
                    candidates.add(0, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.fromParts("package", packageName, null)))
            }
        } catch (e: Exception) {
            Log.w(TAG, "构造厂商自启页失败: ${e.message}")
        }
        for (intent in candidates) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return
            } catch (_: Exception) {
                continue
            }
        }
    }

    /** 初始化系统 TTS；失败就静默降级（App 不依赖语音可用性）。 */
    private fun initTts() {
        try {
            tts = TextToSpeech(this) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    try {
                        tts?.language = java.util.Locale.SIMPLIFIED_CHINESE
                        // 告警要压过声浪但别炸耳：走 ALARM 用途 + 0.9 音量。
                        tts?.setAudioAttributes(
                            android.media.AudioAttributes.Builder()
                                .setUsage(android.media.AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH)
                                .build())
                        tts?.setSpeechRate(1.05f)
                        ttsReady = true
                    } catch (e: Exception) {
                        Log.w(TAG, "TTS 配置失败: ${e.message}")
                    }
                } else {
                    Log.w(TAG, "TTS 不可用: $status")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "TTS 初始化异常: ${e.message}")
        }
    }

    private fun speak(text: String): Boolean {
        if (text.isBlank()) return false
        val engine = tts ?: return false
        if (!ttsReady) return false
        return try {
            engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "rev-alarm")
            true
        } catch (e: Exception) {
            Log.w(TAG, "TTS 播报失败: ${e.message}")
            false
        }
    }

    override fun onDestroy() {
        audioFocus?.abandon()
        try { tts?.stop(); tts?.shutdown() } catch (_: Exception) {}
        super.onDestroy()
    }

    /** Android 13+ 前台通知需要运行时授权。 */
    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            if (!granted) {
                requestPermissions(
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    reqNotifications,
                )
            }
        }
    }

    companion object {
        private const val TAG = "RevMainActivity"
    }
}
