import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/full_lesson_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lecture_lesson_sanitizer.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';

GeneratedLesson _thinHistoryLesson() {
  return GeneratedLesson(
    question: 'Revolt of 1857',
    topicName: 'Revolt of 1857',
    subjectName: MpscTeachingSubject.history.displayName,
    script: const ['एकच परिच्छेद'],
    slides: const [
      GeneratedSlide(
        title: 'Revolt of 1857',
        bullets: [
          'कारणे',
          'घटनाक्रम',
          'परिणाम',
          'व्यक्तिमत्त्वे',
        ],
        sceneType: LessonSceneType.introduction,
        narration: '१८५७ चा उठाव हा आधुनिक भारतातील महत्त्वाचा टप्पा आहे.',
      ),
    ],
    summary: 'उठावाची कारणे, घटना आणि परिणाम लक्षात ठेवा.',
    mcqs: const [],
    notes: const [],
    createdAt: DateTime(2026, 1, 1),
    premium: const LessonPremiumExtras(
      introduction: 'आज आपण १८५७ चा उठाव समजून घेणार आहोत.',
      mainConcepts: ['राजकीय कारणे', 'लष्करी कारणे'],
      examples: ['मंगल पांडे यांचा प्रसंग'],
      pyqInsight: ['परीक्षा घटनाक्रम विचारते'],
      quickRevision: 'कारणे, घटना, परिणाम — ही त्रिसूत्री लक्षात ठेवा.',
    ),
  );
}

GeneratedLesson _multiScenePolity() {
  return GeneratedLesson(
    question: 'भारतीय राज्यघटना',
    topicName: 'भारतीय राज्यघटना',
    subjectName: MpscTeachingSubject.polity.displayName,
    script: const ['१', '२', '३', '४'],
    slides: const [
      GeneratedSlide(
        title: 'परिचय',
        bullets: ['राज्यघटना'],
        sceneType: LessonSceneType.introduction,
        visualType: SlideVisualType.flowchart,
        narration: 'परिचय.',
      ),
      GeneratedSlide(
        title: 'कलम',
        bullets: ['मूलभूत अधिकार'],
        sceneType: LessonSceneType.mainExplanation,
        visualType: SlideVisualType.table,
        narration: 'संकल्पना एक.',
      ),
      GeneratedSlide(
        title: 'संस्था',
        bullets: ['संसद'],
        sceneType: LessonSceneType.mainExplanation,
        visualType: SlideVisualType.flowchart,
        narration: 'संकल्पना दोन.',
      ),
      GeneratedSlide(
        title: 'उदाहरण',
        bullets: ['आणीबाणी'],
        sceneType: LessonSceneType.examples,
        narration: 'उदाहरण.',
      ),
      GeneratedSlide(
        title: 'PYQ',
        bullets: ['पूर्व परीक्षा'],
        sceneType: LessonSceneType.importantPoints,
        narration: 'परीक्षा मुद्दा.',
      ),
      GeneratedSlide(
        title: 'पुनरावृत्ती',
        bullets: ['थोडक्यात'],
        sceneType: LessonSceneType.summary,
        narration: 'पुनरावृत्ती.',
      ),
    ],
    summary: 'राज्यघटना',
    mcqs: const [],
    notes: const [],
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  test('thin lesson produces multiple ordered video scenes', () {
    final scenes = classroomVideoScenesFor(
      _thinHistoryLesson(),
      subject: MpscTeachingSubject.history,
    );
    expect(scenes.length, greaterThanOrEqualTo(4));
    expect(hasUsableClassroomVideoScenes(scenes), isTrue);
    expect(scenes.first.sceneType, LessonSceneType.introduction);
    expect(
      scenes.map((s) => s.sceneType).toList(),
      containsAllInOrder([
        LessonSceneType.introduction,
        LessonSceneType.mainExplanation,
      ]),
    );
    expect(scenes.last.sceneType, LessonSceneType.summary);
  });

  test('scene order is preserved when the lesson already has scenes', () {
    final original = _multiScenePolity();
    final scenes = classroomVideoScenesFor(
      original,
      subject: MpscTeachingSubject.polity,
    );
    expect(scenes.map((s) => s.title).toList(), [
      for (final s in original.slides) s.title,
    ]);
    expect(scenes.map((s) => s.sceneType).toList(), [
      for (final s in original.slides) s.sceneType,
    ]);
  });

  test('slide changes when scene changes along the TTS timeline', () {
    final lesson = ensureClassroomVideoScenes(_multiScenePolity());
    final cues = FullLessonNarrationService().lessonSpeakCues(lesson);
    expect(cues.length, lesson.slides.length);
    expect(cues.map((c) => c.slideIndex).toList(), [0, 1, 2, 3, 4, 5]);
    final spans = beatSpansFor(
      texts: [for (final c in cues) c.text],
      total: const Duration(seconds: 60),
      slideIndices: [for (final c in cues) c.slideIndex],
    );
    expect(spans.map((s) => s.slideIndex).toSet().length, greaterThan(1));
    final slides = <int>[
      for (final p in [0.0, 0.2, 0.4, 0.6, 0.8, 0.99])
        slideIndexAtAudioProgress(
          spans: spans,
          progress: p,
          total: const Duration(seconds: 60),
          slideCount: lesson.slides.length,
        ),
    ];
    expect(slides.first, 0);
    expect(slides.last, lesson.slides.length - 1);
    expect(slides.toSet().length, greaterThan(1));
    for (var i = 1; i < slides.length; i++) {
      expect(slides[i] >= slides[i - 1], isTrue);
    }
  });

  test('no static single-slide fallback when multiple scenes exist', () {
    final lesson = ensureClassroomVideoScenes(_multiScenePolity());
    final cues = FullLessonNarrationService().lessonSpeakCues(lesson);
    expect(cues.map((c) => c.slideIndex).toSet().length, cues.length);
  });

  test('subject-specific slide type is preserved', () {
    final history = classroomVideoScenesFor(
      _thinHistoryLesson(),
      subject: MpscTeachingSubject.history,
    );
    expect(
      history.any((s) => s.visualType == SlideVisualType.timeline),
      isTrue,
    );
    final polity = classroomVideoScenesFor(
      _multiScenePolity(),
      subject: MpscTeachingSubject.polity,
    );
    expect(polity[0].visualType, SlideVisualType.flowchart);
    expect(polity[1].visualType, SlideVisualType.table);
  });

  test('TTS narration path still uses one Gemini /ai/tts script join', () {
    final lesson = ensureClassroomVideoScenes(_multiScenePolity());
    final cues = FullLessonNarrationService().lessonSpeakCues(lesson);
    final script = FullLessonNarrationService().buildLectureScript(
      scriptLines: [for (final c in cues) c.text],
    );
    expect(script.contains('elevenlabs'), isFalse);
    expect(script.split(' ').length, greaterThan(3));
    expect(cues, isNotEmpty);
  });

  test('existing beatSpansFor architecture is reused for scene holds', () {
    const spans = [
      BeatAudioSpan(
        beatIndex: 0,
        slideIndex: 0,
        text: 'पहिली',
        start: Duration.zero,
        end: Duration(seconds: 10),
      ),
      BeatAudioSpan(
        beatIndex: 1,
        slideIndex: 1,
        text: 'दुसरी',
        start: Duration(seconds: 10),
        end: Duration(seconds: 20),
      ),
      BeatAudioSpan(
        beatIndex: 2,
        slideIndex: 2,
        text: 'तिसरी',
        start: Duration(seconds: 20),
        end: Duration(seconds: 30),
      ),
    ];
    expect(spanIndexAtPosition(spans: spans, position: Duration.zero), 0);
    expect(
      spanIndexAtPosition(spans: spans, position: const Duration(seconds: 10)),
      1,
    );
    expect(
      spanIndexAtPosition(spans: spans, position: const Duration(seconds: 29)),
      2,
    );
    expect(
      slideIndexAtAudioProgress(
        spans: spans,
        progress: 1,
        total: const Duration(seconds: 30),
        slideCount: 3,
      ),
      2,
    );
  });

  test('five equal scenes advance 1/5 through 5/5', () {
    const spans = [
      BeatAudioSpan(
        beatIndex: 0,
        slideIndex: 0,
        text: '१',
        start: Duration.zero,
        end: Duration(seconds: 10),
      ),
      BeatAudioSpan(
        beatIndex: 1,
        slideIndex: 1,
        text: '२',
        start: Duration(seconds: 10),
        end: Duration(seconds: 20),
      ),
      BeatAudioSpan(
        beatIndex: 2,
        slideIndex: 2,
        text: '३',
        start: Duration(seconds: 20),
        end: Duration(seconds: 30),
      ),
      BeatAudioSpan(
        beatIndex: 3,
        slideIndex: 3,
        text: '४',
        start: Duration(seconds: 30),
        end: Duration(seconds: 40),
      ),
      BeatAudioSpan(
        beatIndex: 4,
        slideIndex: 4,
        text: '५',
        start: Duration(seconds: 40),
        end: Duration(seconds: 50),
      ),
    ];
    const total = Duration(seconds: 50);
    final slides = <int>[
      for (final p in [0.0, 0.21, 0.41, 0.61, 0.81])
        slideIndexAtAudioProgress(
          spans: spans,
          progress: p,
          total: total,
          slideCount: 5,
        ),
    ];
    expect(slides, [0, 1, 2, 3, 4]);
    expect(spanIndexAtPosition(spans: spans, position: const Duration(seconds: 10)), 1);
    expect(spanIndexAtPosition(spans: spans, position: const Duration(seconds: 20)), 2);
    expect(spanIndexAtPosition(spans: spans, position: const Duration(seconds: 30)), 3);
    expect(spanIndexAtPosition(spans: spans, position: const Duration(seconds: 40)), 4);
  });
}
