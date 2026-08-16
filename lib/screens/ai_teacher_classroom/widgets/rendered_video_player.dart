import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/rendered_video_controller.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_progress_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/pip_request.dart';
import 'package:mpsc_combine_ai/utils/student_media.dart';
import 'package:video_player/video_player.dart';

/// Fullscreen-capable MP4 player for generated AI Classroom videos.
class RenderedVideoPlayer extends StatefulWidget {
  const RenderedVideoPlayer({
    super.key,
    required this.source,
    this.assetKey,
    this.autoplay = true,
    this.progressId = '',
    this.onBack,
  });

  final String source;
  final String? assetKey;
  final bool autoplay;
  final String progressId;
  final VoidCallback? onBack;

  @override
  State<RenderedVideoPlayer> createState() => _RenderedVideoPlayerState();
}

class _RenderedVideoPlayerState extends State<RenderedVideoPlayer> {
  VideoPlayerController? _controller;
  String? _error;
  bool _ready = false;
  double _speed = 0.95;
  double _startFraction = 0;
  Timer? _saveTimer;

  static const _speeds = <double>[0.75, 0.95, 1.0, 1.25, 1.5];

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  @override
  void didUpdateWidget(covariant RenderedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.assetKey != widget.assetKey) {
      unawaited(_boot());
    }
  }

  Future<void> _boot() async {
    await _loadProgress();
    await _init();
  }

  Future<void> _loadProgress() async {
    final uid = authService.currentUser?.uid;
    final id = widget.progressId.trim();
    if (uid == null || id.isEmpty) return;
    try {
      final p = await lessonProgressRepository.getProgress(uid, id);
      _startFraction = (p?.lastPositionFraction ?? 0).clamp(0.0, 0.98);
    } catch (_) {}
  }

  Future<void> _init() async {
    await _controller?.dispose();
    _controller = null;
    _ready = false;
    _error = null;
    if (mounted) setState(() {});

    try {
      final c = createRenderedVideoController(
        source: widget.source,
        assetKey: widget.assetKey,
      );
      _controller = c;
      await c.initialize();
      await c.setLooping(false);
      await c.setPlaybackSpeed(_speed);
      if (_startFraction > 0.02) {
        final d = c.value.duration;
        await c.seekTo(
          Duration(milliseconds: (d.inMilliseconds * _startFraction).round()),
        );
      }
      if (widget.autoplay) await c.play();
      c.addListener(_onTick);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = studentFacingMediaError(e));
    }
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {});
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 4), _saveProgress);
  }

  Future<void> _saveProgress() async {
    final c = _controller;
    final uid = authService.currentUser?.uid;
    final id = widget.progressId.trim();
    if (c == null || !c.value.isInitialized || uid == null || id.isEmpty) {
      return;
    }
    final total = c.value.duration.inMilliseconds;
    if (total <= 0) return;
    final fraction = (c.value.position.inMilliseconds / total).clamp(0.0, 1.0);
    try {
      await lessonProgressRepository.savePosition(
        uid: uid,
        chapterId: id,
        fraction: fraction,
        completed: fraction >= 0.95,
      );
    } catch (_) {}
  }

  Future<void> _skip(int seconds) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final next = c.value.position + Duration(seconds: seconds);
    final end = c.value.duration;
    var target = next;
    if (target < Duration.zero) target = Duration.zero;
    if (target > end) target = end;
    await c.seekTo(target);
  }

  Future<void> _cycleSpeed() async {
    final i = _speeds.indexWhere((s) => (s - _speed).abs() < 0.01);
    _speed = _speeds[((i < 0 ? 0 : i) + 1) % _speeds.length];
    await _controller?.setPlaybackSpeed(_speed);
    if (mounted) setState(() {});
  }

  Future<void> _openFullscreen() async {
    final c = _controller;
    if (c == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenVideoScaffold(
          controller: c,
          onBack: () => Navigator.of(context).maybePop(),
          onSkip: _skip,
          onCycleSpeed: _cycleSpeed,
          speed: _speed,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(_saveProgress());
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    final c = _controller;
    if (!_ready || c == null || !c.value.isInitialized) {
      return const SizedBox(
        height: 220,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.orange),
        ),
      );
    }

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio:
                c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
        ),
        const SizedBox(height: 8),
        _TransportBar(
          controller: c,
          speed: _speed,
          onPlayPause: () {
            if (c.value.isPlaying) {
              c.pause();
            } else {
              c.play();
            }
            setState(() {});
          },
          onSkip: _skip,
          onCycleSpeed: _cycleSpeed,
          onFullscreen: _openFullscreen,
          onPip: () => unawaited(requestPictureInPicture()),
          onBack: widget.onBack,
        ),
      ],
    );
  }
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({
    required this.controller,
    required this.speed,
    required this.onPlayPause,
    required this.onSkip,
    required this.onCycleSpeed,
    required this.onFullscreen,
    required this.onPip,
    this.onBack,
  });

  final VideoPlayerController controller;
  final double speed;
  final VoidCallback onPlayPause;
  final Future<void> Function(int seconds) onSkip;
  final VoidCallback onCycleSpeed;
  final VoidCallback onFullscreen;
  final VoidCallback onPip;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final pos = controller.value.position;
    final dur = controller.value.duration;
    return Column(
      children: [
        VideoProgressIndicator(
          controller,
          allowScrubbing: true,
          colors: const VideoProgressColors(
            playedColor: AppColors.orange,
            bufferedColor: Color(0x33FF6B2B),
            backgroundColor: Color(0x220A1F44),
          ),
        ),
        Row(
          children: [
            if (onBack != null)
              IconButton(
                tooltip: 'Back',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
              ),
            IconButton(
              tooltip: controller.value.isPlaying ? 'Pause' : 'Play',
              onPressed: onPlayPause,
              icon: Icon(
                controller.value.isPlaying
                    ? Icons.pause_circle
                    : Icons.play_circle,
                color: AppColors.navy,
                size: 36,
              ),
            ),
            IconButton(
              tooltip: 'Back 10s',
              onPressed: () => onSkip(-10),
              icon: const Icon(Icons.replay_10_rounded, color: AppColors.navy),
            ),
            IconButton(
              tooltip: 'Forward 10s',
              onPressed: () => onSkip(10),
              icon: const Icon(Icons.forward_10_rounded, color: AppColors.navy),
            ),
            Text(
              '${formatMediaClock(pos)} / ${formatMediaClock(dur)}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onCycleSpeed,
              child: Text(
                '${speed}x',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Picture in picture',
              onPressed: onPip,
              icon: const Icon(Icons.picture_in_picture_alt_rounded,
                  color: AppColors.navy),
            ),
            IconButton(
              tooltip: 'Fullscreen',
              onPressed: onFullscreen,
              icon: const Icon(Icons.fullscreen_rounded, color: AppColors.navy),
            ),
          ],
        ),
      ],
    );
  }
}

class _FullscreenVideoScaffold extends StatelessWidget {
  const _FullscreenVideoScaffold({
    required this.controller,
    required this.onBack,
    required this.onSkip,
    required this.onCycleSpeed,
    required this.speed,
  });

  final VideoPlayerController controller;
  final VoidCallback onBack;
  final Future<void> Function(int seconds) onSkip;
  final VoidCallback onCycleSpeed;
  final double speed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onBack,
        ),
        title: const Text('AI Classroom'),
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio == 0
              ? 16 / 9
              : controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      ),
      bottomNavigationBar: ColoredBox(
        color: Colors.black,
        child: _TransportBar(
          controller: controller,
          speed: speed,
          onPlayPause: () {
            if (controller.value.isPlaying) {
              controller.pause();
            } else {
              controller.play();
            }
          },
          onSkip: onSkip,
          onCycleSpeed: onCycleSpeed,
          onFullscreen: onBack,
          onPip: () => unawaited(requestPictureInPicture()),
          onBack: onBack,
        ),
      ),
    );
  }
}
