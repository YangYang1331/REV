import 'package:flutter/material.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/models/obd_data.dart';

/// ECO 驾驶实时提示条：根据节气门 / 负荷 / 转速 / 瞬时油耗给出中文建议。
/// 纯展示组件，不持有状态，随遥测帧重建。
class EcoTipBar extends StatelessWidget {
  const EcoTipBar({super.key, required this.data, required this.skin});

  final ObdData data;
  final SkinDescriptor skin;

  @override
  Widget build(BuildContext context) {
    final tip = _evaluate(data);
    final color = switch (tip.level) {
      _EcoLevel.good => skin.ok,
      _EcoLevel.warn => skin.warn,
      _EcoLevel.bad => skin.bad,
      _EcoLevel.info => skin.accent2,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          Icon(tip.icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tip.text,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  _EcoTip _evaluate(ObdData d) {
    // 怠速
    if (d.rpm > 0 && d.rpm < 900 && d.speed < 5) {
      return _EcoTip(_EcoLevel.warn, Icons.timer,
          '怠速状态：长时间怠速很费油，等待超过 1 分钟建议熄火');
    }
    // 急加速
    final throttle = d.throttle;
    if (throttle != null && throttle > 70) {
      return _EcoTip(_EcoLevel.bad, Icons.flash_on,
          '急加速！缓踩油门、提前收油，油耗立降');
    }
    // 负荷过大
    final load = d.load;
    if (load != null && load > 80) {
      return _EcoTip(_EcoLevel.warn, Icons.warning_amber,
          '发动机负荷过大，避免满载大脚油门');
    }
    // 转速过高
    if (d.rpm > 3000 && d.speed > 20) {
      return _EcoTip(_EcoLevel.warn, Icons.upgrade,
          '转速偏高，及时升挡（自动挡温柔给油）更省油');
    }
    // 瞬时油耗偏高
    final l100 = d.fuelL100;
    if (l100 != null && l100 > 12) {
      return _EcoTip(_EcoLevel.warn, Icons.local_gas_station,
          '当前油耗 ${l100.toStringAsFixed(1)} L/100，保持匀速可明显下降');
    }
    // 匀速良好
    if (d.speed > 30 &&
        throttle != null &&
        throttle < 30 &&
        l100 != null &&
        l100 < 8) {
      return _EcoTip(_EcoLevel.good, Icons.eco,
          '匀速行驶良好，保持当前节奏就是最省的开法');
    }
    // 默认
    return _EcoTip(_EcoLevel.info, Icons.lightbulb_outline,
        '平稳给油、预判路况提前收油滑行，油耗更漂亮');
  }
}

enum _EcoLevel { good, warn, bad, info }

class _EcoTip {
  const _EcoTip(this.level, this.icon, this.text);
  final _EcoLevel level;
  final IconData icon;
  final String text;
}
