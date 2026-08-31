import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/daily_study_plan.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/models/study_plan.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/ai_weakness_tracker.dart';
import 'package:mpsc_combine_ai/services/daily_planner_service.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';

class _FixedSyllabus extends SyllabusProgressTracker {
  _FixedSyllabus(this.snapshot);
  final SyllabusProgressSnapshot snapshot;
  @override
  Future<SyllabusProgressSnapshot> load(String uid) async => snapshot;
}

class _FixedWeakness extends AiWeaknessTracker {
  _FixedWeakness(this.snapshot);
  final WeaknessSnapshot snapshot;
  @override
  Future<WeaknessSnapshot> load(
    String uid, {
    SyllabusProgressSnapshot? syllabus,
    DateTime? now,
  }) async =>
      snapshot;
}

SyllabusTopicProgress _topic({
  required String subjectId,
  required String subject,
  required String chapterId,
  required String chapter,
  SyllabusTopicStatus status = SyllabusTopicStatus.pending,
  int order = 0,
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
      order: order,
    ),
    status: status,
  );
}

void main() {
  final now = DateTime(2026, 8, 21);

  test('daily plan round-trips and is distinct from weekly weekKey', () {
    final plan = DailyStudyPlan(
      dateKey: '2026-08-21',
      uid: 'u1',
      targetExam: 'PSI / STI / ASO',
      examDate: '2026-12-01',
      dailyHours: 4,
      tasks: const [
        DailyPlanTask(
          id: 't1',
          type: DailyPlanTaskType.study,
          subject: 'Polity',
          topic: 'Fundamental Rights',
          durationMinutes: 45,
          studyMinutes: 45,
        ),
      ],
      generatedAt: now,
    );
    final mapped = DailyStudyPlan.fromMap(plan.toMap(), '2026-08-21');
    expect(mapped.tasks.single.topic, 'Fundamental Rights');
    expect(mapped.totalStudyMinutes, 45);
    expect(DailyStudyPlan.isDailyDoc('2026-08-21', plan.toMap()), isTrue);
    expect(DailyStudyPlan.isDailyDoc(StudyPlan.weekKeyFor(now)), isFalse);
  });

  test('student profile planner prefs round-trip without dropping admin fields', () {
    final profile = StudentProfile(
      uid: 'u1',
      name: 'Asha',
      email: 'a@x.com',
      mobile: '999',
      targetExam: 'PSI / STI / ASO',
      examDate: '2026-12-01',
      dailyStudyHours: 5.5,
      isBlocked: false,
      assignedSubjectIds: const ['s1'],
    );
    final copy = StudentProfile.fromMap(profile.toMap(), 'u1');
    expect(copy.examDate, '2026-12-01');
    expect(copy.dailyStudyHours, 5.5);
    expect(copy.assignedSubjectIds, ['s1']);
  });

  test('pending syllabus is chosen for study; weak topic gets extra practice', () {
    final syllabus = SyllabusProgressSnapshot(
      topics: [
        _topic(
          subjectId: 'pol',
          subject: 'Polity',
          chapterId: 'fr',
          chapter: 'Fundamental Rights',
        ),
        _topic(
          subjectId: 'his',
          subject: 'History',
          chapterId: 'mod',
          chapter: 'Modern Maharashtra',
          status: SyllabusTopicStatus.completed,
          order: 1,
        ),
      ],
    );
    final weak = WeaknessSnapshot(
      signals: const [
        WeakTopicSignal(
          label: 'Polity mock',
          scorePercent: 38,
          source: 'test',
          subjectId: 'pol',
          chapterId: 'fr',
          subjectTitle: 'Polity',
        ),
      ],
      averageTestPercent: 38,
      attemptsThisWeek: 1,
    );
    final plan = DailyPlannerService().buildPlan(
      uid: 'u1',
      prefs: const PlannerPrefs(
        targetExam: 'Combine',
        examDate: '2026-09-01',
        dailyHours: 4,
      ),
      dateKey: '2026-08-21',
      syllabus: syllabus,
      weakness: weak,
      now: now,
    );
    expect(plan.tasks, isNotEmpty);
    expect(
      plan.tasks.any((t) => t.type == DailyPlanTaskType.study && t.chapterId == 'fr'),
      isTrue,
    );
    expect(plan.tasks.any((t) => t.type == DailyPlanTaskType.practiceMcq), isTrue);
    expect(plan.tasks.any((t) => t.type == DailyPlanTaskType.pyq), isTrue);
    expect(plan.tasks.any((t) => t.type == DailyPlanTaskType.testQuiz), isTrue);
    expect(plan.adaptationNotes.join(' '), contains('Weak'));
  });

  test('strong topics reduce revision emphasis versus weak-only plan', () {
    final syllabus = SyllabusProgressSnapshot(
      topics: [
        _topic(
          subjectId: 'geo',
          subject: 'Geography',
          chapterId: 'soil',
          chapter: 'Maharashtra soils',
        ),
      ],
    );
    DailyStudyPlan make(WeaknessSnapshot w) => DailyPlannerService().buildPlan(
          uid: 'u1',
          prefs: const PlannerPrefs(
            targetExam: 'Combine',
            examDate: '',
            dailyHours: 4,
          ),
          dateKey: '2026-08-21',
          syllabus: syllabus,
          weakness: w,
          now: now,
        );

    final weakPlan = make(
      const WeaknessSnapshot(
        signals: [
          WeakTopicSignal(
            label: 'Soils test',
            scorePercent: 30,
            source: 'test',
            chapterId: 'soil',
            subjectId: 'geo',
            subjectTitle: 'Geography',
          ),
        ],
        averageTestPercent: 30,
      ),
    );
    final strongPlan = make(
      const WeaknessSnapshot(
        signals: [
          WeakTopicSignal(
            label: 'Soils test',
            scorePercent: 92,
            source: 'test',
            chapterId: 'soil',
            subjectId: 'geo',
            subjectTitle: 'Geography',
          ),
        ],
        averageTestPercent: 92,
        attemptsThisWeek: 2,
      ),
    );
    expect(weakPlan.totalPracticeMinutes, greaterThan(strongPlan.totalPracticeMinutes));
  });

  test('Firestore daily plan stays under the owning student uid', () async {
    final db = FakeFirebaseFirestore();
    final repo = StudentProgressRepository(firestore: db);
    final plan = DailyStudyPlan(
      dateKey: '2026-08-21',
      uid: 'student_a',
      targetExam: 'Combine',
      dailyHours: 3,
      tasks: const [
        DailyPlanTask(
          id: 't1',
          type: DailyPlanTaskType.revision,
          subject: 'Polity',
          topic: 'DPSP',
          durationMinutes: 20,
          revisionMinutes: 20,
        ),
      ],
      generatedAt: now,
    );
    await repo.saveDailyPlan('student_a', plan);
    final weekKey = StudyPlan.weekKeyFor(now);
    await repo.saveStudyPlan(
      'student_a',
      StudyPlan(
        weekKey: weekKey,
        title: 'Weekly',
        summary: 'keep weekly',
        dailySlots: const [],
        weeklyGoals: const [],
        revisionReminders: const [],
        generatedAt: now,
      ),
    );

    final aSnap = await db
        .collection('students')
        .doc('student_a')
        .collection('studyPlans')
        .doc('2026-08-21')
        .get();
    expect(aSnap.exists, isTrue);
    expect(aSnap.data()!['uid'], 'student_a');
    expect(aSnap.data()!['kind'], 'daily');

    final bSnap = await db
        .collection('students')
        .doc('student_b')
        .collection('studyPlans')
        .doc('2026-08-21')
        .get();
    expect(bSnap.exists, isFalse);

    final weeklySnap = await db
        .collection('students')
        .doc('student_a')
        .collection('studyPlans')
        .doc(weekKey)
        .get();
    expect(weeklySnap.data()?['title'], 'Weekly');
    expect(DailyStudyPlan.isDailyDoc(weekKey, weeklySnap.data()), isFalse);

    final loaded = await repo.getDailyPlan('student_a', dateKey: '2026-08-21');
    expect(loaded?.tasks.single.topic, 'DPSP');

    await repo.setTaskStatus(
      uid: 'student_a',
      dateKey: '2026-08-21',
      taskId: 't1',
      status: DailyPlanTaskStatus.completed,
    );
    await repo.rescheduleTask(
      uid: 'student_a',
      fromDateKey: '2026-08-21',
      taskId: 't1',
      targetDateKey: '2026-08-22',
    );
    final moved = await repo.getDailyPlan('student_a', dateKey: '2026-08-22');
    expect(moved?.tasks, isNotEmpty);
    expect(moved?.tasks.first.topic, 'DPSP');

    final others = await db.collection('students').doc('student_b').get();
    expect(others.exists, isFalse);
  });

  test('generate uses injected syllabus/weakness trackers', () async {
    final db = FakeFirebaseFirestore();
    final repo = StudentProgressRepository(firestore: db);
    final service = DailyPlannerService(
      syllabus: _FixedSyllabus(
        SyllabusProgressSnapshot(
          topics: [
            _topic(
              subjectId: 'eco',
              subject: 'Economy',
              chapterId: 'budget',
              chapter: 'Union Budget',
            ),
          ],
        ),
      ),
      weakness: _FixedWeakness(const WeaknessSnapshot(signals: [])),
      progress: repo,
      profiles: ProfileRepository(firestore: db),
    );
    final plan = await service.generate(
      uid: 'u1',
      prefs: const PlannerPrefs(
        targetExam: 'Combine',
        examDate: '2027-01-01',
        dailyHours: 2,
      ),
      now: now,
    );
    expect(plan.tasks.any((t) => t.topic == 'Union Budget'), isTrue);
  });

  test('no syllabus and no performance does not invent tasks', () {
    final plan = DailyPlannerService().buildPlan(
      uid: 'u1',
      prefs: const PlannerPrefs(
        targetExam: 'Combine',
        examDate: '',
        dailyHours: 4,
      ),
      dateKey: '2026-08-21',
      syllabus: const SyllabusProgressSnapshot(topics: []),
      weakness: const WeaknessSnapshot(signals: []),
      now: now,
    );
    expect(plan.tasks, isEmpty);
    expect(plan.adaptationNotes.join(' '), contains('Not enough student data'));
  });

  test('weak topic is prioritized for revision, targeted MCQs, and PYQs', () {
    final syllabus = SyllabusProgressSnapshot(
      topics: [
        _topic(
          subjectId: 'pol',
          subject: 'Indian Polity',
          chapterId: 'fr',
          chapter: 'Fundamental Rights',
          status: SyllabusTopicStatus.completed,
        ),
        _topic(
          subjectId: 'geo',
          subject: 'Geography',
          chapterId: 'monsoon',
          chapter: 'Monsoon',
          order: 1,
        ),
      ],
    );
    final plan = DailyPlannerService().buildPlan(
      uid: 'u1',
      prefs: const PlannerPrefs(
        targetExam: 'Combine',
        examDate: '2026-12-01',
        dailyHours: 4,
      ),
      dateKey: '2026-08-21',
      syllabus: syllabus,
      weakness: const WeaknessSnapshot(
        signals: [
          WeakTopicSignal(
            label: 'Fundamental Rights',
            scorePercent: 32,
            source: 'test',
            subjectId: 'pol',
            chapterId: 'fr',
            subjectTitle: 'Indian Polity',
            priority: 40,
          ),
        ],
        averageTestPercent: 32,
        attemptsThisWeek: 1,
      ),
      now: now,
    );
    expect(
      plan.tasks.any(
        (t) =>
            t.type == DailyPlanTaskType.revision &&
            t.chapterId == 'fr' &&
            t.priority >= 40,
      ),
      isTrue,
    );
    expect(
      plan.tasks.any(
        (t) => t.type == DailyPlanTaskType.practiceMcq && t.chapterId == 'fr',
      ),
      isTrue,
    );
    expect(
      plan.tasks.any(
        (t) => t.type == DailyPlanTaskType.pyq && t.chapterId == 'fr',
      ),
      isTrue,
    );
    final improved = DailyPlannerService().buildPlan(
      uid: 'u1',
      prefs: const PlannerPrefs(
        targetExam: 'Combine',
        examDate: '2026-12-01',
        dailyHours: 4,
      ),
      dateKey: '2026-08-21',
      syllabus: syllabus,
      weakness: const WeaknessSnapshot(
        signals: [
          WeakTopicSignal(
            label: 'Fundamental Rights',
            scorePercent: 88,
            source: 'test',
            subjectId: 'pol',
            chapterId: 'fr',
            subjectTitle: 'Indian Polity',
            priority: 0,
          ),
        ],
        averageTestPercent: 88,
        attemptsThisWeek: 2,
      ),
      now: now,
    );
    expect(plan.totalPracticeMinutes, greaterThan(improved.totalPracticeMinutes));
    expect(
      improved.adaptationNotes.join(' '),
      isNot(contains('Weak: Indian Polity')),
    );
  });
}
