import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obd_dashboard/core/skin/skin_descriptor.dart';
import 'package:obd_dashboard/core/skin/skin_provider.dart';
import 'package:obd_dashboard/services/alarm_service.dart';

/// 顶部报警横幅：水温/油温/电压/超速触发时滑入一条提示，6 秒后自动收起。
///
/// 语音与提示音由 [AlarmService] 统一负责，这里只做"看得见"的一层，
/// 点击可立刻收起（记录仍保留在 设置 → 报警与语音 里）。
class AlarmBanner extends ConsumerStatefulWidget {
  const AlarmBanner({super.key});

  @override
  ConsumerState<AlarmBanner> createState() => _AlarmBannerState();
}

class _AlarmBannerState extends ConsumerState<AlarmBanner> {
  AlarmEvent? _ev;
  bool _shown = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    AlarmService.instance.last.addListener(_onEvent);
    _onEvent();
  }

  @override
  void dispose() {
    AlarmService.instance.last.removeListener(_onEvent);
    _timer?.cancel();
    super.dispose();
  }

  void _onEvent() {
    final ev = AlarmService.instance.last.value;
    if (!mounted || ev == null) {
      if (mounted) setState(() => _shown = false);
      return;
    }
    if (identical(ev, _ev) && _shown) return;
    _timer?.cancel();
    setState(() {
      _ev = ev;
      _shown = true;
    });
    _timer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _shown = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(skinProvider);
    final ev = _ev;
    return IgnorePointer(
      ignoring: !_shown || ev == null,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, -1.2),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _card(skin, ev),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(SkinDescriptor skin, AlarmEvent? ev) {
    final critical = ev?.critical ?? false;
    final accent = critical ? skin.bad : skin.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          alarmDismiss();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1218).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(critical ? Icons.warning_amber_rounded : Icons.info_outline,
                  color: accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(ev?.title ?? '',
                        style: TextStyle(
                            color: accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    if ((ev?.detail ?? '').isNotEmpty)
                      Text(ev!.detail,
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('点击收起',
                  style: TextStyle(color: Colors.white24, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  void alarmDismiss() {
    _timer?.cancel();
    setState(() => _shown = false);
    AlarmService.instance.clearBanner();
  }
}
