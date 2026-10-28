import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/core/vehicle/engine_pack_mapping.dart';
import 'package:obd_dashboard/core/vehicle/engine_sound_mapping.dart';

/// 一条振荡器声部：阶次 + 波形 + 播放句柄。
class _Voice {
  _Voice({required this.order, required this.isSaw});
  final double order;
  final bool isSaw;
  AudioSource? source;
  SoundHandle? handle;
}

/// 随发动机转速实时合成的模拟声浪（v2.10.0）。
///
/// 主力：flutter_soloud（SoLoud/miniaudio FFI）实时振荡器 + 噪声层，
/// 走一条独立 engineBus，与 audioplayers 的点火音/提示音/TTS 物理隔离。
/// 兜底：SoLoud 初始化失败时，自动退回 audioplayers 常驻循环
/// `assets/audio/idle_loop.wav`（保底=用户认可的「一直有声音」）。
///
/// 安全原则（2GB 车机）：
///  - 所有平台调用包 try/catch，任何异常静默降级，绝不闪退；
///  - init 只在进仪表盘时做一次，离开才 deinit，避免频繁 init/dispose；
///  - 声部数量恒定（5 个振荡器 + 1 路噪声），不动态增减；
///  - 全部参数 50ms 平滑插值后下发，杜绝拉链音/爆音。
class EngineSoundService {
  EngineSoundService._();
  static final EngineSoundService instance = EngineSoundService._();

  // ---- 运行态 ----
  bool _prefLoaded = false;
  bool _prefEnabled = false;
  bool _enteredDashboard = false;
  bool _active = false; // 已 start（voices 在跑或兜底循环在跑）
  bool _voicesRunning = false; // soloud 声部是否正在发声（熄火淡完后停）
  bool _soloudReady = false;
  bool _usingFallback = false;
  bool _ducking = false;

  EngineSoundMapper? _mapper;
  EngineSoundLifeMachine? _life;
  Timer? _pump;

  double _pendingRpm = 0;
  double _fade = 0; // 0..1 淡入/淡出
  double _fadeTarget = 1;

  // ---- SoLoud 对象 ----
  Bus? _bus;
  final List<_Voice> _voices = [
    _Voice(order: 0.5, isSaw: false),
    _Voice(order: 1.0, isSaw: false),
    _Voice(order: 2.0, isSaw: true),
    _Voice(order: 3.0, isSaw: true),
    _Voice(order: 4.0, isSaw: true),
  ];
  AudioSource? _noiseSource;
  SoundHandle? _noiseHandle;

  // ---- v2.11.0 多引擎采样包 ----
  List<EnginePackManifest> _packs = [];
  String _packId = 'synth';
  EnginePackManifest? _activePack;
  final EngineBandPlanner _planner = const EngineBandPlanner();
  EngineOneShotDecider? _decider;
  double _lastRpmForRate = 0;
  int _lastRpmAt = 0;
  double _drpmSmoothed = 0;

  /// band 循环源/句柄/平滑权重（key = band id）。
  final Map<String, AudioSource> _loopSources = {};
  final Map<String, SoundHandle> _loopHandles = {};
  final Map<String, double> _smoothWeights = {};
  final Map<String, double> _smoothSpeeds = {};

  /// 用户音质档位（auto/high/low），start() 时从 prefs 读。
  AudioQuality _audioQuality = AudioQuality.auto;

  /// one-shot 源（key = pop/blowoff/whine）。
  final Map<String, AudioSource> _oneShotSources = {};

  /// 当前是否走采样包路径（否则走振荡器合成 = id "synth"）。
  bool get _useSamplePack =>
      _activePack != null && !_activePack!.synthOnly && _loopSources.isNotEmpty;

  /// 供设置页读取全部包（manifest 未加载时返回空，页面自行刷新）。
  List<EnginePackManifest> get packs => List.unmodifiable(_packs);
  String get packId => _packId;

  // ---- 兜底 audioplayers ----
  // late 懒构造：仅在 SoLoud 初始化失败、真正走兜底循环时才创建 AudioPlayer，
  // 避免单元测试里引擎声懒加载即触发 audioplayers 平台通道 MissingPluginException。
  late final AudioPlayer _fbPlayer = AudioPlayer();

  /// 供设置页读取当前开关（未加载时返回 false）。
  bool get enabled => _prefEnabled;

  Future<void> _loadPref() async {
    if (_prefLoaded) return;
    _prefLoaded = true;
    try {
      _prefEnabled = await AppStore.instance.getEngineSoundEnabled();
      _packId = await AppStore.instance.getEnginePack();
      _audioQuality = parseAudioQuality(await AppStore.instance.getEngineAudioQuality());
    } catch (_) {
      _prefEnabled = false;
      _packId = 'synth';
    }
  }

  /// 加载采样包 manifest（assets/audio/packs/manifest.json）。任何失败返回空列表。
  Future<List<EnginePackManifest>> loadManifest() async {
    if (_packs.isNotEmpty) return _packs;
    try {
      final raw =
          await rootBundle.loadString('assets/audio/packs/manifest.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _packs = (decoded['packs'] as List<dynamic>? ?? [])
          .map((e) => EnginePackManifest.fromJson(e as Map<String, dynamic>))
          .where((p) => p.id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('engine pack manifest load failed (ignored): $e');
      _packs = [];
    }
    return _packs;
  }

  /// 设置页选包：持久化 + 若正在运行则热切换采样源。
  Future<void> selectPack(String id) async {
    _packId = id;
    try {
      await AppStore.instance.setEnginePack(id);
    } catch (_) {}
    if (_active) {
      await _reloadPackSources();
    }
  }

  /// 设置页音质档（auto/high/low）：持久化 + 热重载采样源（hi/lo 变化）。
  Future<void> setAudioQuality(String q) async {
    _audioQuality = parseAudioQuality(q);
    try {
      await AppStore.instance.setEngineAudioQuality(q);
    } catch (_) {}
    if (_active && _useSamplePack) {
      await _reloadPackSources();
    }
  }

  AudioQuality get audioQuality => _audioQuality;

  /// 设置页试听：播放该包怠速循环 2 秒后自动停（不影响仪表盘运行态）。
  Future<void> previewPack(String id) async {
    try {
      await _ensureSoloud();
      if (!_soloudReady) return;
      final bit = sampleBit(variant: _buildVariant, is32bit: _is32BitProcess(), quality: _audioQuality);
      final src = await SoLoud.instance.loadAsset(
          'assets/audio/packs/$id/$bit/loop_idle.m4a');
      final h = _bus?.play(src, volume: 0.5, looping: true);
      await Future.delayed(const Duration(seconds: 2));
      if (h != null) SoLoud.instance.stop(h);
      await SoLoud.instance.disposeSource(src);
    } catch (e) {
      debugPrint('preview pack failed (ignored): $e');
    }
  }

  /// 运行时判断 32 位进程（armv7 车机）→ lo 档。
  /// 构建变体（phone / car）：flutter --dart-define=BUILD_VARIANT=car 打出车机包。
  static const String _buildVariant =
      String.fromEnvironment('BUILD_VARIANT', defaultValue: 'phone');

  bool _is32BitProcess() => sizeOf<IntPtr>() == 4;

  /// 设置页开关变更：持久化 + 立即启停。
  Future<void> setEnabled(bool v) async {
    _prefLoaded = true;
    _prefEnabled = v;
    try {
      await AppStore.instance.setEngineSoundEnabled(v);
    } catch (_) {}
    if (v && _enteredDashboard) {
      await start();
    } else if (!v) {
      await stop();
    }
  }

  /// 进入仪表盘：建 mapper/状态机，开关打开则启动。
  Future<void> onEnterDashboard({
    required double idleRpm,
    required double redlineRpm,
  }) async {
    _enteredDashboard = true;
    _mapper = EngineSoundMapper(idleRpm: idleRpm, redlineRpm: redlineRpm);
    _life = EngineSoundLifeMachine(idleRpm: idleRpm);
    await _loadPref();
    if (_prefEnabled) await start();
  }

  /// 离开仪表盘：淡出→停声部→deinit。
  Future<void> onExitDashboard() async {
    _enteredDashboard = false;
    await stop();
    await _teardownSoloud();
  }

  /// TTS/语音播报期间 duck 到 ~18%，播完恢复。
  void setDucking(bool d) {
    _ducking = d;
  }

  /// 遥测每帧喂 rpm（real/gps/demo 统一；gps 即虚拟 rpm）。
  void feedFrame(double rpm, int nowMs) {
    if (!_active || _life == null || _mapper == null) return;
    _pendingRpm = rpm;
    // 采样模式：算 drpm/s 并跑 one-shot 决策。
    double drpmPerSec = 0;
    if (_lastRpmAt > 0) {
      final dt = (nowMs - _lastRpmAt) / 1000.0;
      if (dt > 0.01 && dt < 2) drpmPerSec = (rpm - _lastRpmForRate) / dt;
      _drpmSmoothed += (drpmPerSec - _drpmSmoothed) * 0.3;
    }
    _lastRpmForRate = rpm;
    _lastRpmAt = nowMs;
    try {
      final ev = _life!.update(rpm, nowMs);
      if (ev == EngineLifeEvent.becameOff) {
        // 熄火确认：淡出→停声部（但保持 entered，便于重新点火自动恢复）。
        _fadeTarget = 0;
      } else if (ev == EngineLifeEvent.becameAlive) {
        _mapper!.reset();
        _fadeTarget = 1;
        if (_soloudReady) {
          if (_useSamplePack) {
            // 采样循环一直在 bus 上（volume≈0），淡入即可。
          } else {
            _startVoicesLocked();
          }
        }
      }
      // one-shot 决策（放炮/泄压/机增）。
      if (_useSamplePack && _decider != null && _activePack != null) {
        for (final shot in _decider!.decide(
          rpm: rpm,
          drpmPerSec: drpmPerSec,
          nowMs: nowMs,
          pack: _activePack!,
        )) {
          final src = _oneShotSources[shot.name];
          if (src != null) {
            try {
              _bus?.play(src, volume: 0.7);
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  // ---- 启停 ----

  Future<void> start() async {
    if (_active) {
      if (_enteredDashboard) _fadeTarget = 1;
      return;
    }
    _active = true;
    _fade = 0;
    _fadeTarget = 1;

    // 1) 先试 SoLoud 主力。
    if (!await _ensureSoloud()) {
      await _teardownSoloud();
    }

    // 2) 先加载采样包 manifest（冷启动直接进仪表盘时设置页还没开过，
    //    _packs 必须在这里加载，否则选了真机包也会被退回合成）。
    await loadManifest();

    // 3) 按所选包装载发声源：采样包 → 循环段；否则 → 振荡器合成。
    if (_soloudReady) {
      await _reloadPackSources();
    }

    // 3) SoLoud 没起来 → 兜底 audioplayers 常驻循环。
    if (!_soloudReady) {
      try {
        await _fbPlayer.setReleaseMode(ReleaseMode.loop);
        await _fbPlayer.setVolume(0.6);
        await _fbPlayer.play(AssetSource('audio/idle_loop.wav'));
        _usingFallback = true;
      } catch (e) {
        debugPrint('fallback idle loop failed: $e');
      }
    }

    // 3) 50ms 参数泵。
    _pump?.cancel();
    _pump = Timer.periodic(const Duration(milliseconds: 50), (_) => _pumpTick());
  }

  /// 淡出声后停止（不 deinit，便于开关/熄火快速恢复）。
  Future<void> stop() async {
    if (!_active) return;
    _fadeTarget = 0;
    // 给一点淡出时间（200ms），再真正停。
    await Future.delayed(const Duration(milliseconds: 220));
    // 先把各采样循环音量归零（淡出窗口结束时确保无声）。
    try {
      for (final h in _loopHandles.values) {
        SoLoud.instance.setVolume(h, 0.0);
      }
    } catch (_) {}
    try {
      for (final v in _voices) {
        if (v.source != null) SoLoud.instance.stopAudioSource(v.source!);
      }
      if (_noiseSource != null) SoLoud.instance.stopAudioSource(_noiseSource!);
    } catch (_) {}
    _voicesRunning = false;
    // 停掉所有采样循环句柄（不关开关就不再响）；源不 dispose，便于快速重开。
    try {
      for (final h in _loopHandles.values) {
        SoLoud.instance.stop(h);
      }
    } catch (_) {}
    try {
      await _fbPlayer.stop();
    } catch (_) {}
    _usingFallback = false;
    _pump?.cancel();
    _pump = null;
    _active = false;
  }

  Future<void> _teardownSoloud() async {
    await _unloadSampleSources();
    try {
      for (final v in _voices) {
        if (v.source != null) {
          await SoLoud.instance.disposeSource(v.source!);
          v.source = null;
        }
      }
      if (_noiseSource != null) {
        await SoLoud.instance.disposeSource(_noiseSource!);
        _noiseSource = null;
      }
      _bus?.dispose();
      _bus = null;
      if (SoLoud.instance.isInitialized) {
        await SoLoud.instance.deinitAsync();
      }
    } catch (e) {
      debugPrint('soloud deinit failed (ignored): $e');
    }
    _soloudReady = false;
  }

  /// 在 engineBus 上启动全部声部（引擎 alive 且未在发声时调用）。
  void _startVoicesLocked() {
    if (!_soloudReady || _voicesRunning || _bus == null) return;
    try {
      final soloud = SoLoud.instance;
      for (final v in _voices) {
        if (v.source == null) continue;
        v.handle = _bus!.play(v.source!, volume: 0.0001);
        soloud.setWaveformFreq(v.source!, 40 * v.order);
      }
      if (_noiseSource != null) {
        _noiseHandle = _bus!.play(_noiseSource!,
            volume: 0.0001, looping: true);
      }
      _voicesRunning = true;
    } catch (e) {
      debugPrint('start voices failed: $e');
    }
  }

  /// 初始化 SoLoud + 建 engineBus（含合成用的 bus 低通）。失败返回 false。
  Future<bool> _ensureSoloud() async {
    try {
      final soloud = SoLoud.instance;
      if (!soloud.isInitialized) {
        await soloud.init(
          sampleRate: 22050, // 2GB 车机：低采样率省 CPU/内存
          bufferSize: 1024,
          channels: Channels.mono,
          lowLatency: true,
        );
      }
      _bus ??= soloud.createMixingBus(name: 'engine');
      if (!_bus!.isActive) {
        _bus!.playOnEngine(volume: 0.9);
      }
      try {
        _bus!.filters.biquadFilter.type().value = 0; // 0 = lowpass
        _bus!.filters.biquadFilter.resonance().value = 0.4;
      } catch (e) {
        debugPrint('bus filter init failed (ignored): $e');
      }
      _soloudReady = true;
      return true;
    } catch (e) {
      debugPrint('soloud init failed, fallback to audioplayers loop: $e');
      _soloudReady = false;
      return false;
    }
  }

  /// 按当前 _packId 重新装载发声源（合成 or 采样包）。
  Future<void> _reloadPackSources() async {
    if (!_soloudReady) return;
    // 双保险：任何路径进来（热切换/start/调试）都确保 manifest 已加载。
    if (_packs.isEmpty) await loadManifest();
    // 清旧源。
    await _unloadSampleSources();
    _activePack = resolveEnginePack(_packId, _packs);

    if (_activePack!.synthOnly || _packId == 'synth') {
      await _loadSynthSourcesLocked();
    } else {
      await _loadSampleSourcesLocked(_activePack!);
      // 采样装载失败（文件未就绪等）→ 静默退回合成。
      if (_loopSources.isEmpty) {
        await _loadSynthSourcesLocked();
      }
    }
  }

  /// 装载振荡器合成源（id="synth" / 兜底）。
  Future<void> _loadSynthSourcesLocked() async {
    try {
      final soloud = SoLoud.instance;
      for (final v in _voices) {
        v.source = await soloud.loadWaveform(
          v.isSaw ? WaveForm.saw : WaveForm.sin,
          false,
          1.0,
          0.0,
        );
      }
      // 噪声层：内存里合成一小段循环噪声 wav（完全本地，零版权素材）。
      try {
        _noiseSource ??= await soloud.loadMem(
          'engine_exhaust_noise.wav',
          _makeNoiseWav(),
        );
      } catch (e) {
        debugPrint('engine noise load failed (ignored): $e');
        _noiseSource = null;
      }
      _startVoicesLocked();
    } catch (e) {
      debugPrint('load synth sources failed (ignored): $e');
    }
  }

  /// 装载采样包 5 段循环 + one-shot。任何一段失败仅跳过该段；
  /// hi 档加载失败自动回退 lo 档再试一次，任何档都不能静默无声。
  Future<void> _loadSampleSourcesLocked(EnginePackManifest pack) async {
    final soloud = SoLoud.instance;

    /// 按当前档位加载某段资源；hi 失败自动降级 lo。
    Future<AudioSource> loadBand(String relPath) async {
      final wanted = sampleBit(
          variant: _buildVariant,
          is32bit: _is32BitProcess(),
          quality: _audioQuality);
      try {
        return await soloud.loadAsset(
            'assets/audio/packs/${pack.id}/$wanted/$relPath');
      } catch (e) {
        debugPrint('load $wanted/$relPath failed, fallback lo: $e');
        return await soloud.loadAsset(
            'assets/audio/packs/${pack.id}/lo/$relPath');
      }
    }

    final bands = <String>['idle', 'low', 'mid', 'high', 'bounce'];
    for (final band in bands) {
      if (!pack.bands.contains(band)) continue;
      try {
        final src = await loadBand('loop_$band.m4a');
        final h = _bus!.play(src, volume: 0.0001, looping: true);
        _loopSources[band] = src;
        _loopHandles[band] = h;
        _smoothWeights[band] = 0;
        _smoothSpeeds[band] = 1.0;
      } catch (e) {
        debugPrint('load loop $band failed (ignored): $e');
      }
    }
    // one-shot。
    for (final entry in {
      'pop': pack.hasPop,
      'blowoff': pack.hasBlowoff,
      'whine': pack.hasWhine,
    }.entries) {
      if (!entry.value) continue;
      try {
        _oneShotSources[entry.key] = await loadBand('one_${entry.key}.m4a');
      } catch (e) {
        debugPrint('load oneshot ${entry.key} failed (ignored): $e');
      }
    }
    _decider = EngineOneShotDecider();
    // 采样模式下合成声部全部停掉。
    try {
      for (final v in _voices) {
        if (v.source != null) soloud.stopAudioSource(v.source!);
      }
      if (_noiseSource != null) soloud.stopAudioSource(_noiseSource!);
    } catch (_) {}
    _voicesRunning = false;
  }

  Future<void> _unloadSampleSources() async {
    // 切换包/回收：先停旧句柄，杜绝残留叠音。
    try {
      for (final h in _loopHandles.values) {
        SoLoud.instance.stop(h);
      }
    } catch (_) {}
    _loopHandles.clear();
    try {
      for (final s in _loopSources.values) {
        await SoLoud.instance.disposeSource(s);
      }
      for (final s in _oneShotSources.values) {
        await SoLoud.instance.disposeSource(s);
      }
    } catch (_) {}
    _loopSources.clear();
    _smoothWeights.clear();
    _smoothSpeeds.clear();
    _oneShotSources.clear();
    // 合成源也一并回收，避免双路叠音。
    try {
      for (final v in _voices) {
        if (v.source != null) {
          await SoLoud.instance.disposeSource(v.source!);
          v.source = null;
        }
      }
      if (_noiseSource != null) {
        await SoLoud.instance.disposeSource(_noiseSource!);
        _noiseSource = null;
      }
    } catch (_) {}
    _voicesRunning = false;
  }

  // ---- 50ms 参数泵 ----

  void _pumpTick() {
    if (!_active || _mapper == null || _life == null) return;
    try {
      // 淡出接近完成且目标为 0 → 停声部一次。
      if (_fadeTarget == 0 && _fade < 0.03) {
        _fade = 0;
        if (_voicesRunning) {
          try {
            for (final v in _voices) {
              if (v.source != null) {
                SoLoud.instance.stopAudioSource(v.source!);
              }
            }
            if (_noiseSource != null) {
              SoLoud.instance.stopAudioSource(_noiseSource!);
            }
          } catch (_) {}
          _voicesRunning = false;
        }
        if (_usingFallback) {
          try {
            _fbPlayer.setVolume(0.0);
          } catch (_) {}
        }
        return;
      }

      // 淡出中：还没淡完就直接降到目标 0，不再 plan。
      final params = _mapper!.plan(_pendingRpm, 50.0);

      // 淡入/淡出斜坡（约 1.2s 进 / 0.25s 出）。
      final ramp = _fadeTarget == 1 ? 0.04 : 0.2;
      _fade += (_fadeTarget - _fade) * ramp;
      _fade = _fade.clamp(0.0, 1.0);

      final duck = _ducking ? 0.18 : 1.0;
      final master = params.masterGain * _fade * duck;

      if (_useSamplePack) {
        // 采样包模式：band 权重 50ms 平滑后下发各循环音量；
        // 同时按 band 内连续变调（setRelativePlaySpeed）让转速同步变尖。
        final w = _planner.plan(
            _pendingRpm, _mapper!.idleRpm, _mapper!.redlineRpm);
        final bounce = _planner.bounceWeight(
            _drpmSmoothed, _pendingRpm, _mapper!.idleRpm);
        final span = (_mapper!.redlineRpm - _mapper!.idleRpm).abs();
        final t = span <= 0.0
            ? 0.0
            : ((_pendingRpm - _mapper!.idleRpm) / span).clamp(0.0, 1.0);
        for (final band in const ['idle', 'low', 'mid', 'high', 'bounce']) {
          final handle = _loopHandles[band];
          if (handle == null) continue;
          var target = w[band];
          if (band == 'bounce') target = bounce;
          final cur = (_smoothWeights[band] ?? 0.0) +
              (target - (_smoothWeights[band] ?? 0.0)) * 0.25;
          _smoothWeights[band] = cur;
          try {
            SoLoud.instance.setVolume(
                handle, (cur * _fade * duck * 0.85).clamp(0.0, 1.0));
          } catch (_) {}
          // band 内连续变调（0.2 系数平滑防拉链）。
          final targetSpeed = _planner.bandPlaySpeed(band: band, t: t);
          final spd = (_smoothSpeeds[band] ?? 1.0) +
              (targetSpeed - (_smoothSpeeds[band] ?? 1.0)) * 0.2;
          _smoothSpeeds[band] = spd;
          try {
            SoLoud.instance.setRelativePlaySpeed(handle, spd);
          } catch (_) {}
        }
      } else if (_soloudReady && _voicesRunning) {
        final soloud = SoLoud.instance;
        for (final v in _voices) {
          if (v.source == null || (v.handle?.id ?? 0) <= 0) continue;
          final gain = params.harmonicGains[v.order] ?? 0.2;
          try {
            soloud.setWaveformFreq(v.source!, params.fundamentalHz * v.order);
            soloud.setVolume(v.handle!, (gain * master * 0.5).clamp(0.0, 1.0));
          } catch (_) {}
        }
        if (_noiseSource != null && (_noiseHandle?.id ?? 0) > 0) {
          try {
            soloud.setVolume(
                _noiseHandle!, (params.noiseLevel * master).clamp(0.0, 1.0));
          } catch (_) {}
        }
        // bus 低通截止随 rpm 抬升（失败静默忽略）。
        try {
          _bus?.filters.biquadFilter.frequency().value =
              params.noiseCutoffHz;
        } catch (_) {}
      } else if (_usingFallback) {
        // 兜底：循环怠速声，用 playbackRate 随 rpm 粗略变调。
        try {
          final rate = (params.fundamentalHz / 40.0).clamp(0.7, 1.8);
          _fbPlayer.setPlaybackRate(rate);
          _fbPlayer.setVolume(0.6 * _fade * duck);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('engine sound pump failed (ignored): $e');
    }
  }

  /// 本地程序化生成一小段低通噪声 wav（16-bit PCM mono 22050Hz，2s）。
  /// 完全本地合成、零版权采样；噪声循环即使有轻微接缝也听不出来。
  Uint8List _makeNoiseWav() {
    const sr = 22050;
    const seconds = 2;
    const n = sr * seconds;
    final pcm = Int16List(n);
    final rnd = math.Random(20260101);
    double lp = 0;
    for (var i = 0; i < n; i++) {
      final white = rnd.nextDouble() * 2 - 1;
      lp = 0.94 * lp + 0.06 * white; // 单极低通，偏排气噗噗声
      pcm[i] = ((lp * 4.0) * 32767).round().clamp(-32768, 32767);
    }
    final byteData = ByteData(44 + pcm.length * 2);
    void u32(int o, int v) => byteData.setUint32(o, v, Endian.little);
    void u16(int o, int v) => byteData.setUint16(o, v, Endian.little);
    byteData.setUint8(0, 0x52); // "RIFF"
    byteData.setUint8(1, 0x49);
    byteData.setUint8(2, 0x46);
    byteData.setUint8(3, 0x46);
    u32(4, 36 + pcm.length * 2);
    byteData.setUint8(8, 0x57); // "WAVE"
    byteData.setUint8(9, 0x41);
    byteData.setUint8(10, 0x56);
    byteData.setUint8(11, 0x45);
    byteData.setUint8(12, 0x66); // "fmt "
    byteData.setUint8(13, 0x6D);
    byteData.setUint8(14, 0x74);
    byteData.setUint8(15, 0x20);
    u32(16, 16);
    u16(20, 1); // PCM
    u16(22, 1); // mono
    u32(24, sr);
    u32(28, sr * 2);
    u16(32, 2);
    u16(34, 16);
    byteData.setUint8(36, 0x64); // "data"
    byteData.setUint8(37, 0x61);
    byteData.setUint8(38, 0x74);
    byteData.setUint8(39, 0x61);
    u32(40, pcm.length * 2);
    for (var i = 0; i < pcm.length; i++) {
      byteData.setInt16(44 + i * 2, pcm[i], Endian.little);
    }
    return byteData.buffer.asUint8List();
  }
}
