import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/student_media.dart';

const kLessonPlaybackSpeeds = <double>[1.0, 1.25, 1.5, 2.0];

String lessonSpeedLabel(double speed) {
  if (speed == speed.roundToDouble()) return '${speed.toStringAsFixed(0)}x';
  return '${speed}x';
}

class LessonVideoControls extends StatelessWidget {
  const LessonVideoControls({
    super.key,
    required this.playing,
    required this.positionLabel,
    required this.durationLabel,
    required this.sliderValue,
    required this.playbackSpeed,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSpeed,
    required this.onFullscreen,
  });

  final bool playing;
  final String positionLabel;
  final String durationLabel;
  final double sliderValue;
  final double playbackSpeed;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSpeed;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: sliderValue.clamp(0.0, 1.0),
              onChanged: onSeek,
              activeColor: AppColors.orange,
              inactiveColor: Colors.white24,
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: playing ? 'Pause' : 'Play',
                onPressed: onPlayPause,
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
              ),
              Text(
                '$positionLabel / $durationLabel',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const Spacer(),
              PopupMenuButton<double>(
                tooltip: 'Speed',
                initialValue: playbackSpeed,
                color: AppColors.navyDark,
                onSelected: onSpeed,
                itemBuilder: (context) => [
                  for (final s in kLessonPlaybackSpeeds)
                    PopupMenuItem(
                      value: s,
                      child: Text(
                        lessonSpeedLabel(s),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: s == playbackSpeed
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text(
                    lessonSpeedLabel(playbackSpeed),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Fullscreen',
                onPressed: onFullscreen,
                icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String lessonClockFromFraction({
  required double fraction,
  required Duration duration,
}) {
  final ms = (duration.inMilliseconds * fraction.clamp(0.0, 1.0)).round();
  return formatMediaClock(Duration(milliseconds: ms));
}
