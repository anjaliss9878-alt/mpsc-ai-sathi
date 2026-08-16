import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Play / Pause / Replay / Speed controls for the AI Lesson Player.
class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    super.key,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onRepeat,
    this.speed = 1.0,
    this.onSpeedChanged,
  });

  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onRepeat;
  final double speed;
  final ValueChanged<double>? onSpeedChanged;

  static const speeds = <double>[0.75, 0.9, 1.0, 1.25, 1.5];

  String _label(double s) {
    if (s == 1.0) return '1x';
    if (s == 0.75) return '0.75x';
    if (s == 1.25) return '1.25x';
    if (s == 1.5) return '1.5x';
    return '${s}x';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onPlayPause,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                label: Text(isPlaying ? 'Pause' : 'Play'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: onRepeat,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
              ),
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: const Text('Replay'),
            ),
          ],
        ),
        if (onSpeedChanged != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.speed_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              const Text(
                'Speed',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in speeds)
                      ChoiceChip(
                        label: Text(_label(s), style: const TextStyle(fontSize: 12)),
                        selected: speed == s,
                        onSelected: (_) => onSpeedChanged!(s),
                        visualDensity: VisualDensity.compact,
                        selectedColor: AppColors.orange.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                          color: speed == s ? AppColors.navy : AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
