import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lecture_lesson_sanitizer.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/speakable_marathi.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';

void main() {
  test('script cleaning expands GDP UPSC MPSC and drops symbols', () {
    final spoken = speakableMarathi('MPSC / UPSC GDP + 7% • Page 4');
    expect(spoken.contains('/'), isFalse);
    expect(spoken.contains('%'), isFalse);
    expect(spoken.contains('+'), isFalse);
    expect(spoken.contains('•'), isFalse);
    expect(spoken.toLowerCase().contains('page'), isFalse);
    expect(spoken, contains('एम पी एस सी'));
    expect(spoken, contains('यू पी एस सी'));
    expect(spoken, contains('जी डी पी'));
    expect(spoken, contains('टक्के'));
  });

  test('sanitizeLectureLesson keeps pyqs and mcqs', () {
    final lesson = sanitizeLectureLesson(
      GeneratedLesson(
        question: 'GDP',
        topicName: 'GDP',
        subjectName: 'Economy',
        script: const ['GDP + 2%'],
        slides: const [
          GeneratedSlide(
            title: 'GDP',
            bullets: ['Page 1'],
            narration: 'GDP is 7% / year',
          ),
        ],
        summary: 'GDP',
        mcqs: const [
          GeneratedMcq(
            question: 'GDP म्हणजे?',
            options: ['अ', 'ब', 'क', 'ड'],
            correctIndex: 0,
            explanation: 'जी डी पी',
          ),
        ],
        notes: const ['GDP नोट'],
        createdAt: DateTime(2026, 1, 1),
        pyqs: const [
          GeneratedPyq(
            question: 'GDP PYQ',
            year: '2023',
            answer: 'उत्तर',
            analysis: 'विश्लेषण',
          ),
        ],
      ),
    );
    expect(lesson.pyqs, hasLength(1));
    expect(lesson.mcqs, hasLength(1));
    expect(lesson.slides.first.narration.contains('%'), isFalse);
    expect(lesson.slides.first.narration.contains('/'), isFalse);
  });

  test('detects example topics from the upgrade prompt', () {
    expect(detectMpscTeachingSubject('संसद'), MpscTeachingSubject.polity);
    expect(detectMpscTeachingSubject('गंगा नदी'), MpscTeachingSubject.geography);
    expect(detectMpscTeachingSubject('पेशवे'), MpscTeachingSubject.history);
    expect(detectMpscTeachingSubject('GDP'), MpscTeachingSubject.economics);
    expect(detectMpscTeachingSubject('मान्सून'), MpscTeachingSubject.geography);
    expect(detectMpscTeachingSubject('भारतीय राज्यघटना'), MpscTeachingSubject.polity);
    expect(
      detectMpscTeachingSubject('महाराष्ट्रातील मृदा'),
      MpscTeachingSubject.geography,
    );
  });

  test('MCQ kind and difficulty parse from JSON', () {
    final q = GeneratedMcq.fromMap({
      'question': 'विधान कारण',
      'options': ['अ', 'ब', 'क', 'ड'],
      'correctIndex': 1,
      'explanation': 'योग्य',
      'difficulty': 'hard',
      'kind': 'assertion-reason',
    });
    expect(q.difficulty, McqDifficulty.hard);
    expect(q.kind, McqKind.assertionReason);
    expect(q.kindLabelMr, 'विधान-कारण');
  });

  test('sansad romanization is not treated as a placeholder Parliament miss', () {
    final lesson = GeneratedLesson(
      question: 'sansad',
      topicName: 'भारतीय संसद',
      subjectName: 'राज्यव्यवस्था · Polity Teacher',
      script: const ['आज आपण संसदेची रचना शिकणार आहोत.'],
      slides: const [
        GeneratedSlide(
          title: 'संसद',
          bullets: ['लोकसभा', 'राज्यसभा'],
          narration: 'भारतीय संसद द्विसदनीय आहे.',
        ),
      ],
      summary: 'संसद म्हणजे भारताचे सर्वोच्च कायदेमंडळ.',
      mcqs: const [],
      notes: const ['संसद = लोकसभा + राज्यसभा'],
      createdAt: DateTime(2026, 1, 1),
    );
    expect(isPlaceholderLesson(lesson, topic: 'sansad'), isFalse);
    expect(isPlaceholderLesson(lesson, topic: 'संसद'), isFalse);
  });
}
