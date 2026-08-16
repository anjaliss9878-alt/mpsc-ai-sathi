import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// VM placeholder — real players live in io/web implementations.
class LessonVideoSurface extends StatelessWidget {
  const LessonVideoSurface({
    super.key,
    required this.playbackUrl,
    this.isYoutube = false,
    this.startFraction = 0,
    this.playbackSpeed = 1.0,
    this.thumbnailUrl = '',
    this.onProgress,
  });

  final String playbackUrl;
  final bool isYoutube;
  final double startFraction;
  final double playbackSpeed;
  final String thumbnailUrl;
  final void Function(double fraction, double speed, {required bool completed})?
      onProgress;

  @override
  Widget build(BuildContext context) {
    return const AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: AppColors.navyDark,
        child: Center(
          child: Icon(Icons.play_circle_fill_rounded, color: Colors.white54, size: 56),
        ),
      ),
    );
  }
}
