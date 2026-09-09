import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/models/ai_lesson.dart';
import 'package:flutter/foundation.dart';
import 'package:mpsc_combine_ai/services/ai_backend_base.dart';
import 'package:mpsc_combine_ai/services/backend_request_headers.dart';
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
    final uri = Uri.parse('$_workerBase/health');
    try {
      final res = await _http.get(uri).timeout(const Duration(seconds: 2));
      final ok = classroomEngineHealthOk(res.statusCode, res.body);
      debugPrint(
        '[ai-video] health endpoint=$uri status=${res.statusCode} '
        'canRender=$ok token=n/a',
      );
      return ok;
    } catch (e) {
      debugPrint('[ai-video] health endpoint=$uri error=${e.runtimeType}');
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
    final uri = Uri.parse(aiVideoRenderEndpoint(_workerBase));
    final headers = await backendJsonHeaders();
    debugPrint(
      '[ai-video] render endpoint=$uri method=POST hasToken=true',
    );
    final res = await _http
        .post(
          uri,
          headers: headers,
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
    debugPrint(
      '[ai-video] render status=${res.statusCode} '
      'bodyChars=${res.body.length}',
    );
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
      // Require status=ready. A leftover finalVideoUrl from a previous job
      // plus newly uploaded audio must not switch the lecture to a silent MP4.
      if (job.isPlayable) {
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

/// Play the muxed MP4 on native. Flutter web keeps the slide lecture engine
/// so scene changes stay visible with Gemini TTS.
String? lectureMuxedUrlForStudent({
  required bool isWeb,
  String? muxedUrl,
}) {
  if (isWeb) return null;
  final u = (muxedUrl ?? '').trim();
  return u.isEmpty ? null : u;
}

/// Mux whenever FFmpeg worker is up, the student is signed in, and TTS audio exists.
bool shouldPrepareMuxedLecture({
  required bool engineCanRender,
  required bool signedIn,
  required bool hasAudio,
}) =>
    engineCanRender && signedIn && hasAudio;

final ClassroomVideoClient classroomVideoClient = ClassroomVideoClient();

bool classroomEngineHealthOk(int statusCode, String body) {
  if (statusCode != 200) return false;
  try {
    final map = jsonDecode(body);
    if (map is! Map) return false;
    if (map['canRender'] == false || map['ffmpeg'] == false) return false;
    return map['canRender'] == true || map['ffmpeg'] == true;
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
