import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/storage_service.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/student_media.dart';
import 'package:mpsc_combine_ai/widgets/lesson_video_surface.dart';

/// Student lecture player. Resolves Storage via [getDownloadURL], resumes
/// saved progress, and auto-saves watch position. Never shows the URL.
class LessonVideoPlayer extends StatefulWidget {
  const LessonVideoPlayer({
    super.key,
    required this.source,
    required this.progressId,
    this.title = 'Lecture',
    this.subjectTitle = '',
    this.thumbnailUrl = '',
  });

  final String source;
  final String progressId;
  final String title;
  final String subjectTitle;
  final String thumbnailUrl;

  @override
  State<LessonVideoPlayer> createState() => _LessonVideoPlayerState();
}

class _LessonVideoPlayerState extends State<LessonVideoPlayer> {
  String? _playbackUrl;
  bool _youtube = false;
  bool _loading = true;
  String? _error;
  double _startFraction = 0;
  double _speed = 1.0;
  bool _progressReady = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void didUpdateWidget(covariant LessonVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.progressId != widget.progressId) {
      _boot();
    }
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
      _progressReady = false;
    });
    await Future.wait([_resolve(), _loadProgress()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _resolve() async {
    final stored = widget.source.trim();
    if (stored.isEmpty) {
      _playbackUrl = null;
      return;
    }
    try {
      final youtube = isYoutubeUrl(stored);
      _youtube = youtube;
      _playbackUrl =
          youtube ? stored : await storageService.resolveDownloadUrl(stored);
    } catch (e) {
      _error = studentFacingMediaError(e);
      _playbackUrl = null;
    }
  }

  Future<void> _loadProgress() async {
    final uid = authService.currentUser?.uid;
    if (uid == null || widget.progressId.isEmpty) {
      _progressReady = true;
      return;
    }
    try {
      final snap = await studentProgressRepository
          .watchOneVideoProgress(uid, widget.progressId)
          .first
          .timeout(const Duration(seconds: 8), onTimeout: () => null);
      if (snap != null) {
        _startFraction = snap.completed ? 0 : snap.progress.clamp(0.0, 1.0);
        _speed = snap.playbackSpeed <= 0 ? 1.0 : snap.playbackSpeed;
      }
    } catch (_) {}
    _progressReady = true;
  }

  Future<void> _saveProgress(
    double fraction,
    double speed, {
    required bool completed,
  }) async {
    final uid = authService.currentUser?.uid;
    if (uid == null || widget.progressId.isEmpty) return;
    try {
      await studentProgressRepository.upsertVideoProgress(
        uid: uid,
        videoId: widget.progressId,
        title: widget.title,
        subject: widget.subjectTitle,
        progress: fraction,
        completed: completed,
        playbackSpeed: speed,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (widget.source.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.navy,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: const Row(
              children: [
                Icon(Icons.play_circle_fill_rounded, color: AppColors.orange),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Video lecture',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_loading || !_progressReady)
            const AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: AppColors.navyDark,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.orange),
                ),
              ),
            )
          else if (_error != null || _playbackUrl == null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: AppColors.navyDark,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _error ?? 'Could not load this file. Please try again.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            )
          else
            LessonVideoSurface(
              playbackUrl: _playbackUrl!,
              isYoutube: _youtube,
              startFraction: _startFraction,
              playbackSpeed: _speed,
              thumbnailUrl: widget.thumbnailUrl,
              onProgress: _saveProgress,
            ),
        ],
      ),
    );
  }
}
