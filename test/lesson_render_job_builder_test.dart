import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/lesson_render_job_builder.dart';

GeneratedLesson _sampleLesson({int slideCount = 16}) {
  final slides = List<GeneratedSlide>.generate(slideCount, (i) {
    final isSummary = i == slideCount - 1;
    final isTitle = i == 0;
    return GeneratedSlide(
      title: isTitle
          ? 'ओळख'
          : isSummary
              ? 'सारांश'
              : 'संकल्पना ${i + 1}',
      bullets: ['मुद्दा अ', 'मुद्दा ब'],
      narration: 'हे एक सविस्तर मराठी स्पष्टीकरण आहे. उदाहरणासह समजावून सांगतो.',
      bulletExpansions: const [
        'पहिला मुद्दा स्पष्ट करतो.',
        'दुसरा मुद्दा उदाहरणाने सांगतो.',
      ],
      keywords: const ['MPSC'],
      sceneType: isTitle
          ? LessonSceneType.title
          : isSummary
              ? LessonSceneType.summary
              : LessonSceneType.mainExplanation,
      visualType: i % 5 == 0
          ? SlideVisualType.flowchart
          : i % 5 == 1
              ? SlideVisualType.timeline
              : i % 5 == 2
                  ? SlideVisualType.table
                  : SlideVisualType.bullets,
      flowchart: i % 5 == 0
          ? const [
              FlowNode(id: '1', label: 'सुरुवात', nextIds: ['2']),
              FlowNode(id: '2', label: 'शेवट'),
            ]
          : const [],
      timeline: i % 5 == 1
          ? const [
              TimelineEvent(year: '1950', label: 'घटना लागू'),
            ]
          : const [],
      tableHeaders: i % 5 == 2 ? const ['अ', 'ब'] : const [],
      tableRows: i % 5 == 2
          ? const [
              ['१', '२'],
            ]
          : const [],
      sectionQuestion: i == 5
          ? const GeneratedMcq(
              question: 'चाचणी प्रश्न?',
              options: ['अ', 'ब', 'क', 'ड'],
              correctIndex: 1,
              explanation: 'ब योग्य आहे.',
            )
          : null,
      transition: 'fade',
    );
  });

  return GeneratedLesson(
    question: 'संसद',
    topicName: 'संसद',
    subjectName: 'राज्यव्यवस्था',
    script: slides.map((s) => s.narration).toList(),
    slides: slides,
    summary: 'संपूर्ण पुनरावृत्ती: संसदेची रचना लक्षात ठेवा.',
    mcqs: const [
      GeneratedMcq(
        question: 'संसदेत किती भाग?',
        options: ['१', '२', '३', '४'],
        correctIndex: 2,
        explanation: 'तीन भाग.',
      ),
      GeneratedMcq(
        question: 'लोकसभा?',
        options: ['अ', 'ब', 'क', 'ड'],
        correctIndex: 0,
        explanation: 'अ.',
      ),
      GeneratedMcq(
        question: 'राज्यसभा?',
        options: ['अ', 'ब', 'क', 'ड'],
        correctIndex: 0,
        explanation: 'अ.',
      ),
    ],
    notes: const ['टीप १', 'टीप २', 'टीप ३'],
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  test('buildRenderJobFromLesson produces landscape 1280x720 @ 30fps', () {
    final job = buildRenderJobFromLesson(_sampleLesson());
    expect(job.targetWidth, 1280);
    expect(job.targetHeight, 720);
    expect(job.targetWidth, kEduVideoWidth);
    expect(job.targetHeight, kEduVideoHeight);
    expect(job.fps, kEduVideoFps);
    expect(job.scenes.length, greaterThanOrEqualTo(16));
    expect(job.totalDuration.inSeconds, greaterThan(20));
    for (final scene in job.scenes) {
      expect(scene.beats, isNotEmpty);
      for (final beat in scene.beats) {
        expect(beat.speakText.trim(), isNotEmpty);
        expect(beat.subtitleCues, isNotEmpty);
      }
    }
  });

  test('assertLessonReadyForVideo rejects empty / tiny decks', () {
    expect(
      () => assertLessonReadyForVideo(_sampleLesson(slideCount: 3)),
      throwsStateError,
    );
    expect(() => assertLessonReadyForVideo(_sampleLesson()), returnsNormally);
  });

  test('exactly one MCQ scene is attached after a major section', () {
    final job = buildRenderJobFromLesson(_sampleLesson());
    final mcqScenes =
        job.scenes.where((s) => s.beats.any((b) => b.isMcq)).toList();
    expect(mcqScenes, isNotEmpty);
    // Each section checkpoint is a single MCQ (question + explain beats).
    for (final scene in mcqScenes) {
      final qBeats = scene.beats.where((b) => b.isMcq).length;
      expect(qBeats, 1);
      expect(scene.beats.where((b) => b.isMcqExplain).length, 1);
    }
  });
}
