import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/student_media.dart';
import 'package:mpsc_combine_ai/widgets/lesson_video_controls.dart';
import 'package:mpsc_combine_ai/widgets/storage_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

/// Native [video_player] for Android / iOS / desktop.
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
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _started = false;
  String? _error;
  double _speed = 1.0;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _speed = widget.playbackSpeed;
    if (!widget.isYoutube) _init();
  }

  @override
  void didUpdateWidget(covariant LessonVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackUrl != widget.playbackUrl ||
        oldWidget.isYoutube != widget.isYoutube) {
      _controller?.removeListener(_tick);
      _controller?.dispose();
      _controller = null;
      _ready = false;
      _started = false;
      _error = null;
      if (!widget.isYoutube) _init();
    }
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.playbackUrl));
      _controller = c;
      c.addListener(_tick);
      await c.initialize();
      await c.setLooping(false);
      await c.setPlaybackSpeed(_speed);
      final start = widget.startFraction;
      if (start > 0.02 && start < 0.95 && c.value.duration.inMilliseconds > 0) {
        await c.seekTo(
          Duration(
            milliseconds: (c.value.duration.inMilliseconds * start).round(),
          ),
        );
      }
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = studentFacingMediaError(e));
    }
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    _maybeSave(force: false);
  }

  void _maybeSave({required bool force}) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final dur = c.value.duration.inMilliseconds;
    if (dur <= 0) return;
    final fraction = c.value.position.inMilliseconds / dur;
    final now = DateTime.now();
    if (!force && now.difference(_lastSave) < const Duration(seconds: 5)) {
      return;
    }
    _lastSave = now;
    widget.onProgress?.call(
      fraction.clamp(0.0, 1.0),
      _speed,
      completed: fraction >= 0.95,
    );
  }

  @override
  void dispose() {
    _maybeSave(force: true);
    _controller?.removeListener(_tick);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openYoutube() async {
    final uri = Uri.tryParse(widget.playbackUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _play() async {
    final c = _controller;
    if (c == null) return;
    setState(() => _started = true);
    await c.play();
  }

  Future<void> _setSpeed(double speed) async {
    _speed = speed;
    await _controller?.setPlaybackSpeed(speed);
    _maybeSave(force: true);
    if (mounted) setState(() {});
  }

  Future<void> _fullscreen() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() => _started = true);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenVideoPage(
          controller: c,
          speed: _speed,
          onSpeed: _setSpeed,
        ),
      ),
    );
    _maybeSave(force: true);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isYoutube) {
      return _Poster(
        thumbnailUrl: widget.thumbnailUrl,
        label: 'Play video',
        onPlay: _openYoutube,
      );
    }
    if (_error != null) {
      return _VideoError(message: _error!);
    }
    final c = _controller;
    if (!_ready || c == null || !c.value.isInitialized) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: AppColors.navyDark,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.orange),
          ),
        ),
      );
    }

    final pos = c.value.position;
    final dur = c.value.duration;
    final maxMs = dur.inMilliseconds <= 0 ? 1.0 : dur.inMilliseconds.toDouble();
    final value = pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
    final canResume = widget.startFraction > 0.02 && widget.startFraction < 0.95;

    return Column(
      children: [
        AspectRatio(
          aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
          child: ColoredBox(
            color: AppColors.navyDark,
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoPlayer(c),
                if (!_started)
                  _Poster(
                    thumbnailUrl: widget.thumbnailUrl,
                    label: canResume
                        ? 'Resume  ${lessonClockFromFraction(fraction: widget.startFraction, duration: dur)}'
                        : 'Play lecture',
                    onPlay: _play,
                  ),
              ],
            ),
          ),
        ),
        LessonVideoControls(
          playing: c.value.isPlaying,
          positionLabel: formatMediaClock(pos),
          durationLabel: formatMediaClock(dur),
          sliderValue: value / maxMs,
          playbackSpeed: _speed,
          onPlayPause: () {
            if (c.value.isPlaying) {
              c.pause();
              _maybeSave(force: true);
            } else {
              _play();
            }
          },
          onSeek: (fraction) {
            c.seekTo(Duration(milliseconds: (fraction * maxMs).round()));
            _maybeSave(force: true);
          },
          onSpeed: _setSpeed,
          onFullscreen: _fullscreen,
        ),
      ],
    );
  }
}

class _FullscreenVideoPage extends StatefulWidget {
  const _FullscreenVideoPage({
    required this.controller,
    required this.speed,
    required this.onSpeed,
  });

  final VideoPlayerController controller;
  final double speed;
  final ValueChanged<double> onSpeed;

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final pos = c.value.position;
    final dur = c.value.duration;
    final maxMs = dur.inMilliseconds <= 0 ? 1.0 : dur.inMilliseconds.toDouble();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Lecture'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            ),
          ),
          LessonVideoControls(
            playing: c.value.isPlaying,
            positionLabel: formatMediaClock(pos),
            durationLabel: formatMediaClock(dur),
            sliderValue: (pos.inMilliseconds / maxMs).clamp(0.0, 1.0),
            playbackSpeed: widget.speed,
            onPlayPause: () {
              if (c.value.isPlaying) {
                c.pause();
              } else {
                c.play();
              }
            },
            onSeek: (fraction) {
              c.seekTo(Duration(milliseconds: (fraction * maxMs).round()));
            },
            onSpeed: widget.onSpeed,
            onFullscreen: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({
    required this.thumbnailUrl,
    required this.label,
    required this.onPlay,
  });

  final String thumbnailUrl;
  final String label;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPlay,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbnailUrl.trim().isNotEmpty)
              StorageImage(storedUrl: thumbnailUrl, fit: BoxFit.cover)
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
                    label,
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
    );
  }
}

class _VideoError extends StatelessWidget {
  const _VideoError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: AppColors.navyDark,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}
