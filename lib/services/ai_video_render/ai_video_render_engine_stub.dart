import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/lesson_render_job_builder.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/render_models.dart';

/// Web stub — FFmpeg MP4 encode is native-only.
///
/// Web plays the dynamic Gemini slide deck with synced Marathi voice
/// (educational player). No hardcoded / placeholder MP4 assets.
class AiVideoRenderEngine {
  Future<bool> get canEncode async => false;

  AiVideoRenderJob jobFromLesson(GeneratedLesson lesson) {
    assertLessonReadyForVideo(lesson);
    return buildRenderJobFromLesson(lesson);
  }

  Future<AiVideoRenderResult> render(
    AiVideoRenderJob job, {
    void Function(AiVideoRenderPhase phase, double progress)? onProgress,
    bool force = false,
    GeneratedLesson? sourceLesson,
  }) async {
    throw UnsupportedError(
      'MP4 encoding is not available on Flutter Web. '
      'The app plays the Gemini-generated educational lesson with synced voice.',
    );
  }
}

final AiVideoRenderEngine aiVideoRenderEngine = AiVideoRenderEngine();
