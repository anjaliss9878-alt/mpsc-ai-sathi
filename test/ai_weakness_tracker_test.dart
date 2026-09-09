import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/data/diagnostic_questions.dart';
import 'package:mpsc_combine_ai/data/student_onboarding.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/models/test_result.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_progress_repository.dart';
import 'package:mpsc_combine_ai/services/ai_weakness_tracker.dart';
import 'package:mpsc_combine_ai/services/daily_planner_service.dart';
import 'package:mpsc_combine_ai/services/diagnostic_service.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';

class _FixedSyllabus extends SyllabusProgressTracker {
  _FixedSyllabus(this.snapshot);
  final SyllabusProgressSnapshot snapshot;
  @override
  Future<SyllabusProgressSnapshot> load(String uid) async => snapshot;
}

SyllabusTopicProgress _topic({
  required String subjectId,
  required String subject,
  required String chapterId,
  required String chapter,
  SyllabusTopicStatus status = SyllabusTopicStatus.pending,
  int minutes = 20,
  List<String> tags = const [],
  DateTime? lastStudiedAt,
  int revisionCount = 0,
}) {
  return SyllabusTopicProgress(
    subject: SubjectItem(
      id: subjectId,
      title: subject,
      subtitle: '',
      iconName: 'menu_book',
      order: 0,
    ),
    chapter: ChapterItem(
      id: chapterId,
      subjectId: subjectId,
      title: chapter,
      order: 0,
      estimatedStudyMinutes: minutes,
      tags: tags,
    ),
    status: status,
    lastStudiedAt: lastStudiedAt,
    revisionCount: revisionCount,
  );
}

SyllabusProgressSnapshot _syllabus() {
  return SyllabusProgressSnapshot(
    topics: [
      _topic(
        subjectId: 'pol',
        subject: 'Polity',
        chapterId: 'rights',
        chapter: 'Fundamental Rights',
        status: SyllabusTopicStatus.completed,
        minutes: 50,
        tags: const ['important'],
      ),
      _topic(
        subjectId: 'pol',
        subject: 'Polity',
        chapterId: 'preamble',
        chapter: 'Preamble',
        status: SyllabusTopicStatus.pending,
      ),
      _topic(
        subjectId: 'geo',
        subject: 'Geography',
        chapterId: 'earth',
        chapter: 'Earth',
        status: SyllabusTopicStatus.completed,
      ),
    ],
  );
}

PerformanceSample _sample({
  required DateTime at,
  required int correct,
  required int attempted,
  String chapterId = 'rights',
  String subjectId = 'pol',
  String subject = 'Polity',
  String label = 'Fundamental Rights',
  String source = 'test',
}) {
  return PerformanceSample(
    at: at,
    attempted: attempted,
    correct: correct,
    wrong: attempted - correct,
    source: source,
    label: label,
    subjectId: subjectId,
    chapterId: chapterId,
    subjectTitle: subject,
  );
}

void main() {
  final now = DateTime(2026, 8, 21, 12);

  test('accuracy is correct / attempted × 100', () {
    expect(weaknessAccuracyPercent(correct: 0, attempted: 0), 0);
    expect(weaknessAccuracyPercent(correct: 3, attempted: 10), 30);
    expect(weaknessAccuracyPercent(correct: 8, attempted: 10), 80);
  });

  test('classification uses configurable thresholds', () {
    const t = WeaknessThresholds.defaults;
    expect(t.bandFor(70), WeaknessBand.strong);
    expect(t.bandFor(69), WeaknessBand.improving);
    expect(t.bandFor(50), WeaknessBand.improving);
    expect(t.bandFor(49), WeaknessBand.weak);
    expect(t.bandFor(0), WeaknessBand.weak);

    const custom = WeaknessThresholds(strongMin: 90, improvingMin: 70, weakMin: 50);
    expect(custom.bandFor(85), WeaknessBand.improving);
    expect(custom.bandFor(49), WeaknessBand.critical);
  });

  test('topic and subject aggregation use real question counts', () {
    final result = analyzeWeakness(
      WeaknessAnalysisInput(
        now: now,
        syllabus: _syllabus(),
        samples: [
          _sample(at: now, correct: 2, attempted: 10, chapterId: 'rights'),
          _sample(
            at: now,
            correct: 8,
            attempted: 10,
            chapterId: 'preamble',
            label: 'Preamble',
          ),
        ],
      ),
    );
    final rights = result.topics.firstWhere((t) => t.chapterId == 'rights');
    expect(rights.accuracyPercent, 20);
    expect(rights.band, WeaknessBand.weak);
    expect(rights.attempted, 10);
    expect(rights.correct, 2);
    expect(rights.wrong, 8);

    final polity = result.subjects.firstWhere((s) => s.subjectId == 'pol');
    expect(polity.attempted, 20);
    expect(polity.correct, 10);
    expect(polity.accuracyPercent, 50);
    expect(polity.band, WeaknessBand.improving);
  });

  test('trend improving / declining / insufficient', () {
    expect(
      weaknessTrend(
        recentAccuracy: 70,
        previousAccuracy: 40,
        recentSamples: 2,
        previousSamples: 2,
      ),
      PerformanceTrend.improving,
    );
    expect(
      weaknessTrend(
        recentAccuracy: 30,
        previousAccuracy: 70,
        recentSamples: 2,
        previousSamples: 2,
      ),
      PerformanceTrend.declining,
    );
    expect(
      weaknessTrend(
        recentAccuracy: 50,
        previousAccuracy: 52,
        recentSamples: 2,
        previousSamples: 2,
      ),
      PerformanceTrend.stable,
    );
    expect(
      weaknessTrend(
        recentAccuracy: 90,
        previousAccuracy: null,
        recentSamples: 1,
        previousSamples: 0,
      ),
      PerformanceTrend.insufficient,
    );

    final improving = analyzeWeakness(
      WeaknessAnalysisInput(
        now: now,
        syllabus: _syllabus(),
        samples: [
          _sample(at: DateTime(2026, 7, 26), correct: 2, attempted: 10),
          _sample(at: DateTime(2026, 7, 28), correct: 3, attempted: 10),
          _sample(at: DateTime(2026, 8, 12), correct: 8, attempted: 10),
          _sample(at: DateTime(2026, 8, 18), correct: 9, attempted: 10),
        ],
      ),
    );
    expect(
      improving.topics.singleWhere((t) => t.chapterId == 'rights').trend,
      PerformanceTrend.improving,
    );

    final empty = analyzeWeakness(
      WeaknessAnalysisInput(
        now: now,
        syllabus: _syllabus(),
        samples: const [],
      ),
    );
    expect(empty.hasPerformance, isFalse);
    expect(empty.overallTrend, PerformanceTrend.insufficient);
    expect(empty.priorityWeakAreas, isEmpty);
  });

  test('empty / insufficient data does not invent numbers', () {
    final result = analyzeWeakness(
      WeaknessAnalysisInput(
        now: now,
        syllabus: _syllabus(),
        samples: [
          _sample(at: now, correct: 0, attempted: 0),
        ],
      ),
    );
    expect(result.hasPerformance, isFalse);
    expect(result.overallAccuracy, 0);
    expect(result.topics, isEmpty);
  });

  test('repeated mistakes, stale revision, and exam importance raise priority', () {
    final result = analyzeWeakness(
      WeaknessAnalysisInput(
        now: now,
        syllabus: _syllabus(),
        samples: [
          _sample(at: DateTime(2026, 8, 1), correct: 3, attempted: 10),
          _sample(at: DateTime(2026, 8, 18), correct: 2, attempted: 10),
        ],
      ),
    );
    final rights = result.topics.singleWhere((t) => t.chapterId == 'rights');
    expect(rights.repeatedMistakes, isTrue);
    expect(rights.examImportant, isTrue);
    expect(rights.priority, greaterThan(40));
    expect(rights.band, WeaknessBand.weak);
    expect(result.weakCompleted.any((t) => t.chapterId == 'rights'), isTrue);
  });

  test('syllabus mix distinguishes incomplete vs completed weakness', () {
    final result = analyzeWeakness(
      WeaknessAnalysisInput(
        now: now,
        syllabus: _syllabus(),
        samples: [
          _sample(at: now, correct: 4, attempted: 10, chapterId: 'rights'),
          _sample(
            at: now,
            correct: 4,
            attempted: 10,
            chapterId: 'preamble',
            label: 'Preamble',
          ),
          _sample(
            at: now,
            correct: 9,
            attempted: 10,
            chapterId: 'earth',
            subjectId: 'geo',
            subject: 'Geography',
            label: 'Earth',
          ),
        ],
      ),
    );
    expect(result.weakIncomplete.map((t) => t.chapterId), contains('preamble'));
    expect(result.weakCompleted.map((t) => t.chapterId), contains('rights'));
    expect(result.strongCompleted.map((t) => t.chapterId), contains('earth'));
  });

  test('planner-facing snapshot sorts weak topics by priority', () {
    final snap = WeaknessSnapshot(
      signals: const [
        WeakTopicSignal(
          label: 'A',
          scorePercent: 50,
          source: 'test',
          priority: 10,
        ),
        WeakTopicSignal(
          label: 'B',
          scorePercent: 20,
          source: 'test',
          priority: 40,
        ),
      ],
    );
    expect(snap.weakTopics.first.label, 'B');
    expect(snap.hasPoorRecentTests, isTrue);
  });

  test('student data is isolated by uid', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('subjects').doc('pol').set(
          SubjectItem(
            id: 'pol',
            title: 'Polity',
            subtitle: '',
            iconName: 'menu_book',
            order: 1,
          ).toMap(),
        );
    await db.collection('chapters').doc('rights').set(
          ChapterItem(
            id: 'rights',
            subjectId: 'pol',
            title: 'Fundamental Rights',
            order: 1,
          ).toMap(),
        );

    final progress = StudentProgressRepository(firestore: db);
    await progress.saveTestAttempt(
      'student_a',
      TestResult(
        testTitle: 'Fundamental Rights mock',
        dateTime: now,
        totalQuestions: 10,
        attempted: 10,
        correct: 3,
        wrong: 7,
        score: 6,
        maxScore: 20,
        percentage: 30,
        timeTakenSeconds: 120,
        questionResults: const [],
      ),
    );
    await progress.saveTestAttempt(
      'student_b',
      TestResult(
        testTitle: 'Fundamental Rights mock',
        dateTime: now,
        totalQuestions: 10,
        attempted: 10,
        correct: 9,
        wrong: 1,
        score: 18,
        maxScore: 20,
        percentage: 90,
        timeTakenSeconds: 90,
        questionResults: const [],
      ),
    );

    final tracker = FirestoreAiWeaknessTracker(
      progress: progress,
      classroom: LessonProgressRepository(firestore: db),
      syllabus: FirestoreSyllabusProgressTracker(
        notes: NotesRepository(firestore: db),
        classroom: LessonProgressRepository(firestore: db),
        progress: progress,
      ),
      profiles: ProfileRepository(firestore: db),
    );

    final a = await tracker.load('student_a', now: now);
    final b = await tracker.load('student_b', now: now);
    expect(a.analysis?.overallCorrect, 3);
    expect(b.analysis?.overallCorrect, 9);
    expect(a.weakTopics, isNotEmpty);
    expect(b.strongTopics, isNotEmpty);
    expect(a.analysis?.topics.single.accuracyPercent, 30);
    expect(b.analysis?.topics.single.accuracyPercent, 90);
  });

  test('MCQ practice attempts update weakness with kind mcq', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('subjects').doc('geo').set(
          SubjectItem(
            id: 'geo',
            title: 'Geography',
            subtitle: '',
            iconName: 'menu_book',
            order: 1,
          ).toMap(),
        );
    await db.collection('chapters').doc('monsoon').set(
          ChapterItem(
            id: 'monsoon',
            subjectId: 'geo',
            title: 'Monsoon',
            order: 1,
          ).toMap(),
        );
    final progress = StudentProgressRepository(firestore: db);
    await progress.saveTestAttempt(
      'student_a',
      TestResult(
        testTitle: 'Monsoon MCQ set',
        dateTime: now,
        totalQuestions: 10,
        attempted: 10,
        correct: 4,
        wrong: 6,
        score: 4,
        maxScore: 10,
        percentage: 40,
        timeTakenSeconds: 80,
        questionResults: const [],
      ),
      kind: 'mcq',
      subjectId: 'geo',
      chapterId: 'monsoon',
    );
    final tracker = FirestoreAiWeaknessTracker(
      progress: progress,
      classroom: LessonProgressRepository(firestore: db),
      syllabus: FirestoreSyllabusProgressTracker(
        notes: NotesRepository(firestore: db),
        classroom: LessonProgressRepository(firestore: db),
        progress: progress,
      ),
      profiles: ProfileRepository(firestore: db),
    );
    final snap = await tracker.load('student_a', now: now);
    expect(snap.hasPerformance, isTrue);
    expect(snap.signals.single.chapterId, 'monsoon');
    expect(snap.signals.single.source, 'mcq');
    expect(snap.signals.single.scorePercent, 40);
    expect(snap.weakTopics, isNotEmpty);
  });

  test('0% with real attempts is Weak, unattempted topics are omitted', () {
    final result = analyzeWeakness(
      WeaknessAnalysisInput(
        now: now,
        syllabus: _syllabus(),
        samples: [
          _sample(at: now, correct: 0, attempted: 4, chapterId: 'rights'),
        ],
      ),
    );
    expect(result.topics.single.chapterId, 'rights');
    expect(result.topics.single.accuracyPercent, 0);
    expect(result.topics.single.band, WeaknessBand.weak);
    expect(result.topics.any((t) => t.chapterId == 'earth'), isFalse);
    expect(result.topics.any((t) => t.band == WeaknessBand.insufficient), isFalse);
  });

  test('PYQ without chapter metadata is not guessed onto a topic', () {
    final result = analyzeWeakness(
      WeaknessAnalysisInput(
        now: now,
        syllabus: _syllabus(),
        samples: [
          PerformanceSample(
            at: now,
            attempted: 1,
            correct: 1,
            wrong: 0,
            source: 'pyq',
            label: 'MPSC 2019 Paper',
            subjectId: '',
            chapterId: '',
            subjectTitle: '',
          ),
        ],
      ),
    );
    expect(result.hasPerformance, isTrue);
    expect(result.topics, isEmpty);
  });

  test('diagnostic area stays Economy; later MCQ updates latest band and planner',
      () async {
    final db = FakeFirebaseFirestore();
    final progress = StudentProgressRepository(firestore: db);
    final diagnostic = DiagnosticService(progress: progress);
    final questions = groupBDiagnosticQuestions();
    final selected = List<int?>.generate(questions.length, (i) {
      if (questions[i].areaId == 'economy') {
        return (questions[i].correctIndex + 1) % questions[i].options.length;
      }
      return questions[i].correctIndex;
    });
    final scored = diagnostic.score(
      attemptId: 'diag_eco',
      targetExam: kTargetExamGroupBCombined,
      questions: questions,
      selected: selected,
      now: DateTime(2026, 9, 1, 10),
    );
    await diagnostic.persist('student_w', scored);

    final profiles = ProfileRepository(firestore: db);
    await profiles.saveProfile(
      StudentProfile(
        uid: 'student_w',
        name: 'Asha',
        email: 'a@x.com',
        mobile: '9999999999',
        targetExam: kTargetExamGroupBCombined,
        dailyStudyHours: 5,
        onboardingCompleted: true,
        diagnosticCompleted: true,
      ),
    );

    final syllabus = groupBFallbackSyllabus();
    final tracker = FirestoreAiWeaknessTracker(
      progress: progress,
      classroom: LessonProgressRepository(firestore: db),
      syllabus: _FixedSyllabus(syllabus),
      profiles: profiles,
    );

    final afterDiag = await tracker.load(
      'student_w',
      syllabus: syllabus,
      now: DateTime(2026, 9, 1, 11),
    );
    final economyTopics = afterDiag.signals
        .where((s) => s.subjectTitle == 'Economy' || s.chapterId.contains('economy'))
        .toList();
    expect(economyTopics, isNotEmpty);
    expect(
      afterDiag.signals.any((s) => s.subjectTitle == 'General Ability Test'),
      isFalse,
    );
    expect(economyTopics.first.isWeak, isTrue);

    final economyChapter = groupBChapterForArea('economy')!;
    await progress.saveTestAttempt(
      'student_w',
      TestResult(
        testTitle: 'Basics of Indian Economy MCQ',
        dateTime: DateTime(2026, 9, 2, 12),
        totalQuestions: 10,
        attempted: 10,
        correct: 3,
        wrong: 7,
        score: 3,
        maxScore: 10,
        percentage: 30,
        timeTakenSeconds: 60,
        questionResults: const [],
      ),
      kind: 'mcq',
      subjectId: economyChapter.subjectId,
      chapterId: economyChapter.id,
      areaId: 'economy',
    );

    final afterLow = await tracker.load(
      'student_w',
      syllabus: syllabus,
      now: DateTime(2026, 9, 2, 13),
    );
    final low = afterLow.signals.singleWhere(
      (s) => s.chapterId == economyChapter.id,
    );
    expect(low.scorePercent, 30);
    expect(low.isWeak, isTrue);
    expect(low.priority, greaterThan(0));

    final lowPlan = DailyPlannerService().buildPlan(
      uid: 'student_w',
      prefs: const PlannerPrefs(
        targetExam: kTargetExamGroupBCombined,
        examDate: '',
        dailyHours: 5,
        preparationDurationDays: 90,
      ),
      dateKey: '2026-09-02',
      syllabus: syllabus,
      weakness: afterLow,
      now: DateTime(2026, 9, 2, 13),
    );
    expect(lowPlan.adaptationNotes.join(' '), contains('Weak: Economy'));

    await progress.saveTestAttempt(
      'student_w',
      TestResult(
        testTitle: 'Basics of Indian Economy MCQ 2',
        dateTime: DateTime(2026, 9, 3, 12),
        totalQuestions: 10,
        attempted: 10,
        correct: 9,
        wrong: 1,
        score: 9,
        maxScore: 10,
        percentage: 90,
        timeTakenSeconds: 50,
        questionResults: const [],
      ),
      kind: 'mcq',
      subjectId: economyChapter.subjectId,
      chapterId: economyChapter.id,
      areaId: 'economy',
    );

    final afterHigh = await tracker.load(
      'student_w',
      syllabus: syllabus,
      now: DateTime(2026, 9, 3, 13),
    );
    final high = afterHigh.signals.singleWhere(
      (s) => s.chapterId == economyChapter.id,
    );
    expect(high.scorePercent, 90);
    expect(high.isStrong, isTrue);
    expect(high.isWeak, isFalse);

    final highPlan = DailyPlannerService().buildPlan(
      uid: 'student_w',
      prefs: const PlannerPrefs(
        targetExam: kTargetExamGroupBCombined,
        examDate: '',
        dailyHours: 5,
        preparationDurationDays: 90,
      ),
      dateKey: '2026-09-03',
      syllabus: syllabus,
      weakness: afterHigh,
      now: DateTime(2026, 9, 3, 13),
    );
    expect(highPlan.adaptationNotes.join(' '), isNot(contains('Weak: Economy')));
    expect(
      highPlan.tasks.any(
        (t) =>
            t.subject == 'History' ||
            t.subject == 'Marathi' ||
            t.subject == 'Current Affairs' ||
            t.subject == 'Geography' ||
            t.subject == 'Polity',
      ),
      isTrue,
    );
  });
}
