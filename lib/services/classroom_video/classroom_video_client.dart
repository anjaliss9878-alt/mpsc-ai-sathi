import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/models/ai_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_backend_base.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_asset_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_repository.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/full_lesson_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';

/// Optional local classroom video backend over localhost (topic → MP4).
class ClassroomVideoClient {
  ClassroomVideoClient({
    AiLessonRepository? repository,
    AiLessonAssetService? assets,
    http.Client? httpClient,
    String? workerBase,
  })  : _repo = repository ?? aiLessonRepository,
        _assets = assets ?? aiLessonAssetService,
        _http = httpClient ?? http.Client(),
        _workerBase = (workerBase ?? aiBackendBase()).replaceAll(RegExp(r'/$'), '');

  final AiLessonRepository _repo;
  final AiLessonAssetService _assets;
  final http.Client _http;
  final String _workerBase;

  Future<bool> isEngineRunning() async {
    try {
      final res = await _http
          .get(Uri.parse('$_workerBase/health'))
          .timeout(const Duration(seconds: 2));
      return classroomEngineHealthOk(res.statusCode, res.body);
    } catch (_) {
      return false;
    }
  }

  Future<String> enqueueJob({
    required String topic,
    String chapterId = '',
    String subjectId = '',
    String subjectTitle = '',
    bool forceRegenerate = true,
  }) async {
    final uid = authService.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Please sign in first');
    }
    return _repo.enqueue(
      uid: uid,
      topic: topic.trim().isEmpty ? 'MPSC विषय' : topic.trim(),
      chapterId: chapterId,
      subjectId: subjectId,
      subjectTitle: subjectTitle,
      forceRegenerate: forceRegenerate,
    );
  }

  /// Mux existing Gemini slides + uploaded audio into a final MP4.
  Future<void> startRender({
    required String jobId,
    required String topic,
    required String narration,
    required List<Map<String, dynamic>> slides,
    String audioPath = '',
  }) async {
    final token = await authService.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Please sign in first');
    }
    final res = await _http
        .post(
          Uri.parse('$_workerBase/render'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jobId': jobId,
            'idToken': token,
            'topic': topic,
            'narration': narration,
            'audioPath': audioPath,
            'slides': slides,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 202 && res.statusCode != 200) {
      throw StateError(
        'Video rendering failed (HTTP ${res.statusCode})',
      );
    }
    if (!classroomRenderResponseAccepted(res.statusCode, res.body)) {
      throw StateError('Video rendering failed');
    }
  }

  Future<AiLesson> waitUntilPlayable(
    String jobId, {
    Duration timeout = const Duration(minutes: 12),
    void Function(AiLesson job)? onUpdate,
  }) async {
    final end = DateTime.now().add(timeout);
    await for (final job in watch(jobId).timeout(timeout)) {
      if (job == null) continue;
      onUpdate?.call(job);
      if (job.isFailed) {
        throw StateError(
          job.friendlyMessage.trim().isNotEmpty
              ? job.friendlyMessage
              : 'Video rendering failed',
        );
      }
      if (job.hasAudio && job.hasVideo && (job.isReady || job.finalVideoUrl.trim().isNotEmpty)) {
        return job;
      }
      if (DateTime.now().isAfter(end)) break;
    }
    throw TimeoutException('Video rendering timed out');
  }

  Stream<AiLesson?> watch(String jobId) => _repo.watch(jobId);

  /// Internal playback URL only — never show this string in the UI.
  Future<String> playbackUrl(String storedPath) =>
      _assets.playbackUrl(storedPath);

  List<Map<String, dynamic>> slidesPayload(
    GeneratedLesson lesson, {
    LessonAudioBundle? audio,
  }) =>
      classroomSlidesPayload(lesson, audio: audio);
}

final ClassroomVideoClient classroomVideoClient = ClassroomVideoClient();

bool classroomEngineHealthOk(int statusCode, String body) {
  if (statusCode != 200) return false;
  try {
    final map = jsonDecode(body);
    if (map is! Map) return false;
    if (map['canRender'] == false || map['ffmpeg'] == false) return false;
    return map['ok'] == true || map['canRender'] == true;
  } catch (_) {
    return false;
  }
}

bool classroomRenderResponseAccepted(int statusCode, String body) {
  if (statusCode != 202 && statusCode != 200) return false;
  try {
    final map = jsonDecode(body);
    return map is Map && map['accepted'] == true;
  } catch (_) {
    return false;
  }
}

List<Map<String, dynamic>> classroomSlidesPayload(
  GeneratedLesson lesson, {
  LessonAudioBundle? audio,
}) {
  final seconds = audio == null || audio.spans.isEmpty
      ? null
      : slideSecondsFromSpans(
          spans: audio.spans,
          slideCount: lesson.slides.length,
        );
  return [
    for (var i = 0; i < lesson.slides.length; i++)
      {
        'heading': lesson.slides[i].title,
        'points': lesson.slides[i].bullets.take(5).toList(),
        'spoken': lesson.slides[i].narration.trim().isNotEmpty
            ? lesson.slides[i].narration
            : lesson.slides[i].bullets.join(' '),
        if (seconds != null && i < seconds.length && seconds[i] > 0)
          'durationSeconds': seconds[i],
      },
  ];
}
