import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_generation_pipeline.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_lesson_job_status.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_storage_cache_service.dart';

void main() {
  test('UI stages map to production API status strings', () {
    expect(VideoGenerationStage.understandingTopic.apiStatus, 'queued');
    expect(VideoGenerationStage.creatingLesson.apiStatus, 'generating_script');
    expect(VideoGenerationStage.creatingVoice.apiStatus, 'generating_audio');
    expect(VideoGenerationStage.preparingSlides.apiStatus, 'generating_slides');
    expect(VideoGenerationStage.renderingVideo.apiStatus, 'rendering_video');
    expect(VideoGenerationStage.ready.apiStatus, 'completed');
    expect(VideoGenerationStage.failed.apiStatus, 'failed');
  });

  test('VideoLessonJobStatus.apiName is stable wire format', () {
    expect(VideoLessonJobStatus.generatingScript.apiName, 'generating_script');
    expect(VideoLessonJobStatus.completed.apiName, 'completed');
  });

  test('storage cache keys are topic-normalized and stable for any topic', () {
    final cache = VideoStorageCacheService();
    final a = cache.keyForTopic('मूलभूत हक्क');
    final b = cache.keyForTopic('  मूलभूत हक्क  ');
    final c = cache.keyForTopic('राज्यपाल');
    expect(a, b);
    expect(a, isNot(equals(c)));
    expect(a.length, 32);
  });
}
