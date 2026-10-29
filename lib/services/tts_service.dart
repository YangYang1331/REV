import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 真实 TTS 语音播报服务（flutter_tts，走系统语音引擎）。
///
/// 用于 Trigger→Action 的 announce 动作（如水温过高、换挡提示）。
/// 单例；车机/手机系统自带 TTS 引擎即可发声，无需联网（中文引擎多数设备内置）。
/// 播报与声浪并行：TTS 走系统语音通道，会自动获得音频焦点，不影响引擎声。
class TtsService {
  TtsService._internal();
  static final TtsService instance = TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool _enabled = true;

  /// 初始化语音引擎：中文、适中语速、稍低音调（沉稳，不刺耳）。
  Future<void> init() async {
    if (_ready) return;
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(0.95);
      await _tts.setVolume(0.9);
      // 播报完即停，不占用音频焦点。
      await _tts.awaitSpeakCompletion(true);
      _ready = true;
    } catch (e) {
      // 部分设备无中文 TTS 引擎：退回英文尝试，仍失败则标记不可用（不崩溃）。
      debugPrint('TTS init zh-CN failed: $e');
      try {
        await _tts.setLanguage('en-US');
        _ready = true;
      } catch (e2) {
        debugPrint('TTS unavailable on this device: $e2');
        _ready = false;
      }
    }
  }

  bool get isEnabled => _enabled;
  bool get isAvailable => _ready;

  void setEnabled(bool v) => _enabled = v;

  /// 播报一段文字。未启用/引擎不可用时直接跳过（不抛错）。
  Future<void> speak(String text) async {
    if (!_enabled || text.isEmpty) return;
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    }
  }

  /// 停止当前播报。
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
