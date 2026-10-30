import 'dart:async';

import 'package:flutter/services.dart';

/// 语音播报（TTS）：走 MainActivity 里的原生 TextToSpeech 通道，
/// 不引入第三方依赖，也没有网络请求——说出来的只是本地拼好的短句。
///
/// 设计原则：**永不阻断数据流**。设备没有 TTS 引擎、通道不存在（桌面/测试环境）
/// 时全部静默降级，调用方无需 try/catch。
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  static const _ch = MethodChannel('rev/tts');

  bool _enabled = true;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastHash = 0;

  bool get enabled => _enabled;
  void setEnabled(bool v) => _enabled = v;

  /// 播报一句短提示。[force] 为 false 时，6 秒内同样的内容不会重复播。
  Future<void> speak(String text, {bool force = false}) async {
    if (!_enabled || text.trim().isEmpty) return;
    final now = DateTime.now();
    final h = text.hashCode;
    if (!force && h == _lastHash && now.difference(_lastAt).inSeconds < 6) return;
    _lastHash = h;
    _lastAt = now;
    try {
      await _ch.invokeMethod<void>('speak', {'text': text});
    } catch (_) {
      // 非 Android / 无引擎：忽略
    }
  }

  Future<void> stop() async {
    try {
      await _ch.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
