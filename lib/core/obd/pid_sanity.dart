/// PID 读数合理性校验纯逻辑（无 IO，可单测）。
///
/// 真实车上偶发：CAN 总线毛刺、BLE 分包错位、劣质 ELM 克隆固件回串
/// → 一帧里 rpm 跳到 3 万、水温 -100℃、速度 -5 km/h。
/// 旧版直接把脏值推到仪表盘，造成"指针飞天"。
/// 本模块提供两级过滤：
///  1. [isPhysicallyPlausible] —— 单帧物理范围检查；
///  2. [isDeltaPlausible]      —— 与上一帧比对，跳变超过物理可能速率判坏帧。
library;

import 'package:obd_dashboard/core/obd/obd_pid.dart';

/// 单 PID 物理合理区间（基于 SAE J1979 + 马自达6 2.0L 实际工况）。
///
/// 注：温度类 ECU 原始值 0x00 解码后 = -40℃（合法"未定义"哨兵），
/// 但真实水温低于 -40 必然是坏帧；速度 / 负荷 / 油门不可能为负。
class PidSanity {
  const PidSanity._();

  /// 单帧物理范围：返回 true 表示该值在物理可能区间内。
  static bool isPhysicallyPlausible(Pid pid, double v) {
    if (v.isNaN || v.isInfinite) return false;
    switch (pid) {
      case Pid.rpm:
        // 马6 2.0L 红线 ≈ 6500，怠速 ~700；允许到 9000 留冗余。
        return v >= 0 && v <= 9000;
      case Pid.speed:
        return v >= 0 && v <= 260;
      case Pid.coolant:
      case Pid.intakeTemp:
      case Pid.ambient:
        // -40 是 ECU 未定义哨兵，允许；真水温极少 > 150。
        return v >= -40 && v <= 150;
      case Pid.engineLoad:
      case Pid.throttle:
      case Pid.fuelLevel:
      case Pid.absLoad:
        return v >= 0 && v <= 100;
      case Pid.map:
        // 进气歧管绝对压力 kPa：怠速 ~30，大气压 ~100，增压到 250。
        return v >= 10 && v <= 250;
      case Pid.maf:
        return v >= 0 && v <= 150;
      case Pid.fuelRate:
        return v >= 0 && v <= 80;
      case Pid.ltft:
        // 长期燃油修正 ±30% 为常见窗口。
        return v >= -30 && v <= 30;
      case Pid.ignAdv:
        return v >= -30 && v <= 50;
      case Pid.catTemp:
        return v >= -40 && v <= 1000;
      case Pid.fuelRail:
        return v >= 0 && v <= 30; // MPa
      case Pid.voltage:
        return v >= 6 && v <= 16;
    }
  }

  /// 与上一帧比对的跳变阈值（每轮轮询约 50~200ms）。
  /// 返回 true 表示跳变在物理可能速率内。
  static bool isDeltaPlausible(Pid pid, double? prev, double now) {
    if (prev == null) return true; // 首帧无基线，放行
    final d = (now - prev).abs();
    switch (pid) {
      case Pid.rpm:
        // 0.1~0.2s 内转速突变 > 2000 rpm 物理不可能（发动机惯量）。
        return d <= 2000;
      case Pid.speed:
        // 0.1s 内车速突变 > 20 km/h 不可能（急刹车 g≈2 也只 ~7 km/h/0.1s）。
        return d <= 25;
      case Pid.coolant:
      case Pid.intakeTemp:
      case Pid.ambient:
      case Pid.catTemp:
        return d <= 20; // 温度不会瞬间变 20℃
      case Pid.engineLoad:
      case Pid.throttle:
      case Pid.fuelLevel:
      case Pid.absLoad:
        return d <= 40; // 油门/负荷 0.1s 内跳 40% 可能（地板油），再大即坏帧
      case Pid.map:
        return d <= 80;
      case Pid.maf:
        return d <= 50;
      case Pid.fuelRate:
        return d <= 40;
      case Pid.ltft:
        return d <= 10;
      case Pid.ignAdv:
        return d <= 20;
      case Pid.fuelRail:
        return d <= 5;
      case Pid.voltage:
        // 电瓶电压跳动 > 2V 基本是采样毛刺。
        return d <= 2.5;
    }
  }

  /// 综合判定：物理范围 + 跳变。prev 为 null 时只查物理范围。
  /// 返回 false 时调用方应丢弃该帧该 PID。
  static bool accept(Pid pid, double? prev, double now) {
    if (!isPhysicallyPlausible(pid, now)) return false;
    if (!isDeltaPlausible(pid, prev, now)) return false;
    return true;
  }
}

/// Mode 03 / Mode 04 纯逻辑。
///
/// Mode 03 正响应格式（ISO15765 CAN，ATH0 关头后）：
///   `43 <count> <code1A><code1B> <code2A><code2B> ...`
/// 每个 DTC 占 2 字节，按 SAE J2012 拼成 `P/C/B/Uxxxx`。
/// 首字节高 2 位决定字母：
///   00 → P（动力），01 → C（底盘），10 → B（车身），11 → U（网络）。
class DtcCodec {
  const DtcCodec._();

  /// Mode 04 清码命令字（ELM 习惯写法 "04"，不带 mode 前缀空格）。
  static const String clearCommand = '04';

  /// Mode 03 读码命令字。
  static const String readCommand = '03';

  /// Mode 03 正响应标记。
  static const String positiveMarker = '43';

  /// 解析 Mode 03 正响应为 DTC 字符串列表。
  /// 兼容带响应头（43 后字节数）与紧凑拼接；非法段跳过，绝不抛。
  static List<String> parseMode03(String raw) {
    var s = raw
        .toUpperCase()
        .replaceAll(RegExp(r'[^0-9A-F]'), '');
    if (!s.startsWith(positiveMarker)) return const [];
    s = s.substring(2);
    // 首字节是 DTC 数量（可选字段，部分固件省略）。
    // 策略：先尝试"首字节=count"；若剩余字节数 != count*2，回退到"无 count 头"。
    if (s.length >= 2) {
      final count = int.tryParse(s.substring(0, 2), radix: 16) ?? 0;
      final withCount = _decodePairs(s.substring(2), count);
      if (withCount.isNotEmpty || count == 0) {
        // count==0 时 withCount 为空，但"无 count 头"路径也会得到空
        // —— 优先信任 count 字段（ECU 明确说没码）。
        if (count == 0 || withCount.isNotEmpty) return withCount;
      }
    }
    return _decodePairs(s, null);
  }

  /// 从字节流里两两切 DTC；[expected] 为 null 表示切到尾。
  static List<String> _decodePairs(String hex, int? expected) {
    final out = <String>[];
    var pos = 0;
    while (pos + 4 <= hex.length) {
      final b0 = int.tryParse(hex.substring(pos, pos + 2), radix: 16);
      final b1 = int.tryParse(hex.substring(pos + 2, pos + 4), radix: 16);
      pos += 4;
      if (b0 == null || b1 == null) continue;
      if (b0 == 0 && b1 == 0) continue; // 填充字节
      out.add(_encodeDtc(b0, b1));
      if (expected != null && out.length >= expected) break;
    }
    return out;
  }

  /// 两字节 → SAE J2012 五字符码。
  /// b0 高 2 位 = 字母前缀；b0 低 6 位 + b1 = 四位数字（十六进制显示）。
  static String _encodeDtc(int b0, int b1) {
    const letters = ['P', 'C', 'B', 'U'];
    final family = (b0 >> 6) & 0x03;
    final high = (b0 >> 4) & 0x03; // b0 中间两位 → 第一位数字
    final d1 = (b0 & 0x0F).toRadixString(16).toUpperCase();
    final d2 = (b1 >> 4).toRadixString(16).toUpperCase();
    final d3 = (b1 & 0x0F).toRadixString(16).toUpperCase();
    return '${letters[family]}$high$d1$d2$d3';
  }
}
