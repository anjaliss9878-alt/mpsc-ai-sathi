import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/models/ai_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_backend_base.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_asset_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_repository.dart';
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
      return res.statusCode == 200;
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

  Stream<AiLesson?> watch(String jobId) => _repo.watch(jobId);

  /// Internal playback URL only — never show this string in the UI.
  Future<String> playbackUrl(String storedPath) =>
      _assets.playbackUrl(storedPath);
}

final ClassroomVideoClient classroomVideoClient = ClassroomVideoClient();
