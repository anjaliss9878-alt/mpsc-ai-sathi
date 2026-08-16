import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/student_media.dart';
import 'package:mpsc_combine_ai/widgets/lesson_video_controls.dart';
import 'package:mpsc_combine_ai/widgets/storage_image.dart';

/// HTML `<video>` (and YouTube iframe) for Flutter Web.
class LessonVideoSurface extends StatefulWidget {
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
  State<LessonVideoSurface> createState() => _LessonVideoSurfaceState();
}

class _LessonVideoSurfaceState extends State<LessonVideoSurface> {
  late final String _viewType;
  html.VideoElement? _video;
  bool _playing = false;
  bool _started = false;
  bool _appliedStart = false;
  double _position = 0;
  double _duration = 0;
  bool _ready = false;
  double _speed = 1.0;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _speed = widget.playbackSpeed;
    _viewType = 'lesson-video-${identityHashCode(this)}';
    final src = widget.playbackUrl;
    final youtube = widget.isYoutube;
    final ytId = youtube ? youtubeVideoId(src) : null;

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      if (youtube && ytId != null && ytId.isNotEmpty) {
        final iframe = html.IFrameElement()
          ..src = 'https://www.youtube.com/embed/$ytId?rel=0&modestbranding=1'
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allowFullscreen = true;
        iframe.setAttribute(
          'allow',
          'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; fullscreen',
        );
        iframe.setAttribute('title', 'Lesson video');
        return iframe;
      }

      final video = html.VideoElement()
        ..src = src
        ..controls = false
        ..autoplay = false
        ..playbackRate = _speed
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'contain'
        ..style.backgroundColor = '#071530';
      video.setAttribute('playsinline', 'true');
      video.setAttribute('preload', 'metadata');
      video.onLoadedMetadata.listen((_) {
        _duration = video.duration.toDouble();
        _ready = true;
        _applyStart(video);
        if (mounted) setState(() {});
      });
      video.onTimeUpdate.listen((_) {
        _position = video.currentTime.toDouble();
        _playing = !video.paused;
        _maybeSave(force: false);
        if (mounted) setState(() {});
      });
      video.onPlay.listen((_) {
        _playing = true;
        _started = true;
        if (mounted) setState(() {});
      });
      video.onPause.listen((_) {
        _playing = false;
        _maybeSave(force: true);
        if (mounted) setState(() {});
      });
      _video = video;
      return video;
    });
  }

  void _applyStart(html.VideoElement video) {
    if (_appliedStart) return;
    final start = widget.startFraction;
    if (start > 0.02 && start < 0.95 && video.duration > 0) {
      video.currentTime = start * video.duration;
      _position = video.currentTime.toDouble();
    }
    video.playbackRate = _speed;
    _appliedStart = true;
  }

  void _maybeSave({required bool force}) {
    if (_duration <= 0) return;
    final fraction = (_position / _duration).clamp(0.0, 1.0);
    final now = DateTime.now();
    if (!force && now.difference(_lastSave) < const Duration(seconds: 5)) {
      return;
    }
    _lastSave = now;
    widget.onProgress?.call(fraction, _speed, completed: fraction >= 0.95);
  }

  @override
  void dispose() {
    _maybeSave(force: true);
    super.dispose();
  }

  void _togglePlay() {
    final v = _video;
    if (v == null) return;
    setState(() => _started = true);
    if (v.paused) {
      v.play();
    } else {
      v.pause();
    }
  }

  void _seek(double fraction) {
    final v = _video;
    if (v == null || _duration <= 0) return;
    v.currentTime = fraction.clamp(0.0, 1.0) * _duration;
    _maybeSave(force: true);
  }

  void _setSpeed(double speed) {
    _speed = speed;
    _video?.playbackRate = speed;
    _maybeSave(force: true);
    if (mounted) setState(() {});
  }

  void _fullscreen() {
    final v = _video;
    if (v == null) return;
    v.playbackRate = _speed;
    v.requestFullscreen();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isYoutube) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: AppColors.navyDark,
          child: HtmlElementView(viewType: _viewType),
        ),
      );
    }

    final max = _duration <= 0 ? 1.0 : _duration;
    final canResume = widget.startFraction > 0.02 && widget.startFraction < 0.95;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(
            color: AppColors.navyDark,
            child: Stack(
              fit: StackFit.expand,
              children: [
                HtmlElementView(viewType: _viewType),
                if (!_started)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _togglePlay,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (widget.thumbnailUrl.trim().isNotEmpty)
                            StorageImage(
                              storedUrl: widget.thumbnailUrl,
                              fit: BoxFit.cover,
                            )
                          else
                            const ColoredBox(color: AppColors.navyDark),
                          const ColoredBox(color: Color(0x66071530)),
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.play_circle_filled_rounded,
                                  color: Colors.white,
                                  size: 72,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  canResume && _duration > 0
                                      ? 'Resume  ${formatMediaClockSeconds(widget.startFraction * _duration)}'
                                      : 'Play lecture',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        LessonVideoControls(
          playing: _playing,
          positionLabel: formatMediaClockSeconds(_position),
          durationLabel: formatMediaClockSeconds(_duration),
          sliderValue: (_position / max).clamp(0.0, 1.0),
          playbackSpeed: _speed,
          onPlayPause: _togglePlay,
          onSeek: _ready ? _seek : (_) {},
          onSpeed: _setSpeed,
          onFullscreen: _fullscreen,
        ),
      ],
    );
  }
}
