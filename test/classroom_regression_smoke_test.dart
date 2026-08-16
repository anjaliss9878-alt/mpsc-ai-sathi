import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/faculty_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_cache_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/teaching_sequence.dart';
import 'package:mpsc_combine_ai/services/google_cloud_tts_service.dart';

void main() {
  test('welcome lesson and legacy lesson remain compatible', () {
    expect(welcomeLesson.slides.length, 8);
    expect(welcomeLesson.mcqs.length, 5);
    expect(welcomeLesson.premium.hasContent, isTrue);
    expect(
      narrationSegmentsFor(welcomeLesson).length,
      welcomeLesson.slides.length,
    );
    final beats = teachingSequenceFor(welcomeLesson);
    expect(beats.length, greaterThan(welcomeLesson.slides.length));
    expect(beats.first.kind, TeachingBeatKind.titleRead);
    expect(
      beats.any((b) => b.kind == TeachingBeatKind.concept),
      isTrue,
    );
    expect(
      beats.any((b) => b.kind == TeachingBeatKind.memoryTrick),
      isTrue,
    );
    expect(
      beats.any((b) => b.kind == TeachingBeatKind.pyq),
      isTrue,
    );
    expect(
      beats.any((b) => b.kind == TeachingBeatKind.mcq),
      isTrue,
    );
    expect(
      beats.any((b) => b.kind == TeachingBeatKind.revision),
      isTrue,
    );
    expect(
      beats.any((b) => b.kind == TeachingBeatKind.summary),
      isTrue,
    );
    expect(
      beats.any((b) => b.kind == TeachingBeatKind.premiumClose),
      isTrue,
    );
    // Paragraph teaching: concept beats should be longer than bare bullets.
    final teach = beats.firstWhere((b) => b.kind == TeachingBeatKind.concept);
    expect(teach.speakText.length, greaterThan(24));
    expect(teach.pauseAfter, isFalse);
    expect(
      beats.any((b) => b.spotlight == PremiumSpotlight.pyq),
      isTrue,
    );

    final legacy = GeneratedLesson.fromMap({
      'question': 'q',
      'topicName': 't',
      'subjectName': 's',
      'script': ['a'],
      'slides': [
        {
          'title': 'Title',
          'bullets': ['b1'],
          'narration': 'नमुना',
        }
      ],
      'summary': 'sum',
      'mcqs': [
        {
          'question': 'Q?',
          'options': ['1', '2', '3', '4'],
          'correctIndex': 0,
          'explanation': 'e',
        }
      ],
      'notes': ['n1'],
      'createdAt': DateTime.now().toIso8601String(),
    }, 'legacy1');

    expect(legacy.id, 'legacy1');
    expect(legacy.premium.hasContent, isFalse);
    expect(legacy.mcqs.first.correctIndex, 0);

    final round = GeneratedLesson.fromMap(welcomeLesson.toMap(), 'rt');
    expect(round.slides.length, welcomeLesson.slides.length);
    expect(round.premium.importantFacts, isNotEmpty);
  });

  test('faculty narration and cache key helpers', () {
    final paced = facultyNarration('नमस्कार. हा एक धडा आहे.');
    expect(paced, isNotEmpty);
    expect(paced.contains('नमस्कार'), isTrue);
    expect(looksLikeMarathi(paced), isTrue);

    final merged = mergeTeachingParagraph([
      'मुद्दा एक',
      'समजा — हे महत्त्वाचे आहे',
    ]);
    expect(merged.contains('मुद्दा एक'), isTrue);
    expect(merged.length, greaterThan(20));

    final paragraph = buildFacultyTeachingParagraph(
      explain: 'संसद ही केंद्रीय विधिमंडळ आहे.',
      example: 'उदाहरणार्थ, अर्थसंकल्प प्रथम लोकसभेत येतो.',
      trick: 'स्मरण युक्ती — रा + लो + रा.',
      question: 'स्वतःला विचारा — संसदेचे तीन भाग कोणते?',
    );
    expect(paragraph.contains('विधिमंडळ'), isTrue);
    expect(paragraph.contains('उदाहरणार्थ'), isTrue);
    expect(paragraph.contains('रा + लो + रा'), isTrue);
    expect(paragraph.contains('विचारा'), isTrue);
    // Label prefixes are stripped for natural faculty speech.
    expect(paragraph.contains('स्मरण युक्ती —'), isFalse);

    final stage = buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.memoryTrick,
      body: 'Memory Trick: रा + लो + रा',
      marathi: false,
    );
    expect(stage.contains('रा + लो + रा'), isTrue);
    expect(stage.contains('Memory Trick:'), isFalse);

    final chunks = chunkTeachingParagraph(
      List.generate(40, (i) => 'वाक्य $i आहे.').join(' '),
      maxChars: 80,
    );
    expect(chunks.length, greaterThan(1));
    expect(chunks.every((c) => c.trim().isNotEmpty), isTrue);

    expect(kTeachingParagraphPause.inMilliseconds, greaterThan(500));
    expect(kSmartFacultyPipeline.length, 8);
    expect(kSmartFacultyPipeline.first, SmartFacultyStage.introduction);
    expect(kSmartFacultyPipeline.last, SmartFacultyStage.summary);

    final k1 = lessonCacheService.keyFor(question: 'ABC', chapterId: 'c1');
    final k2 = lessonCacheService.keyFor(question: 'abc', chapterId: 'c1');
    expect(k1, k2);

    final mcq = welcomeLesson.mcqs.first;
    expect(mcq.explanationFor(mcq.correctIndex), isNotEmpty);

    // Cloud TTS: Marathi WaveNet defaults + fallback/retry classification.
    expect(GoogleCloudTtsService.defaultMarathiVoice, 'mr-IN-Wavenet-A');
    expect(GoogleCloudTtsService.defaultMarathiLang, 'mr-IN');
    expect(GoogleCloudTtsService.isFallbackStatus(403), isTrue);
    expect(GoogleCloudTtsService.isRetryableStatus(429), isTrue);
    expect(GoogleCloudTtsService.isFallbackStatus(200), isFalse);
    expect(
      GoogleCloudTtsService.isFallbackException(
        const GoogleCloudTtsException(
          message: 'quota exceeded',
          statusCode: 403,
        ),
      ),
      isTrue,
    );
  });

  test('teaching sequence is Smart Faculty pedagogy not OCR bullet reading', () {
    final beats = teachingSequenceFor(welcomeLesson);

    // Continuous lecture: no inter-sentence pauseAfter flags.
    expect(beats.every((b) => !b.pauseAfter), isTrue);

    // Smart Faculty stages appear in order within each concept slide.
    final conceptSlideIndex = welcomeLesson.slides.indexWhere(
      (s) =>
          s.sceneType == LessonSceneType.mainExplanation ||
          s.sceneType == LessonSceneType.importantPoints ||
          s.sceneType == LessonSceneType.introduction,
    );
    expect(conceptSlideIndex, greaterThanOrEqualTo(0));
    final conceptBeats =
        beats.where((b) => b.slideIndex == conceptSlideIndex).toList();
    final stageOrder = <TeachingBeatKind>[
      TeachingBeatKind.introduction,
      TeachingBeatKind.concept,
      TeachingBeatKind.example,
      TeachingBeatKind.memoryTrick,
      TeachingBeatKind.pyq,
      TeachingBeatKind.mcq,
      TeachingBeatKind.revision,
      TeachingBeatKind.summary,
    ];
    var cursor = -1;
    for (final stage in stageOrder) {
      final next = conceptBeats.indexWhere((b) => b.kind == stage);
      expect(next, greaterThan(cursor), reason: 'missing or out-of-order $stage');
      cursor = next;
    }

    // Concept scripts teach in Marathi — not raw English OCR labels.
    final conceptSpeak = beats
        .where((b) => b.kind == TeachingBeatKind.concept)
        .map((b) => b.speakText)
        .join(' | ');
    expect(conceptSpeak, isNotEmpty);
    expect(looksLikeMarathi(conceptSpeak), isTrue);

    final exampleSpeak = beats
        .where((b) => b.kind == TeachingBeatKind.example)
        .map((b) => b.speakText)
        .join(' ');
    expect(exampleSpeak, isNotEmpty);

    // Must not sound like English OCR labels for premium cards.
    final spoken = beats.map((b) => b.speakText).join(' ');
    expect(spoken.contains('PYQ Insight.'), isFalse);
    expect(spoken.contains('Exam Tip.'), isFalse);
    expect(spoken.contains('Memory Trick.'), isFalse);
    expect(spoken.contains('Common Mistake.'), isFalse);
    expect(spoken.contains('AI MCQ.'), isFalse);
    expect(spoken.contains('PYQ Insight:'), isFalse);
    expect(spoken.contains('Memory Trick:'), isFalse);

    // Teacher must not OCR-read board bullets as the sole script.
    for (final slide in welcomeLesson.slides) {
      for (final bullet in slide.bullets) {
        final b = bullet.trim();
        if (b.length < 8) continue;
        final exactOnly = beats.any(
          (beat) => beat.speakText.trim() == b,
        );
        expect(exactOnly, isFalse, reason: 'beat OCR-reads bullet: $b');
      }
    }

    // One stage family per beat kind — pipeline is present without label spam.
    expect(
      beats.where((b) => b.kind == TeachingBeatKind.pyq).length,
      greaterThan(0),
    );
    expect(
      beats.where((b) => b.kind == TeachingBeatKind.mcq).length,
      greaterThan(0),
    );

    // Paragraphs stay within TTS-friendly size (chunked if needed).
    for (final b in beats) {
      expect(
        b.speakText.length,
        lessThanOrEqualTo(kMaxTeachingParagraphChars + 80),
      );
    }
  });

  test('script-only lessons still follow Smart Faculty stage order', () {
    final lesson = GeneratedLesson.fromMap({
      'question': 'संसद',
      'topicName': 'संसद',
      'subjectName': 'राज्यव्यवस्था',
      'script': [
        'नमस्कार. आज संसद शिकू.',
        'संसद म्हणजे केंद्रीय विधिमंडळ.',
        'उदाहरणार्थ अर्थसंकल्प लोकसभेत येतो.',
        'रा लो रा लक्षात ठेवा.',
        'मागील वर्षी हा फरक विचारला गेला.',
        'संसदेचे तीन भाग कोणते?',
        'विधिमंडळ आणि दोन सभागृहे आठवा.',
        'समारोप — संकल्पना पक्की.',
      ],
      'slides': <Map<String, dynamic>>[],
      'summary': 'सारांश',
      'mcqs': <Map<String, dynamic>>[],
      'notes': <String>['n'],
      'createdAt': DateTime.now().toIso8601String(),
    }, 'script-only');

    final beats = teachingSequenceFor(lesson);
    expect(beats, isNotEmpty);
    expect(beats.first.kind, TeachingBeatKind.introduction);
    expect(beats.any((b) => b.kind == TeachingBeatKind.concept), isTrue);
    expect(beats.any((b) => b.kind == TeachingBeatKind.example), isTrue);
    expect(beats.any((b) => b.kind == TeachingBeatKind.memoryTrick), isTrue);
    expect(beats.any((b) => b.kind == TeachingBeatKind.pyq), isTrue);
    expect(beats.any((b) => b.kind == TeachingBeatKind.mcq), isTrue);
    expect(beats.any((b) => b.kind == TeachingBeatKind.revision), isTrue);
    expect(beats.last.kind, TeachingBeatKind.summary);
  });
}
