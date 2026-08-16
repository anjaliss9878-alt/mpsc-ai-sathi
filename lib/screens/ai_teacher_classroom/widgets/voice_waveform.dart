import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/classroom_avatar.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Standalone voice-waveform visualizer strip, shown under the avatar next
/// to the Subtitle Area. Bars animate continuously; amplitude/color depend
/// on [state] — tall orange bars while listening (student's mic input),
/// medium navy bars while speaking (teacher's voice), a near-flat line at
/// idle. Entirely a placeholder: no real audio is analyzed.
class VoiceWaveform extends StatefulWidget {
  const VoiceWaveform({super.key, required this.state, this.barCount = 28});

  final TeacherAvatarState state;
  final int barCount;

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant VoiceWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncTicker();
  }

  void _syncTicker() {
    final active = widget.state == TeacherAvatarState.listening ||
        widget.state == TeacherAvatarState.speaking;
    if (active) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.state) {
      TeacherAvatarState.listening => AppColors.orange,
      TeacherAvatarState.speaking => AppColors.navy,
      TeacherAvatarState.thinking => AppColors.textSecondary,
      TeacherAvatarState.idle => AppColors.navy.withValues(alpha: 0.25),
    };
    final active = widget.state == TeacherAvatarState.listening ||
        widget.state == TeacherAvatarState.speaking;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.barCount, (i) {
              final phase = t * 2 * math.pi + i * 0.45;
              final wobble = (math.sin(phase) + 1) / 2;
              final amplitude = active ? (0.15 + 0.85 * wobble) : 0.08;
              return Container(
                width: 3.2,
                height: 36 * amplitude,
                margin: const EdgeInsets.symmetric(horizontal: 1.6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
