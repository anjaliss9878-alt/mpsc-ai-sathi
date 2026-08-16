import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_cache_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_lesson_cache_service.dart';

void main() {
  test('cache keys are stable and topic-normalized', () {
    final cache = VideoLessonCacheService(lessonCache: LessonCacheService.instance);
    final a = cache.keyForTopic('संसद');
    final b = cache.keyForTopic('  संसद  ');
    final c = cache.keyForTopic('राज्यपाल');
    expect(a, b);
    expect(a, isNot(equals(c)));
  });

  test('writeLesson then read returns Gemini lesson slides', () async {
    final lessons = LessonCacheService.instance;
    final cache = VideoLessonCacheService(lessonCache: lessons);
    const topic = 'dynamic_test_topic_gdp';
    final lesson = GeneratedLesson(
      question: topic,
      topicName: 'GDP',
      subjectName: 'अर्थशास्त्र',
      script: List<String>.filled(10, 'स्पष्टीकरण'),
      slides: List<GeneratedSlide>.generate(
        10,
        (i) => GeneratedSlide(
          title: 'स्लाइड ${i + 1}',
          bullets: const ['अ', 'ब'],
          narration: 'विस्तृत मराठी स्पष्टीकरण.',
        ),
      ),
      summary: 'सारांश',
      mcqs: const [],
      notes: const ['टीप'],
      createdAt: DateTime(2026, 1, 1),
    );

    await cache.writeLesson(topic, lesson);
    final hit = await cache.read(topic);
    expect(hit, isNotNull);
    expect(hit!.lesson.topicName, 'GDP');
    expect(hit.lesson.slides.length, 10);
    expect(hit.hasRenderedVideo, isFalse);
  });
}
