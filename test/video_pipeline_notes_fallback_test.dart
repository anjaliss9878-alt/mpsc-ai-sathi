import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/chapter_lesson_loader.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_generation_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/verified_content_retrieval.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_generation_pipeline.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_lesson_cache_service.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/ai_video_render_engine.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/lesson_render_job_builder.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/render_models.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';

class _NoEncodeEngine extends AiVideoRenderEngine {
  @override
  Future<bool> get canEncode async => false;
}

void main() {
  test(
    'pipeline falls back to AI lesson when database has no verified notes',
    () async {
      final firestore = FakeFirebaseFirestore();
      final notes = NotesRepository(firestore: firestore);
      final retrieval = VerifiedContentRetrieval(
        notes: notes,
        loader: ChapterLessonLoader(notes: notes),
      );
      final pipeline = VideoGenerationPipeline(
        generation: MockLessonGenerationService(),
        contentRetrieval: retrieval,
        videoCache: VideoLessonCacheService(),
        renderEngine: _NoEncodeEngine(),
      );

      final stages = <VideoGenerationStage>[];
      final result = await pipeline.generate(
        topic: 'कोणताही नवीन विषय XYZ',
        forceRegenerate: true,
        onStage: stages.add,
      );

      expect(result.lesson.slides.length, greaterThanOrEqualTo(kMinEduSlides));
      expect(result.usedVerifiedNotes, isFalse);
      expect(result.lesson.sourceKind, LessonSourceKind.aiGenerated);
      expect(result.educationalPlayback || result.hasRenderedVideo, isTrue);
      expect(
        stages,
        isNot(contains(VideoGenerationStage.failed)),
      );
      // Student must never see the old notes-missing blocker copy.
      final joined = result.lesson.slides.map((s) => s.narration).join(' ');
      expect(joined.toLowerCase(), isNot(contains('no published verified')));
      expect(joined, isNot(contains('प्रकाशित नोट्स सापडल्या नाहीत')));
    },
  );

  test('topicOnly generates a classroom lesson without notes or PDF', () async {
    final firestore = FakeFirebaseFirestore();
    final notes = NotesRepository(firestore: firestore);
    final pipeline = VideoGenerationPipeline(
      generation: MockLessonGenerationService(),
      contentRetrieval: VerifiedContentRetrieval(
        notes: notes,
        loader: ChapterLessonLoader(notes: notes),
      ),
      videoCache: VideoLessonCacheService(),
      renderEngine: _NoEncodeEngine(),
    );

    final result = await pipeline.generate(
      topic: 'मूलभूत अधिकार',
      topicOnly: true,
      forceRegenerate: true,
    );

    expect(result.usedVerifiedNotes, isFalse);
    expect(result.lesson.sourceKind, LessonSourceKind.aiGenerated);
    expect(
      result.lesson.slides.length,
      inInclusiveRange(kMinEduSlides, kMaxEduSlides),
    );
  });
}
