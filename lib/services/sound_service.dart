import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/services/engine_sound_service.dart';

/// 音效反馈：连接成功提示音 + 告警（重触感 + 提示音，节流）。
/// 受 AppStore 音效开关控制。
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  final AudioPlayer _player = AudioPlayer();

  /// 开屏氛围音专用播放器：与点火轰鸣/提示音分轨，互不打断。
  final AudioPlayer _splashPlayer = AudioPlayer();
  bool _enabled = true;
  Future<void>? _initFuture;
  DateTime? _lastAlertAt;

  bool get enabled => _enabled;

  /// 启动时从本地设置加载开关（并发调用共享同一个 Future）。
  Future<void> init() => _initFuture ??= _loadEnabled();

  Future<void> _loadEnabled() async {
    try {
      _enabled = await AppStore.instance.getSoundEnabled();
    } catch (_) {
      _enabled = true;
    }
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    try {
      await AppStore.instance.setSoundEnabled(v);
    } catch (_) {}
    if (!v) {
      try {
        await _player.stop();
      } catch (_) {}
      try {
        await _splashPlayer.stop();
      } catch (_) {}
    }
  }

  Future<void> _playAsset(String asset) async {
    await init();
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.play(AssetSource(asset));
    } catch (e) {
      debugPrint('sound play failed: $e');
    }
  }

  Future<void> _play() => _playAsset('audio/bluetooth_connected.wav');

  /// 开屏氛围音：原创 4.0s 合成音轨（低频铺垫 → 点火 → 标题重音 → 冲刺 → 收尾）。
  /// 与点火轰鸣分属两个播放器，1.05s 点火时不会截断氛围音。
  Future<void> playSplashBed() async {
    await init();
    if (!_enabled) return;
    try {
      await _splashPlayer.stop();
      await _splashPlayer.play(
        AssetSource('audio/splash_bed.wav'),
        volume: 0.62,
      );
    } catch (e) {
      debugPrint('splash bed play failed: $e');
    }
  }

  Future<void> stopSplashBed() async {
    try {
      await _splashPlayer.stop();
    } catch (_) {}
  }

  /// 开屏点火轰鸣（起动机→点火→怠速，约 3.0s）。
  /// 与全局音效开关联动：关闭时直接 return 静音；播放前停掉旧音，避免叠音。
  Future<void> playEngineStart() => _playAsset('audio/engine_start.wav');

  /// 连接成功提示音。
  Future<void> playConnected() => _play();

  /// 告警：重触感 + 提示音，至少间隔 2 秒一次，避免刷屏。
  Future<void> playAlert() async {
    if (!_enabled) return;
    final now = DateTime.now();
    if (_lastAlertAt != null &&
        now.difference(_lastAlertAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastAlertAt = now;
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
    await _play();
  }

  /// TTS/语音播报期间把模拟声浪 duck 到 ~18%，播报结束恢复。
  /// audioplayers（点火音/提示音/TTS）与 flutter_soloud（声浪 engineBus）
  /// 是两套独立音频引擎，各走各的通道，这里只做音量避让，不互相截断。
  void duckEngineSound(bool duck) {
    try {
      EngineSoundService.instance.setDucking(duck);
    } catch (_) {}
  }

  void dispose() {
    try {
      _player.dispose();
    } catch (_) {}
    try {
      _splashPlayer.dispose();
    } catch (_) {}
  }
}
