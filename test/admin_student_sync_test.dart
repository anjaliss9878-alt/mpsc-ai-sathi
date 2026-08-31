import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/daily_study_plan.dart';
import 'package:mpsc_combine_ai/models/job_alert.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/models/test_result.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_progress_repository.dart';
import 'package:mpsc_combine_ai/services/ai_weakness_tracker.dart';
import 'package:mpsc_combine_ai/services/daily_planner_service.dart';
import 'package:mpsc_combine_ai/services/job_alerts_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';

void main() {
  final now = DateTime(2026, 8, 26, 12);

  test('admin analytics reads the same planner, attempts, and weakness as the student',
      () async {
    final db = FakeFirebaseFirestore();
    await db.collection('subjects').doc('pol').set(
          SubjectItem(
            id: 'pol',
            title: 'Indian Polity',
            subtitle: '',
            iconName: 'menu_book',
            order: 1,
          ).toMap(),
        );
    await db.collection('chapters').doc('fr').set(
          ChapterItem(
            id: 'fr',
            subjectId: 'pol',
            title: 'Fundamental Rights',
            order: 1,
          ).toMap(),
        );

    final progress = StudentProgressRepository(firestore: db);
    final notes = NotesRepository(firestore: db);
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
    final planner = DailyPlannerService(
      syllabus: syllabus,
      weakness: weakness,
      progress: progress,
      profiles: ProfileRepository(firestore: db),
    );

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
        timeTakenSeconds: 90,
        questionResults: const [],
      ),
      kind: 'test',
      subjectId: 'pol',
      chapterId: 'fr',
    );

    final snap = await weakness.load('student_a', now: now);
    expect(snap.hasPerformance, isTrue);
    expect(snap.signals.single.chapterId, 'fr');
    expect(snap.signals.single.scorePercent, 30);

    final plan = await planner.generate(
      uid: 'student_a',
      prefs: const PlannerPrefs(
        targetExam: 'Combine Group B',
        examDate: '2026-12-01',
        dailyHours: 4,
      ),
      now: now,
    );
    await progress.saveDailyPlan('student_a', plan);
    expect(
      plan.tasks.any(
        (t) => t.chapterId == 'fr' && t.type == DailyPlanTaskType.revision,
      ),
      isTrue,
    );

    await progress.setTaskStatus(
      uid: 'student_a',
      dateKey: plan.dateKey,
      taskId: plan.tasks.first.id,
      status: DailyPlanTaskStatus.completed,
    );

    final adminView = await progress.getDailyPlan(
      'student_a',
      dateKey: plan.dateKey,
    );
    expect(adminView?.completedCount, 1);
    expect(adminView?.uid, 'student_a');

    final otherPlans = await progress.getRecentDailyPlans('student_b');
    expect(otherPlans, isEmpty);
    final otherWeak = await weakness.load('student_b', now: now);
    expect(otherWeak.hasPerformance, isFalse);
  });

  test('published job alerts are the only student-visible copy of admin alerts',
      () async {
    final db = FakeFirebaseFirestore();
    final repo = JobAlertsRepository(firestore: db);
    await repo.add(
      const JobAlert(
        id: '',
        examName: 'Visible PSI',
        organization: 'MPSC',
        post: 'PSI',
        eligibility: 'Graduate',
        description: 'Open',
        applicationUrl: 'https://mpsc.gov.in',
        published: true,
        lastDate: '2026-09-30',
      ),
    );
    await repo.add(
      const JobAlert(
        id: '',
        examName: 'Hidden draft',
        organization: 'MPSC',
        post: 'STI',
        eligibility: 'Graduate',
        description: 'Draft',
        applicationUrl: '',
        published: false,
      ),
    );
    final studentFeed = await repo.getPublished();
    expect(studentFeed.map((e) => e.examName), ['Visible PSI']);
    final adminFeed = await repo.watchAll().first;
    expect(adminFeed.length, 2);

    final id = studentFeed.single.id;
    await repo.update(
      studentFeed.single.copyWith(lastDate: '2026-08-20', description: 'Closed'),
    );
    final updated = await repo.getPublished();
    expect(updated.single.id, id);
    expect(updated.single.lastDate, '2026-08-20');
    expect(updated.single.lifecycle(now), JobAlertLifecycle.closed);
  });
}
