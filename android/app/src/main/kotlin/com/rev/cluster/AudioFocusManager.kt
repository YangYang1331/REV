package com.rev.cluster

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.util.Log

/**
 * 音频焦点协调（v2.14.0）。
 *
 * 目标：引擎声浪作为"较低优先级"音频，与音乐/导航/来电共存：
 *  - 导航播报（AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK）→ duck 到 ~18%；
 *  - 来电（AUDIOFOCUS_LOSS_TRANSIENT）→ 暂时衰减/暂停，挂断恢复；
 *  - 其它媒体长时间占用（AUDIOFOCUS_LOSS）→ 让出声道；
 *  - 焦点归还（AUDIOFOCUS_GAIN）→ 恢复原音量。
 *
 * 本类只负责"申请焦点 + 监听变化并把事件回调给 Dart"。真正的音量缩放复用
 * 现有 EngineSoundService.setDucking()（不在此处改 engine_sound_service）。
 */
class AudioFocusManager(context: Context) {

    private val appCtx = context.applicationContext
    private val audioManager =
        appCtx.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var focusRequest: AudioFocusRequest? = null

    /** 焦点事件回调（主线程）：gain / duck / transient_loss / loss。 */
    var onEvent: ((String) -> Unit)? = null

    private val listener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        val ev = when (focusChange) {
            AudioManager.AUDIOFOCUS_GAIN -> "gain"
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> "duck"
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> "transient_loss"
            AudioManager.AUDIOFOCUS_LOSS -> "loss"
            else -> "gain"
        }
        Log.i(TAG, "audio focus change=$focusChange -> $ev")
        onEvent?.invoke(ev)
    }

    /** 申请焦点（引擎声浪开始时调用）。可重复调用，幂等。 */
    fun request(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(attrs)
                    .setWillPauseWhenDucked(false) // 自己用 setDucking 控制音量，不暂停
                    .setOnAudioFocusChangeListener(listener)
                    .build()
                focusRequest = req
                audioManager.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(
                    listener,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN,
                ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            }
        } catch (e: Exception) {
            Log.w(TAG, "request focus failed: ${e.message}")
            false
        }
    }

    /** 放弃焦点（App 退到后台 / 引擎声关闭时调用）。 */
    fun abandon() {
        try {
            val req = focusRequest
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && req != null) {
                audioManager.abandonAudioFocusRequest(req)
            } else {
                @Suppress("DEPRECATION")
                audioManager.abandonAudioFocus(listener)
            }
        } catch (e: Exception) {
            Log.w(TAG, "abandon focus failed: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "RevAudioFocus"
    }
}
