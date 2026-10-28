import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:obd_dashboard/services/engine_sound_service.dart';

/// 音频焦点桥（v2.14.0）。
///
/// 原生层（AudioFocusManager）监听系统 AUDIOFOCUS 变化，通过 EventChannel
/// `rev/audio_focus` 把事件推到 Dart；这里只做一件事——把焦点事件翻译成
/// 现有 EngineSoundService.setDucking()（**不改 engine_sound_service.dart**）：
///  - 导航播报 ducking / 来电 transient_loss / 其它媒体抢占 loss → 退到 ~18%；
///  - 焦点归还 gain → 恢复原音量。
/// 与音乐共存：我们以 USAGE_MEDIA 申请焦点，音乐保持播放、被适度压低。
class AudioFocusBridge {
  AudioFocusBridge._();
  static final AudioFocusBridge instance = AudioFocusBridge._();

  static const _channel = EventChannel('rev/audio_focus');
  StreamSubscription<dynamic>? _sub;

  /// App 启动时调用一次：订阅原生焦点事件流。
  void init() {
    if (_sub != null) return;
    try {
      _sub = _channel.receiveBroadcastStream().listen(_onEvent, onError: (e) {
        debugPrint('audio focus stream error (ignored): $e');
      });
    } catch (e) {
      debugPrint('audio focus bridge init failed (ignored): $e');
    }
  }

  void _onEvent(dynamic ev) {
    if (ev is! String) return;
    try {
      switch (ev) {
        case 'duck':
        case 'transient_loss':
        case 'loss':
          // 导航播报 / 来电 / 其它媒体抢占：衰减引擎声。
          EngineSoundService.instance.setDucking(true);
        case 'gain':
          // 焦点归还：恢复。
          EngineSoundService.instance.setDucking(false);
      }
    } catch (e) {
      debugPrint('apply ducking failed (ignored): $e');
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
