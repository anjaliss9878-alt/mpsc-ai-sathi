import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/generated_quiz_screen.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_generation_service.dart';

void main() {
  testWidgets('GeneratedQuizScreen shows questions and scores correctly',
      (tester) async {
    final mcqs = welcomeLesson.mcqs;
    expect(mcqs.length, greaterThanOrEqualTo(1));

    await tester.pumpWidget(
      MaterialApp(
        home: GeneratedQuizScreen(
          topicName: welcomeLesson.topicName,
          mcqs: mcqs,
        ),
      ),
    );

    expect(find.textContaining('Quiz ·'), findsOneWidget);
    expect(find.textContaining('Question 1 of'), findsOneWidget);

    // Tap first option (may or may not be correct).
    await tester.tap(find.text(mcqs.first.options.first));
    await tester.pump();
    expect(find.text('Next Question'), findsOneWidget);

    await tester.tap(find.text('Next Question'));
    await tester.pump();
    if (mcqs.length > 1) {
      expect(find.textContaining('Question 2 of'), findsOneWidget);
    }
  });

  test('Mock lesson generation remains usable without API key path', () async {
    final mock = MockLessonGenerationService();
    final lesson = await mock.generateLesson(
      question: 'भारतीय संसद म्हणजे काय?',
      subjectContext: 'Polity',
    );
    expect(lesson.slides, isNotEmpty);
    expect(lesson.mcqs, isNotEmpty);
    expect(lesson.notes, isNotEmpty);
    expect(lesson.topicName, isNotEmpty);

    // Round-trip map must keep quiz usable for GeneratedQuizScreen.
    final round = GeneratedLesson.fromMap(lesson.toMap(), 'mock-rt');
    expect(round.mcqs.first.options.length, 4);
    expect(round.mcqs.first.correctIndex, inInclusiveRange(0, 3));
  });

  test('worker /ai/lesson envelope parses into slides with narration', () {
    final lesson = GeneratedLesson.fromMap({
      'topicName': 'गंगा नदी',
      'question': 'गंगा नदी',
      'script': ['गंगा ही भारतातील प्रमुख नदी आहे.', 'दुसरा परिच्छेद.'],
      'summary': 'गंगा नदी',
      'slides': [
        for (var i = 0; i < 5; i++)
          {
            'title': 'स्लाइड ${i + 1}',
            'bullets': ['मुद्दा'],
            'sceneType': i == 0
                ? 'introduction'
                : (i == 4 ? 'summary' : 'mainExplanation'),
            'narration': 'स्पष्टीकरण ${i + 1}',
          },
      ],
      'mcqs': [
        {
          'question': 'प्रश्न',
          'options': ['अ', 'ब', 'क', 'ड'],
          'correctIndex': 0,
        },
      ],
      'pyqs': [],
    }, '');
    expect(lesson.script, isNotEmpty);
    expect(lesson.slides.length, 5);
    for (var i = 0; i < lesson.slides.length; i++) {
      expect(lesson.slides[i].narration, isNotEmpty);
    }
    expect(isPlaceholderLesson(lesson, topic: 'गंगा नदी'), isFalse);
  });

  test('premium parse tolerates missing and partial maps', () {
    final empty = LessonPremiumExtras.fromMap(null);
    expect(empty.hasContent, isFalse);

    final partial = LessonPremiumExtras.fromMap({
      'importantFacts': ['fact'],
      'examTips': 'not-a-list',
      'quickRevision': ['tip1', 'tip2'],
      'onePageSummary': 42,
    });
    expect(partial.hasContent, isTrue);
    expect(partial.importantFacts, ['fact']);
    expect(partial.examTips, ['not-a-list']);
    expect(partial.quickRevision, 'tip1\ntip2');
    expect(partial.onePageSummary, isEmpty);
  });
}
