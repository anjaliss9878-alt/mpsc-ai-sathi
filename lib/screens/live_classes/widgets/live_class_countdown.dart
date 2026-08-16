import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Live-ticking countdown to [target], re-rendering once a second.
///
/// Purely a display widget — it never changes a class's `status` itself
/// (that stays admin/Firestore-driven), it just reflects time remaining.
class LiveClassCountdown extends StatefulWidget {
  const LiveClassCountdown({super.key, required this.target, this.compact = false});

  final DateTime target;

  /// Compact renders as a small inline chip (for list cards); the full
  /// version renders larger digit blocks (for the Join screen).
  final bool compact;

  @override
  State<LiveClassCountdown> createState() => _LiveClassCountdownState();
}

class _LiveClassCountdownState extends State<LiveClassCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration get _remaining {
    final diff = widget.target.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    if (remaining == Duration.zero) {
      return widget.compact
          ? const _CountdownChip(label: 'Starting now', color: AppColors.orange)
          : const _CountdownBlocks(days: 0, hours: 0, minutes: 0, seconds: 0, isStarting: true);
    }

    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    final seconds = remaining.inSeconds % 60;

    if (widget.compact) {
      final label = days > 0
          ? '${days}d ${_two(hours)}:${_two(minutes)}h'
          : '${_two(hours)}:${_two(minutes)}:${_two(seconds)}';
      return _CountdownChip(label: label, color: AppColors.navy);
    }

    return _CountdownBlocks(days: days, hours: hours, minutes: minutes, seconds: seconds);
  }

  String _two(int n) => n.toString().padLeft(2, '0');
}

class _CountdownChip extends StatelessWidget {
  const _CountdownChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class _CountdownBlocks extends StatelessWidget {
  const _CountdownBlocks({
    required this.days,
    required this.hours,
    required this.minutes,
    required this.seconds,
    this.isStarting = false,
  });

  final int days;
  final int hours;
  final int minutes;
  final int seconds;
  final bool isStarting;

  @override
  Widget build(BuildContext context) {
    if (isStarting) {
      return const Text(
        'वर्ग सुरू होत आहे... (Starting now)',
        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.orange, fontSize: 15),
      );
    }
    final units = <MapEntry<String, int>>[
      if (days > 0) MapEntry('Days', days),
      MapEntry('Hrs', hours),
      MapEntry('Min', minutes),
      MapEntry('Sec', seconds),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: units
          .expand(
            (unit) => [
              _Block(value: unit.value, label: unit.key),
              if (unit.key != units.last.key) const SizedBox(width: 8),
            ],
          )
          .toList(),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}
