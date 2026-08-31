import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/daily_study_plan.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_progress_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';

SubjectItem _subject(String id, String title, {int order = 0}) {
  return SubjectItem(
    id: id,
    title: title,
    subtitle: '',
    iconName: 'menu_book',
    order: order,
  );
}

ChapterItem _chapter(String id, String subjectId, String title, {int order = 0}) {
  return ChapterItem(
    id: id,
    subjectId: subjectId,
    title: title,
    order: order,
  );
}

SyllabusTopicProgress _topic({
  required String subjectId,
  required String subject,
  required String chapterId,
  required String chapter,
  SyllabusTopicStatus status = SyllabusTopicStatus.pending,
  int studyMinutes = 0,
  int revisionCount = 0,
}) {
  return SyllabusTopicProgress(
    subject: _subject(subjectId, subject),
    chapter: _chapter(chapterId, subjectId, chapter),
    status: status,
    studyMinutes: studyMinutes,
    revisionCount: revisionCount,
  );
}

Future<void> _seedSyllabus(FakeFirebaseFirestore db) async {
  await db.collection('subjects').doc('polity').set(
        _subject('polity', 'राज्यशास्त्र', order: 1).toMap(),
      );
  await db.collection('subjects').doc('geo').set(
        _subject('geo', 'भूगोल', order: 2).toMap(),
      );
  await db.collection('subjects').doc('hidden').set(
        _subject('hidden', 'Hidden', order: 9).copyWith(published: false).toMap(),
      );
  await db.collection('chapters').doc('rights').set(
        _chapter('rights', 'polity', 'मूलभूत हक्क', order: 1).toMap(),
      );
  await db.collection('chapters').doc('preamble').set(
        _chapter('preamble', 'polity', 'प्रस्तावना', order: 2).toMap(),
      );
  await db.collection('chapters').doc('earth').set(
        _chapter('earth', 'geo', 'पृथ्वी', order: 1).toMap(),
      );
}

FirestoreSyllabusProgressTracker _tracker(FakeFirebaseFirestore db) {
  return FirestoreSyllabusProgressTracker(
    notes: NotesRepository(firestore: db),
    classroom: LessonProgressRepository(firestore: db),
    progress: StudentProgressRepository(firestore: db),
  );
}

void main() {
  test('progress is completed / total × 100 at topic, chapter, subject, overall', () {
    expect(syllabusCompletionPercent(completed: 0, total: 0), 0);
    expect(syllabusCompletionPercent(completed: 1, total: 4), 25);
    expect(syllabusTopicPercent(SyllabusTopicStatus.completed), 100);
    expect(syllabusTopicPercent(SyllabusTopicStatus.inProgress), 0);
    expect(syllabusTopicPercent(SyllabusTopicStatus.pending), 0);

    final snap = SyllabusProgressSnapshot(
      topics: [
        _topic(
          subjectId: 'polity',
          subject: 'Polity',
          chapterId: 'rights',
          chapter: 'Rights',
          status: SyllabusTopicStatus.completed,
        ),
        _topic(
          subjectId: 'polity',
          subject: 'Polity',
          chapterId: 'preamble',
          chapter: 'Preamble',
          status: SyllabusTopicStatus.inProgress,
        ),
        _topic(
          subjectId: 'geo',
          subject: 'Geo',
          chapterId: 'earth',
          chapter: 'Earth',
          status: SyllabusTopicStatus.pending,
        ),
        _topic(
          subjectId: 'geo',
          subject: 'Geo',
          chapterId: 'monsoon',
          chapter: 'Monsoon',
          status: SyllabusTopicStatus.completed,
        ),
      ],
    );

    expect(snap.overallPercent, 50);
    expect(snap.completedTopics, 2);
    expect(snap.totalTopics, 4);
    expect(snap.incomplete.length, 2);

    final polity = snap.subjectById('polity')!;
    expect(polity.completedTopics, 1);
    expect(polity.totalTopics, 2);
    expect(polity.percent, 50);
    expect(polity.statusLabel, 'सुरू आहे');

    final geo = snap.subjectById('geo')!;
    expect(geo.percent, 50);

    final feed = snap.weaknessInputs;
    expect(feed.completedTopics.length, 2);
    expect(feed.incompleteTopics.length, 2);
  });

  test('topic status update writes history and student-owned path', () async {
    final db = FakeFirebaseFirestore();
    final repo = StudentProgressRepository(firestore: db);
    await repo.upsertSyllabusRecord(
      uid: 'u1',
      chapterId: 'rights',
      subjectId: 'polity',
      status: SyllabusTopicStatus.inProgress,
      source: 'manual',
      extraStudyMinutes: 20,
    );
    await repo.upsertSyllabusRecord(
      uid: 'u1',
      chapterId: 'rights',
      subjectId: 'polity',
      status: SyllabusTopicStatus.completed,
      source: 'manual',
    );
    final record = await repo.getSyllabusRecord('u1', 'rights');
    expect(record?.status, SyllabusTopicStatus.completed);
    expect(record?.studyMinutes, 20);
    expect(record?.completedAt, isNotNull);
    expect(record?.lastStudiedAt, isNotNull);
    expect(record?.history.length, 2);
    expect(record?.history.last.status, SyllabusTopicStatus.completed);

    final snap = await db
        .collection('students')
        .doc('u1')
        .collection('syllabusProgress')
        .doc('rights')
        .get();
    expect(snap.exists, isTrue);
    expect(snap.data()?['status'], 'completed');
  });

  test('student data is isolated by uid', () async {
    final db = FakeFirebaseFirestore();
    await _seedSyllabus(db);
    final repo = StudentProgressRepository(firestore: db);
    final tracker = _tracker(db);

    await repo.upsertSyllabusRecord(
      uid: 'student_a',
      chapterId: 'rights',
      subjectId: 'polity',
      status: SyllabusTopicStatus.completed,
    );
    await repo.upsertSyllabusRecord(
      uid: 'student_b',
      chapterId: 'earth',
      subjectId: 'geo',
      status: SyllabusTopicStatus.completed,
    );

    final a = await tracker.load('student_a');
    final b = await tracker.load('student_b');
    expect(
      a.topics.where((t) => t.isCompleted).map((t) => t.chapterId).toList(),
      ['rights'],
    );
    expect(
      b.topics.where((t) => t.isCompleted).map((t) => t.chapterId).toList(),
      ['earth'],
    );
    expect(a.overallPercent, closeTo(100 / 3, 0.01));
    expect(b.overallPercent, closeTo(100 / 3, 0.01));

    final aDocs = await repo.getSyllabusRecords('student_a');
    expect(aDocs.map((r) => r.chapterId).toList(), ['rights']);
    final bPath = await db
        .collection('students')
        .doc('student_a')
        .collection('syllabusProgress')
        .get();
    expect(bPath.docs.length, 1);
  });

  test('tracker load uses published syllabus and chapter/subject percents', () async {
    final db = FakeFirebaseFirestore();
    await _seedSyllabus(db);
    final tracker = _tracker(db);
    await tracker.setTopicStatus(
      uid: 'u1',
      topic: _topic(
        subjectId: 'polity',
        subject: 'राज्यशास्त्र',
        chapterId: 'rights',
        chapter: 'मूलभूत हक्क',
      ),
      status: SyllabusTopicStatus.completed,
    );

    final snap = await tracker.load('u1');
    expect(snap.topics.map((t) => t.chapterId).toSet(), {'rights', 'preamble', 'earth'});
    expect(snap.topics.any((t) => t.subjectId == 'hidden'), isFalse);
    expect(snap.completedTopics, 1);
    expect(snap.totalTopics, 3);
    expect(snap.overallPercent, closeTo(100 / 3, 0.01));

    final polity = snap.subjectById('polity')!;
    expect(polity.completedTopics, 1);
    expect(polity.totalTopics, 2);
    expect(polity.percent, 50);
    expect(polity.topics.where((t) => t.chapterId == 'rights').single.status,
        SyllabusTopicStatus.completed);
    expect(polity.topics.where((t) => t.chapterId == 'preamble').single.status,
        SyllabusTopicStatus.pending);

    final geo = snap.subjectById('geo')!;
    expect(geo.percent, 0);
    expect(geo.statusLabel, 'सुरू नाही');
  });

  test('completing a topic updates planner; incomplete stays pending', () async {
    final db = FakeFirebaseFirestore();
    await _seedSyllabus(db);
    final repo = StudentProgressRepository(firestore: db);
    final tracker = _tracker(db);

    await repo.saveDailyPlan(
      'u1',
      DailyStudyPlan(
        dateKey: '2026-08-21',
        uid: 'u1',
        targetExam: 'Combine',
        examDate: '2026-12-01',
        dailyHours: 4,
        generatedAt: DateTime(2026, 8, 21),
        tasks: const [
          DailyPlanTask(
            id: 't1',
            type: DailyPlanTaskType.study,
            subject: 'Polity',
            topic: 'Rights',
            durationMinutes: 40,
            subjectId: 'polity',
            chapterId: 'rights',
            studyMinutes: 40,
          ),
          DailyPlanTask(
            id: 't2',
            type: DailyPlanTaskType.study,
            subject: 'Geo',
            topic: 'Earth',
            durationMinutes: 30,
            subjectId: 'geo',
            chapterId: 'earth',
            studyMinutes: 30,
          ),
        ],
      ),
    );

    await tracker.setTopicStatus(
      uid: 'u1',
      topic: _topic(
        subjectId: 'polity',
        subject: 'राज्यशास्त्र',
        chapterId: 'rights',
        chapter: 'मूलभूत हक्क',
      ),
      status: SyllabusTopicStatus.completed,
      plannerDateKey: '2026-08-21',
    );

    final plan = await repo.getDailyPlan('u1', dateKey: '2026-08-21');
    expect(plan?.tasks.firstWhere((t) => t.id == 't1').status,
        DailyPlanTaskStatus.completed);
    expect(plan?.tasks.firstWhere((t) => t.id == 't2').status,
        DailyPlanTaskStatus.pending);

    final snap = await tracker.load('u1');
    expect(
      snap.topics.firstWhere((t) => t.chapterId == 'earth').status,
      SyllabusTopicStatus.pending,
    );
    expect(snap.pending.any((t) => t.chapterId == 'earth'), isTrue);
    expect(snap.completed.any((t) => t.chapterId == 'rights'), isTrue);
  });

  test('planner completion marks topic in progress without completing it', () async {
    final db = FakeFirebaseFirestore();
    await _seedSyllabus(db);
    final repo = StudentProgressRepository(firestore: db);
    await repo.saveDailyPlan(
      'u1',
      DailyStudyPlan(
        dateKey: '2026-08-21',
        uid: 'u1',
        targetExam: 'Combine',
        examDate: '2026-12-01',
        dailyHours: 4,
        generatedAt: DateTime(2026, 8, 21),
        tasks: const [
          DailyPlanTask(
            id: 't1',
            type: DailyPlanTaskType.study,
            subject: 'Polity',
            topic: 'Rights',
            durationMinutes: 40,
            subjectId: 'polity',
            chapterId: 'rights',
            studyMinutes: 40,
          ),
        ],
      ),
    );
    await repo.setTaskStatus(
      uid: 'u1',
      dateKey: '2026-08-21',
      taskId: 't1',
      status: DailyPlanTaskStatus.completed,
    );
    final record = await repo.getSyllabusRecord('u1', 'rights');
    expect(record?.status, SyllabusTopicStatus.inProgress);
    expect(record?.studyMinutes, 40);
    expect(record?.history.single.source, 'planner');
  });
}
