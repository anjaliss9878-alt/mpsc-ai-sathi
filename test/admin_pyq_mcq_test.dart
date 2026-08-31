import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/bulk_mcq_row.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/bulk_pyq_row.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/models/test_item.dart';
import 'package:mpsc_combine_ai/models/test_result.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_content_repository.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_repository.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_progress_repository.dart';
import 'package:mpsc_combine_ai/services/ai_weakness_tracker.dart';
import 'package:mpsc_combine_ai/services/content_counts_service.dart';
import 'package:mpsc_combine_ai/services/content_index_resolver.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/flashcard_repository.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/smart_trick_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';
import 'package:mpsc_combine_ai/services/test_repository.dart';
import 'package:mpsc_combine_ai/services/video_repository.dart';
import 'package:mpsc_combine_ai/utils/correct_answer.dart';

Future<({String subjectId, String chapterId, String topicId})> _seedIndex(
  NotesRepository notes,
) async {
  await notes.ensureDefaultExam();
  final subjectId = await notes.addSubject(
    const SubjectItem(
      id: '',
      title: 'राज्यशास्त्र',
      subtitle: '',
      iconName: 'account_balance',
      order: 0,
      slug: 'rajyashastra',
      nameEn: 'Polity',
      examId: kDefaultExamId,
      published: true,
    ),
  );
  final chapterId = await notes.addChapter(
    ChapterItem(
      id: '',
      subjectId: subjectId,
      title: 'मूलभूत हक्क',
      titleEn: 'Fundamental Rights',
      order: 0,
      examId: kDefaultExamId,
      nodeType: contentNodeTypeToString(ContentNodeType.chapter),
      published: true,
    ),
  );
  final topicId = await notes.addChapter(
    ChapterItem(
      id: '',
      subjectId: subjectId,
      title: 'अनुच्छेद 14',
      titleEn: 'Article 14',
      order: 0,
      examId: kDefaultExamId,
      parentChapterId: chapterId,
      nodeType: contentNodeTypeToString(ContentNodeType.topic),
      published: true,
    ),
  );
  return (subjectId: subjectId, chapterId: chapterId, topicId: topicId);
}

List<McqItem> _fiveMcqs({
  required String subjectId,
  required String chapterId,
  required String topicId,
  required NoteWorkflowStatus status,
}) {
  const questions = [
    'Equality before law is guaranteed by which Article?',
    'Article 14 applies to?',
    'Reasonable classification under Article 14 requires?',
    'Article 14 is part of which Part of the Constitution?',
    'Which case is closely linked with Article 14 equality?',
  ];
  return [
    for (var i = 0; i < questions.length; i++)
      McqItem(
        id: '',
        setTitle: 'Article 14 — Practice Set',
        subject: 'Polity',
        difficulty: 'Medium',
        question: questions[i],
        options: const ['Article 14', 'Article 19', 'Article 21', 'Article 32'],
        correctIndex: 0,
        explanation: 'Article 14 guarantees equality before law.',
        order: i,
        subjectId: subjectId,
        chapterId: chapterId,
        topicId: topicId,
        examId: kDefaultExamId,
        targetGroup: 'groupB',
        published: status == NoteWorkflowStatus.published,
        status: status,
      ),
  ];
}

void main() {
  test('correct answer parser accepts A/B/C/D and 1-based numbers', () {
    const opts = ['W', 'X', 'Y', 'Z'];
    expect(parseCorrectAnswer('B', opts), 1);
    expect(parseCorrectAnswer('3', opts), 2);
    expect(parseCorrectAnswer('Y', opts), 2);
    expect(correctAnswerLetter(0), 'A');
  });

  test('target group labels reject empty and Rajyaseva-only noise', () {
    expect(isValidTargetGroupLabel('Group B'), isTrue);
    expect(isValidTargetGroupLabel('both'), isTrue);
    expect(isValidTargetGroupLabel(''), isFalse);
    expect(ContentIndexResolver.isAllowedExamLabel('Rajyaseva'), isFalse);
    expect(ContentIndexResolver.isAllowedExamLabel('MPSC Combine'), isTrue);
  });

  test('PYQ / MCQ / Test round-trip keep Content Index ids and draft hidden', () {
    final pyq = PyqItem(
      id: 'pyq1',
      title: 'Article 14 PYQ',
      subtitle: '',
      fileUrl: '',
      order: 1,
      year: 2023,
      examName: 'MPSC Combine',
      question: 'Article 14 guarantees?',
      answer: 'A',
      explanation: 'Equality before law.',
      subjectId: 'pol',
      chapterId: 'fr',
      topicId: 'a14',
      examId: kDefaultExamId,
      targetGroup: 'groupB',
      options: const ['Equality', 'Speech', 'Life', 'Religion'],
      correctIndex: 0,
      difficulty: 'Medium',
      source: 'MPSC 2023',
      published: false,
      status: NoteWorkflowStatus.draft,
    );
    final pyqMap = pyq.toMap();
    expect(pyqMap['published'], isFalse);
    expect(pyqMap['status'], 'draft');
    expect(pyqMap['examId'], kDefaultExamId);
    expect(pyqMap['topicId'], 'a14');
    expect(pyqMap['groupId'], 'groupB');
    expect(PyqItem.fromMap(pyqMap, 'pyq1').isStudentVisible, isFalse);

    final published = PyqItem.fromMap({
      ...pyqMap,
      'status': 'published',
      'published': true,
    }, 'pyq1');
    expect(published.isStudentVisible, isTrue);

    final test = TestItem(
      id: 't1',
      title: 'Article 14 Mini Test',
      subtitle: '',
      durationSeconds: 300,
      correctMarks: 2,
      negativeMarks: 0.5,
      questions: const [
        TestQuestion(
          question: 'Q1',
          options: ['A', 'B', 'C', 'D'],
          correctIndex: 0,
          explanation: '',
        ),
      ],
      order: 0,
      examId: kDefaultExamId,
      targetGroup: 'groupB',
      subjectId: 'pol',
      chapterId: 'fr',
      topicId: 'a14',
      difficulty: 'Medium',
      instructions: 'Attempt all.',
      published: false,
      status: NoteWorkflowStatus.draft,
    );
    expect(TestItem.fromMap(test.toMap(), 't1').isStudentVisible, isFalse);
    expect(TestItem.fromMap({'title': 'Legacy'}, 'legacy').isStudentVisible, isTrue);
  });

  test('PYQ bulk preview validates missing fields, duplicates, target, exam', () {
    final index = ContentIndexResolver(
      exams: [ExamItem.mpscCombine()],
      subjects: const [
        SubjectItem(
          id: 'pol',
          title: 'Polity',
          subtitle: '',
          iconName: 'x',
          order: 0,
          nameEn: 'Polity',
        ),
      ],
      chapters: [
        ChapterItem(
          id: 'fr',
          subjectId: 'pol',
          title: 'Fundamental Rights',
          order: 0,
          nodeType: 'chapter',
        ),
        ChapterItem(
          id: 'a14',
          subjectId: 'pol',
          title: 'Article 14',
          order: 0,
          parentChapterId: 'fr',
          nodeType: 'topic',
        ),
      ],
    );

    final good = BulkPyqRow.parse(2, {
      'exam': 'MPSC Combine',
      'target group': 'Group B',
      'year': '2023',
      'subject': 'Polity',
      'chapter': 'Fundamental Rights',
      'topic': 'Article 14',
      'question': 'Equality is in which article?',
      'option a': '14',
      'option b': '19',
      'option c': '21',
      'option d': '32',
      'correct answer': 'A',
      'explanation': 'Art. 14',
      'difficulty': 'Easy',
      'source': '2023',
      'tags': 'polity',
    }, index: index);
    expect(good.isValid, isTrue);
    expect(good.topicId, 'a14');
    expect(good.targetGroup, 'groupB');

    final missing = BulkPyqRow.parse(3, {
      'exam': 'Rajyaseva',
      'target group': 'Group Z',
      'question': '',
    }, index: index);
    expect(missing.errors, contains('Question is empty'));
    expect(missing.errors, contains('Missing subject'));
    expect(missing.errors, contains('Missing chapter'));
    expect(missing.errors, contains('Missing topic'));
    expect(missing.errors, contains('Missing answer'));
    expect(missing.errors, contains('Invalid target group'));
    expect(missing.errors, contains('Invalid exam (MPSC Combine only)'));
  });

  test('MCQ bulk requires four options, answer, and index ids; stays conceptually DRAFT', () {
    final index = ContentIndexResolver(
      exams: [ExamItem.mpscCombine()],
      subjects: const [
        SubjectItem(
          id: 'pol',
          title: 'Polity',
          subtitle: '',
          iconName: 'x',
          order: 0,
          nameEn: 'Polity',
        ),
      ],
      chapters: [
        ChapterItem(
          id: 'fr',
          subjectId: 'pol',
          title: 'Fundamental Rights',
          order: 0,
        ),
        ChapterItem(
          id: 'a14',
          subjectId: 'pol',
          title: 'Article 14',
          order: 0,
          parentChapterId: 'fr',
          nodeType: 'topic',
        ),
      ],
    );
    final row = BulkMcqRow.parse(2, {
      'exam': 'MPSC Combine',
      'target group': 'Group B',
      'subject': 'Polity',
      'chapter': 'Fundamental Rights',
      'topic': 'Article 14',
      'question': 'Article 14 is?',
      'option a': 'Equality',
      'option b': 'Speech',
      'option c': 'Life',
      'option d': 'Religion',
      'correct answer': 'A',
      'explanation': 'Equality',
    }, index: index);
    expect(row.isValid, isTrue);
    expect(row.correctIndex, 0);
    expect(row.topicId, 'a14');

    final bad = BulkMcqRow.parse(3, {
      'question': 'Q',
      'option a': '1',
      'option b': '2',
    }, index: index);
    expect(bad.errors, contains('Needs four options (A–D)'));
    expect(bad.errors, contains('Missing answer'));
  });

  test('published PYQ, 5-question MCQ set, and Test are student-visible; drafts are not',
      () async {
    final db = FakeFirebaseFirestore();
    final notes = NotesRepository(firestore: db);
    final pyqs = PyqRepository(firestore: db);
    final mcqs = McqRepository(firestore: db);
    final tests = TestRepository(firestore: db);
    final ids = await _seedIndex(notes);

    await pyqs.add(
      PyqItem(
        id: '',
        title: 'Article 14 PYQ 2023',
        subtitle: '',
        fileUrl: '',
        order: 1,
        year: 2023,
        examName: 'MPSC Combine',
        question: 'Article 14 guarantees equality before law.',
        answer: 'A',
        explanation: 'Part III.',
        subject: 'Polity',
        subjectId: ids.subjectId,
        chapterId: ids.chapterId,
        topicId: ids.topicId,
        examId: kDefaultExamId,
        targetGroup: 'groupB',
        options: const ['Equality', 'Speech', 'Life', 'Religion'],
        correctIndex: 0,
        published: true,
        status: NoteWorkflowStatus.published,
      ),
    );
    await pyqs.add(
      PyqItem(
        id: '',
        title: 'Hidden draft PYQ',
        subtitle: '',
        fileUrl: '',
        order: 2,
        question: 'Draft only',
        subjectId: ids.subjectId,
        chapterId: ids.chapterId,
        topicId: ids.topicId,
        published: false,
        status: NoteWorkflowStatus.draft,
      ),
    );

    for (final q in _fiveMcqs(
      subjectId: ids.subjectId,
      chapterId: ids.chapterId,
      topicId: ids.topicId,
      status: NoteWorkflowStatus.published,
    )) {
      await mcqs.add(q);
    }
    await mcqs.add(
      McqItem(
        id: '',
        setTitle: 'Hidden draft set',
        subject: 'Polity',
        difficulty: 'Easy',
        question: 'Should not show',
        options: const ['A', 'B', 'C', 'D'],
        correctIndex: 0,
        explanation: '',
        order: 99,
        subjectId: ids.subjectId,
        chapterId: ids.chapterId,
        topicId: ids.topicId,
        published: false,
        status: NoteWorkflowStatus.draft,
      ),
    );

    await tests.add(
      TestItem(
        id: '',
        title: 'Article 14 Mini Test',
        subtitle: '5 Q · Group B',
        durationSeconds: 300,
        correctMarks: 2,
        negativeMarks: 0.5,
        order: 1,
        examId: kDefaultExamId,
        targetGroup: 'groupB',
        subjectId: ids.subjectId,
        chapterId: ids.chapterId,
        topicId: ids.topicId,
        difficulty: 'Medium',
        instructions: 'Attempt all questions.',
        published: true,
        status: NoteWorkflowStatus.published,
        questions: [
          for (final q in _fiveMcqs(
            subjectId: ids.subjectId,
            chapterId: ids.chapterId,
            topicId: ids.topicId,
            status: NoteWorkflowStatus.published,
          ))
            TestQuestion(
              question: q.question,
              options: q.options,
              correctIndex: q.correctIndex,
              explanation: q.explanation,
            ),
        ],
      ),
    );

    final studentPyqs = await pyqs.watchPublished().first;
    expect(studentPyqs.map((p) => p.title), ['Article 14 PYQ 2023']);

    final studentMcqs = await mcqs.watchPublished().first;
    expect(studentMcqs, hasLength(5));
    expect(studentMcqs.every((q) => q.setTitle == 'Article 14 — Practice Set'), isTrue);

    final studentTests = await tests.watchPublished().first;
    expect(studentTests.map((t) => t.title), ['Article 14 Mini Test']);
    expect(studentTests.first.questions, hasLength(5));

    final counts = await ContentCountsService(
      notes: notes,
      mcqs: mcqs,
      pyqs: pyqs,
      tests: tests,
      videos: VideoRepository(firestore: db),
      lessons: AiLessonRepository(firestore: db),
      flashcards: FlashcardRepository(firestore: db),
      smartTricks: SmartTrickRepository(firestore: db),
      currentAffairs: CurrentAffairsRepository(firestore: db),
      aiTeacherContent: AiTeacherContentRepository(firestore: db),
    ).forTopic(topicId: ids.topicId, topicTitle: 'Article 14');
    expect(counts.pyqs, 2);
    expect(counts.mcqs, 6);
    expect(counts.tests, 1);
  });

  test('completing 5 MCQs writes testAttempts and weakness/admin can read them',
      () async {
    final db = FakeFirebaseFirestore();
    final notes = NotesRepository(firestore: db);
    final ids = await _seedIndex(notes);
    final progress = StudentProgressRepository(firestore: db);
    final classroom = LessonProgressRepository(firestore: db);
    final syllabus = FirestoreSyllabusProgressTracker(
      notes: notes,
      classroom: classroom,
      progress: progress,
    );
    final weakness = FirestoreAiWeaknessTracker(
      progress: progress,
      classroom: classroom,
      syllabus: syllabus,
      profiles: ProfileRepository(firestore: db),
    );

    final qs = _fiveMcqs(
      subjectId: ids.subjectId,
      chapterId: ids.chapterId,
      topicId: ids.topicId,
      status: NoteWorkflowStatus.published,
    );
    final result = TestResult(
      testTitle: qs.first.setTitle,
      dateTime: DateTime(2026, 8, 27, 17),
      totalQuestions: 5,
      attempted: 5,
      correct: 2,
      wrong: 3,
      score: 2,
      maxScore: 5,
      percentage: 40,
      timeTakenSeconds: 120,
      questionResults: [
        for (final q in qs)
          QuestionResult(
            question: q.question,
            options: q.options,
            correctIndex: q.correctIndex,
            selectedIndex: 0,
            explanation: q.explanation,
          ),
      ],
    );

    await progress.saveTestAttempt(
      'student_b',
      result,
      testId: 'mcq_${qs.first.setTitle.hashCode}',
      kind: 'mcq',
      subjectId: ids.subjectId,
      chapterId: ids.chapterId,
    );

    final attempts = await progress.getTestAttempts('student_b');
    expect(attempts, hasLength(1));
    expect(attempts.first.kind, 'mcq');
    expect(attempts.first.totalQuestions, 5);
    expect(attempts.first.subjectId, ids.subjectId);

    final snap = await weakness.load('student_b');
    expect(snap.hasPerformance, isTrue);

    final adminView = await progress.getTestAttempts('student_b');
    expect(adminView.first.percentage, 40);
  });
}
