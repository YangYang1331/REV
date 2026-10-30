import 'package:flutter/foundation.dart';
import 'package:obd_dashboard/core/store/app_store.dart';
import 'package:obd_dashboard/models/obd_data.dart';
import 'package:obd_dashboard/services/sound_service.dart';
import 'package:obd_dashboard/services/voice_service.dart';

enum AlarmKind { coolant, oil, voltageLow, voltageHigh, speed, rpm, dataLost }

class AlarmEvent {
  const AlarmEvent({
    required this.kind,
    required this.title,
    required this.detail,
    required this.ts,
    this.critical = false,
  });
  final AlarmKind kind;
  final String title;
  final String detail;
  final int ts;
  final bool critical;
}

/// 行车报警：阈值判断 + 提示音 + 语音播报 + 最近记录。
///
/// 与仪表盘的红屏/边角闪烁互补：那两者是"看得见"，这里是"听得见 + 可回看"。
/// 所有阈值都可在设置里改，且都有 60 秒冷却（避免一路狂叫）；
/// 严重项（水温过高、电压过低）10 秒重复提醒一次，直到恢复正常。
class AlarmService extends ChangeNotifier {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  // ── 可配置项（默认值按民用车保守设定）──
  bool enabled = true;
  bool voice = true;
  bool soundEnabled = true;
  int coolantHighC = 105;
  int oilHighC = 130;
  double voltageLowV = 11.8;
  double voltageHighV = 15.2;

  /// 超速阈值，0 = 不报警（与仪表盘限速提醒共用 AppStore 里的值）。
  int speedLimitKmh = 0;

  int redlineRpm = 6500;

  final List<AlarmEvent> _log = [];
  List<AlarmEvent> get log => List.unmodifiable(_log);

  /// 最近一次事件（UI 横幅监听它）。
  final ValueNotifier<AlarmEvent?> last = ValueNotifier(null);

  final Map<AlarmKind, int> _lastAt = {};
  bool _restored = false;

  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final p = await AppStore.instance.loadAlarmConfig();
      enabled = p.enabled;
      voice = p.voice;
      soundEnabled = p.sound;
      coolantHighC = p.coolantHighC;
      oilHighC = p.oilHighC;
      voltageLowV = p.voltageLowV;
      voltageHighV = p.voltageHighV;
      speedLimitKmh = p.speedLimitKmh;
      VoiceService.instance.setEnabled(voice);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> save() async {
    VoiceService.instance.setEnabled(voice);
    await AppStore.instance.saveAlarmConfig(AlarmConfig(
      enabled: enabled,
      voice: voice,
      sound: soundEnabled,
      coolantHighC: coolantHighC,
      oilHighC: oilHighC,
      voltageLowV: voltageLowV,
      voltageHighV: voltageHighV,
      speedLimitKmh: speedLimitKmh,
    ));
    notifyListeners();
  }

  /// 每帧调用；演示数据不报警（避免演示时乱叫）。
  void feed(ObdData d) {
    if (!enabled || !d.connected) return;
    if (d.source == 'demo') return;
    final now = DateTime.now().millisecondsSinceEpoch;

    final cool = d.coolant;
    if (cool != null && cool >= coolantHighC) {
      _fire(AlarmKind.coolant, '水温过高', '${cool.toStringAsFixed(0)}℃，已超 ${coolantHighC}℃', now,
          critical: true, repeatSec: 10);
    }
    final oil = d.oilTemp;
    if (oil != null && oil >= oilHighC) {
      _fire(AlarmKind.oil, '机油温度过高', '${oil.toStringAsFixed(0)}℃，已超 ${oilHighC}℃', now,
          critical: true, repeatSec: 15);
    }
    final v = d.voltage;
    if (v != null && v > 0.5 && v < voltageLowV) {
      _fire(AlarmKind.voltageLow, '电压过低', '${v.toStringAsFixed(1)}V，低于 ${voltageLowV.toStringAsFixed(1)}V', now,
          critical: true, repeatSec: 20);
    } else if (v != null && v > voltageHighV) {
      _fire(AlarmKind.voltageHigh, '电压过高', '${v.toStringAsFixed(1)}V，高于 ${voltageHighV.toStringAsFixed(1)}V', now,
          critical: true, repeatSec: 20);
    }
    if (speedLimitKmh > 0 && d.speed > speedLimitKmh + 5) {
      _fire(AlarmKind.speed, '超速', '${d.speed.toStringAsFixed(0)} km/h（限速 $speedLimitKmh）', now,
          repeatSec: 30);
    }
    if (d.rpm >= redlineRpm) {
      _fire(AlarmKind.rpm, '转速逼近红线', '${d.rpm} rpm', now, repeatSec: 30);
    }
  }

  void _fire(AlarmKind kind, String title, String detail, int now,
      {bool critical = false, int repeatSec = 60}) {
    final lastAt = _lastAt[kind] ?? 0;
    if (now - lastAt < repeatSec * 1000) return;
    _lastAt[kind] = now;

    final ev = AlarmEvent(
        kind: kind, title: title, detail: detail, ts: now, critical: critical);
    _log.insert(0, ev);
    if (_log.length > 30) _log.removeRange(30, _log.length);
    last.value = ev;
    notifyListeners();

    if (soundEnabled) {
      try {
        SoundService.instance.playAlert();
      } catch (_) {}
    }
    if (voice) {
      VoiceService.instance.speak('$title，$detail');
    }
  }

  /// 手动消掉横幅（不清记录）。
  void clearBanner() => last.value = null;

  void clearLog() {
    _log.clear();
    notifyListeners();
  }
}
