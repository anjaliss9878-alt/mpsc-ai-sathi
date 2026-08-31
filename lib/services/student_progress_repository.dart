import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/bookmark_item.dart';
import 'package:mpsc_combine_ai/models/continue_session.dart';
import 'package:mpsc_combine_ai/models/daily_study_plan.dart';
import 'package:mpsc_combine_ai/models/study_goal.dart';
import 'package:mpsc_combine_ai/models/study_plan.dart';
import 'package:mpsc_combine_ai/models/syllabus_topic_record.dart';
import 'package:mpsc_combine_ai/models/test_result.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Shared Firebase helpers for student goals, bookmarks, resume sessions,
/// certificates, and persisted test attempts.
///
/// Paths (all under `students/{uid}/…`):
/// - `dailyGoals/{yyyy-MM-dd}`
/// - `bookmarks/{id}`
/// - `continueLearning/{id}`
/// - `testAttempts/{id}`
/// - `certificates/{id}`
/// - `studyPlans/{yyyy-Www}` weekly AI timetable
/// - `studyPlans/{yyyy-MM-dd}` personalized daily plans (`kind: daily`)
/// - `syllabusProgress/{chapterId}` explicit topic status + history
/// - `videoProgress/{videoId}`
class StudentProgressRepository {
  StudentProgressRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _col(String uid, String name) =>
      _db.collection('students').doc(uid).collection(name);

  // ── Study goals (midnight daily reset by dateKey) ─────────────────────

  Stream<StudyGoal> watchTodayGoal(String uid) {
    final key = StudyGoal.todayKey();
    return _col(uid, 'dailyGoals').doc(key).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return StudyGoal.emptyForToday();
      }
      return StudyGoal.fromMap(snap.data()!, key);
    });
  }

  Future<StudyGoal> getTodayGoal(String uid) async {
    final key = StudyGoal.todayKey();
    final snap = await _col(uid, 'dailyGoals').doc(key).get();
    if (!snap.exists || snap.data() == null) {
      final empty = StudyGoal.emptyForToday();
      await _col(uid, 'dailyGoals')
          .doc(key)
          .set(empty.toMap(), SetOptions(merge: true));
      return empty;
    }
    return StudyGoal.fromMap(snap.data()!, key);
  }

  Future<void> saveTodayGoal(String uid, StudyGoal goal) async {
    final key = StudyGoal.todayKey();
    await _col(uid, 'dailyGoals').doc(key).set(
          goal.copyWith(updatedAt: DateTime.now()).toMap(),
          SetOptions(merge: true),
        );
  }

  Future<void> markGoalTask({
    required String uid,
    required String task,
    bool done = true,
    String? sessionType,
    String? sessionTitle,
  }) async {
    final current = await getTodayGoal(uid);
    var next = switch (task) {
      'notes' => current.copyWith(notesDone: done),
      'mcqs' => current.copyWith(mcqsDone: done),
      'revision' => current.copyWith(revisionDone: done),
      'test' => current.copyWith(testDone: done),
      _ => current,
    };
    if (sessionType != null || sessionTitle != null) {
      next = next.copyWith(
        lastSessionType: sessionType ?? next.lastSessionType,
        lastSessionTitle: sessionTitle ?? next.lastSessionTitle,
      );
    }
    await saveTodayGoal(uid, next.copyWith(updatedAt: DateTime.now()));
  }

  /// Consecutive calendar days (ending today or yesterday) with ≥1 goal task done.
  Future<int> computeStudyStreak(String uid) async {
    final snap = await _col(uid, 'dailyGoals').get();
    final byKey = <String, StudyGoal>{};
    for (final d in snap.docs) {
      byKey[d.id] = StudyGoal.fromMap(d.data(), d.id);
    }
    var streak = 0;
    var cursor = DateTime.now();
    final today = StudyGoal.todayKey(cursor);
    final todayGoal = byKey[today];
    if (todayGoal == null || todayGoal.completedCount == 0) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    for (var i = 0; i < 365; i++) {
      final key = StudyGoal.todayKey(cursor);
      final goal = byKey[key];
      if (goal == null || goal.completedCount == 0) break;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Stream<int> watchStudyStreak(String uid) {
    return _col(uid, 'dailyGoals')
        .snapshots()
        .asyncMap((_) => computeStudyStreak(uid));
  }

  // ── Continue learning ─────────────────────────────────────────────────

  Stream<List<ContinueSession>> watchContinueSessions(String uid) {
    return _col(uid, 'continueLearning').snapshots().map((snap) {
      final list = snap.docs
          .map((d) => ContinueSession.fromMap(d.data(), d.id))
          .toList()
        ..sort((a, b) {
          final aAt = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bAt = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bAt.compareTo(aAt);
        });
      return list;
    });
  }

  Future<void> upsertContinueSession({
    required String uid,
    required String id,
    required String type,
    required String title,
    required String subtitle,
    required double progress,
    Map<String, dynamic> payload = const {},
  }) async {
    final session = ContinueSession(
      id: id,
      type: type,
      title: title,
      subtitle: subtitle,
      progress: progress.clamp(0.0, 1.0),
      payload: payload,
      updatedAt: DateTime.now(),
    );
    await _col(uid, 'continueLearning')
        .doc(id)
        .set(session.toMap(), SetOptions(merge: true));
  }

  // ── Bookmarks ─────────────────────────────────────────────────────────

  Stream<List<BookmarkItem>> watchBookmarks(String uid) {
    return _col(uid, 'bookmarks').snapshots().map((snap) {
      final list = snap.docs
          .map((d) => BookmarkItem.fromMap(d.data(), d.id))
          .toList()
        ..sort((a, b) {
          final aAt = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bAt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bAt.compareTo(aAt);
        });
      return list;
    });
  }

  Future<bool> isBookmarked(String uid, String id) async {
    final snap = await _col(uid, 'bookmarks').doc(id).get();
    return snap.exists;
  }

  Stream<bool> watchIsBookmarked(String uid, String id) {
    return _col(uid, 'bookmarks').doc(id).snapshots().map((s) => s.exists);
  }

  Future<void> toggleBookmark({
    required String uid,
    required String id,
    required String type,
    required String title,
    required String subtitle,
    required String refId,
    Map<String, dynamic> meta = const {},
  }) async {
    final ref = _col(uid, 'bookmarks').doc(id);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      return;
    }
    await ref.set(
      BookmarkItem(
        id: id,
        type: type,
        title: title,
        subtitle: subtitle,
        refId: refId,
        meta: meta,
        createdAt: DateTime.now(),
      ).toMap(),
    );
  }

  // ── Test attempts ─────────────────────────────────────────────────────

  Stream<List<PersistedTestAttempt>> watchTestAttempts(String uid) {
    return _col(uid, 'testAttempts').snapshots().map((snap) {
      final list = snap.docs
          .map((d) => PersistedTestAttempt.fromMap(d.data(), d.id))
          .toList()
        ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
      return list;
    });
  }

  Future<List<PersistedTestAttempt>> getTestAttempts(String uid) async {
    final snap = await _col(uid, 'testAttempts').get();
    final list = snap.docs
        .map((d) => PersistedTestAttempt.fromMap(d.data(), d.id))
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return list;
  }

  Future<void> saveTestAttempt(
    String uid,
    TestResult result, {
    String? testId,
    String kind = 'test',
    String subjectId = '',
    String chapterId = '',
  }) async {
    final id = '${result.dateTime.millisecondsSinceEpoch}';
    await _col(uid, 'testAttempts').doc(id).set({
      'testId': testId ?? '',
      'testTitle': result.testTitle,
      'dateTime': result.dateTime.toIso8601String(),
      'totalQuestions': result.totalQuestions,
      'attempted': result.attempted,
      'correct': result.correct,
      'wrong': result.wrong,
      'score': result.score,
      'maxScore': result.maxScore,
      'percentage': result.percentage,
      'timeTakenSeconds': result.timeTakenSeconds,
      'kind': kind,
      'subjectId': subjectId,
      'chapterId': chapterId,
      'questionResults': result.questionResults
          .map(
            (q) => {
              'question': q.question,
              'options': q.options,
              'correctIndex': q.correctIndex,
              'selectedIndex': q.selectedIndex,
              'explanation': q.explanation,
            },
          )
          .toList(),
    });
  }

  // ── Certificates ──────────────────────────────────────────────────────

  Stream<List<CertificateItem>> watchCertificates(String uid) {
    return _col(uid, 'certificates').snapshots().map((snap) {
      final list = snap.docs
          .map((d) => CertificateItem.fromMap(d.data(), d.id))
          .toList()
        ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
      return list;
    });
  }

  Future<List<CertificateItem>> getCertificates(String uid) async {
    final snap = await _col(uid, 'certificates').get();
    final list = snap.docs
        .map((d) => CertificateItem.fromMap(d.data(), d.id))
        .toList()
      ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return list;
  }

  Future<void> ensureChapterCertificate({
    required String uid,
    required String chapterId,
    required String title,
    required String subtitle,
  }) async {
    final ref = _col(uid, 'certificates').doc('chapter_$chapterId');
    final snap = await ref.get();
    if (snap.exists) return;
    await ref.set({
      'title': title,
      'subtitle': subtitle,
      'type': 'chapter',
      'refId': chapterId,
      'issuedAt': DateTime.now().toIso8601String(),
    });
  }

  // ── Study plans ───────────────────────────────────────────────────────

  Stream<StudyPlan?> watchCurrentStudyPlan(String uid) {
    final key = StudyPlan.weekKeyFor();
    return _col(uid, 'studyPlans').doc(key).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return StudyPlan.fromMap(snap.data()!, key);
    });
  }

  Future<void> saveStudyPlan(String uid, StudyPlan plan) async {
    await _col(uid, 'studyPlans').doc(plan.weekKey).set(
          plan.toMap(),
          SetOptions(merge: true),
        );
  }

  // ── Personalized daily plans (same studyPlans collection, date-keyed) ─

  Stream<DailyStudyPlan?> watchDailyPlan(String uid, {String? dateKey}) {
    final key = dateKey ?? DailyStudyPlan.dateKeyFor();
    return _col(uid, 'studyPlans').doc(key).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      if (!DailyStudyPlan.isDailyDoc(snap.id, snap.data())) return null;
      return DailyStudyPlan.fromMap(snap.data()!, key);
    });
  }

  Future<DailyStudyPlan?> getDailyPlan(String uid, {String? dateKey}) async {
    final key = dateKey ?? DailyStudyPlan.dateKeyFor();
    final snap = await _col(uid, 'studyPlans').doc(key).get();
    if (!snap.exists || snap.data() == null) return null;
    if (!DailyStudyPlan.isDailyDoc(snap.id, snap.data())) return null;
    return DailyStudyPlan.fromMap(snap.data()!, key);
  }

  Future<void> saveDailyPlan(String uid, DailyStudyPlan plan) async {
    await _col(uid, 'studyPlans').doc(plan.dateKey).set(
          plan.copyWith(generatedAt: plan.generatedAt ?? DateTime.now()).toMap(),
          SetOptions(merge: true),
        );
  }

  Stream<List<DailyStudyPlan>> watchDailyPlans(String uid) {
    return _col(uid, 'studyPlans').snapshots().map((snap) {
      final list = <DailyStudyPlan>[];
      for (final d in snap.docs) {
        if (!DailyStudyPlan.isDailyDoc(d.id, d.data())) continue;
        list.add(DailyStudyPlan.fromMap(d.data(), d.id));
      }
      list.sort((a, b) => b.dateKey.compareTo(a.dateKey));
      return list;
    });
  }

  Future<List<DailyStudyPlan>> getRecentDailyPlans(
    String uid, {
    int limit = 14,
  }) async {
    final snap = await _col(uid, 'studyPlans').get();
    final list = <DailyStudyPlan>[];
    for (final d in snap.docs) {
      if (!DailyStudyPlan.isDailyDoc(d.id, d.data())) continue;
      list.add(DailyStudyPlan.fromMap(d.data(), d.id));
    }
    list.sort((a, b) => b.dateKey.compareTo(a.dateKey));
    if (list.length <= limit) return list;
    return list.take(limit).toList();
  }

  Future<WeeklyPlannerProgress> weeklyProgress(
    String uid, {
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now();
    final keys = <String>{
      for (var i = 0; i < 7; i++)
        DailyStudyPlan.dateKeyFor(clock.subtract(Duration(days: i))),
    };
    final plans = await getRecentDailyPlans(uid, limit: 21);
    var completed = 0;
    var total = 0;
    var days = 0;
    for (final plan in plans) {
      if (!keys.contains(plan.dateKey)) continue;
      days++;
      total += plan.actionableCount;
      completed += plan.completedCount;
    }
    return WeeklyPlannerProgress(
      completedTasks: completed,
      totalTasks: total,
      daysWithPlan: days,
    );
  }

  Future<DailyStudyPlan> setTaskStatus({
    required String uid,
    required String dateKey,
    required String taskId,
    required DailyPlanTaskStatus status,
    String rescheduledToDateKey = '',
  }) async {
    final plan = await getDailyPlan(uid, dateKey: dateKey);
    if (plan == null) {
      throw StateError('No daily plan for $dateKey');
    }
    DailyPlanTask? updated;
    for (final t in plan.tasks) {
      if (t.id == taskId) {
        updated = t.copyWith(
          status: status,
          rescheduledToDateKey: rescheduledToDateKey,
        );
        break;
      }
    }
    if (updated == null) {
      throw StateError('Task $taskId not found');
    }
    final next = plan.withTask(updated);
    await saveDailyPlan(uid, next);
    if (status == DailyPlanTaskStatus.completed) {
      await markGoalTask(
        uid: uid,
        task: updated.goalTaskKey,
        done: true,
        sessionType: 'planner',
        sessionTitle: '${updated.typeLabel}: ${updated.topic}',
      );
      await upsertContinueSession(
        uid: uid,
        id: 'planner',
        type: 'revision',
        title: 'Daily planner',
        subtitle: updated.topic,
        progress: next.progress,
        payload: {'dateKey': dateKey, 'taskId': taskId},
      );
      if (updated.chapterId.isNotEmpty) {
        await recordSyllabusStudyFromPlanner(uid: uid, task: updated);
      }
    }
    return next;
  }

  /// Copies [taskId] onto [targetDateKey] as pending and marks the original
  /// rescheduled. Creates the target day plan if needed.
  Future<void> rescheduleTask({
    required String uid,
    required String fromDateKey,
    required String taskId,
    required String targetDateKey,
  }) async {
    final from = await getDailyPlan(uid, dateKey: fromDateKey);
    if (from == null) throw StateError('No daily plan for $fromDateKey');
    DailyPlanTask? task;
    for (final t in from.tasks) {
      if (t.id == taskId) {
        task = t;
        break;
      }
    }
    if (task == null) throw StateError('Task $taskId not found');

    await setTaskStatus(
      uid: uid,
      dateKey: fromDateKey,
      taskId: taskId,
      status: DailyPlanTaskStatus.rescheduled,
      rescheduledToDateKey: targetDateKey,
    );

    var target = await getDailyPlan(uid, dateKey: targetDateKey);
    final moved = DailyPlanTask(
      id: '${targetDateKey}_${task.id}',
      type: task.type,
      subject: task.subject,
      topic: task.topic,
      durationMinutes: task.durationMinutes,
      subjectId: task.subjectId,
      chapterId: task.chapterId,
      studyMinutes: task.studyMinutes,
      revisionMinutes: task.revisionMinutes,
      practiceMinutes: task.practiceMinutes,
      reason: 'Rescheduled from $fromDateKey',
      priority: task.priority,
    );
    if (target == null) {
      target = DailyStudyPlan(
        dateKey: targetDateKey,
        uid: uid,
        targetExam: from.targetExam,
        examDate: from.examDate,
        dailyHours: from.dailyHours,
        tasks: [moved],
        adaptationNotes: const ['Rescheduled from a previous day.'],
        generatedAt: DateTime.now(),
      );
    } else {
      target = target.copyWith(tasks: [...target.tasks, moved]);
    }
    await saveDailyPlan(uid, target);
  }

  // ── Syllabus topic progress (`students/{uid}/syllabusProgress`) ────────

  static const String syllabusProgressCollection = 'syllabusProgress';

  CollectionReference<Map<String, dynamic>> _syllabusCol(String uid) =>
      _col(uid, syllabusProgressCollection);

  Stream<List<SyllabusTopicRecord>> watchSyllabusRecords(String uid) {
    return _syllabusCol(uid).snapshots().map((snap) {
      return snap.docs
          .map((d) => SyllabusTopicRecord.fromMap(d.data(), d.id))
          .toList();
    });
  }

  Future<List<SyllabusTopicRecord>> getSyllabusRecords(String uid) async {
    final snap = await _syllabusCol(uid).get();
    return snap.docs
        .map((d) => SyllabusTopicRecord.fromMap(d.data(), d.id))
        .toList();
  }

  Future<SyllabusTopicRecord?> getSyllabusRecord(
    String uid,
    String chapterId,
  ) async {
    if (chapterId.isEmpty) return null;
    final snap = await _syllabusCol(uid).doc(chapterId).get();
    if (!snap.exists || snap.data() == null) return null;
    return SyllabusTopicRecord.fromMap(snap.data()!, snap.id);
  }

  Future<void> upsertSyllabusRecord({
    required String uid,
    required String chapterId,
    required String subjectId,
    required SyllabusTopicStatus status,
    String source = 'manual',
    int extraStudyMinutes = 0,
    bool incrementRevision = false,
  }) async {
    if (chapterId.isEmpty) return;
    final existing = await getSyllabusRecord(uid, chapterId);
    final now = DateTime.now();
    final history = [
      ...(existing?.history ?? const <SyllabusStatusEvent>[]),
      SyllabusStatusEvent(status: status, at: now, source: source),
    ];
    final trimmed = history.length <= 30
        ? history
        : history.sublist(history.length - 30);
    final completedAt = status == SyllabusTopicStatus.completed
        ? (existing?.completedAt ?? now)
        : null;
    final next = SyllabusTopicRecord(
      chapterId: chapterId,
      subjectId: subjectId,
      status: status,
      studyMinutes: (existing?.studyMinutes ?? 0) + extraStudyMinutes,
      revisionCount: (existing?.revisionCount ?? 0) + (incrementRevision ? 1 : 0),
      completedAt: completedAt,
      lastStudiedAt: now,
      history: trimmed,
    );
    await _syllabusCol(uid).doc(chapterId).set(
          next.toMap(),
          SetOptions(merge: true),
        );
  }

  /// Planner study/revision completion updates syllabus without looping
  /// back into planner task completion.
  Future<void> recordSyllabusStudyFromPlanner({
    required String uid,
    required DailyPlanTask task,
  }) async {
    if (task.chapterId.isEmpty) return;
    final existing = await getSyllabusRecord(uid, task.chapterId);
    final alreadyDone = existing?.status == SyllabusTopicStatus.completed;
    final nextStatus = alreadyDone
        ? SyllabusTopicStatus.completed
        : SyllabusTopicStatus.inProgress;
    await upsertSyllabusRecord(
      uid: uid,
      chapterId: task.chapterId,
      subjectId: task.subjectId,
      status: nextStatus,
      source: 'planner',
      extraStudyMinutes: task.durationMinutes,
      incrementRevision: task.type == DailyPlanTaskType.revision,
    );
  }

  /// Marks today's open planner tasks for [chapterId] complete. Does not
  /// re-enter [setTaskStatus] (avoids a planner ↔ syllabus loop).
  Future<int> completeOpenPlannerTasksForChapter({
    required String uid,
    required String chapterId,
    String? dateKey,
  }) async {
    if (chapterId.isEmpty) return 0;
    final key = dateKey ?? DailyStudyPlan.dateKeyFor();
    final plan = await getDailyPlan(uid, dateKey: key);
    if (plan == null) return 0;
    var count = 0;
    var next = plan;
    for (final task in plan.tasks) {
      if (task.chapterId != chapterId || !task.isOpen) continue;
      next = next.withTask(
        task.copyWith(status: DailyPlanTaskStatus.completed),
      );
      count++;
    }
    if (count == 0) return 0;
    await saveDailyPlan(uid, next);
    await markGoalTask(
      uid: uid,
      task: 'notes',
      done: true,
      sessionType: 'syllabus',
      sessionTitle: 'Topic complete',
    );
    return count;
  }

  // ── Video progress ────────────────────────────────────────────────────

  Stream<List<VideoProgress>> watchVideoProgress(String uid) {
    return _col(uid, 'videoProgress').snapshots().map((snap) {
      final list = snap.docs
          .map((d) => VideoProgress.fromMap(d.data(), d.id))
          .toList()
        ..sort((a, b) {
          final aAt = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bAt = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bAt.compareTo(aAt);
        });
      return list;
    });
  }

  Stream<VideoProgress?> watchOneVideoProgress(String uid, String videoId) {
    return _col(uid, 'videoProgress').doc(videoId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return VideoProgress.fromMap(snap.data()!, videoId);
    });
  }

  Future<void> upsertVideoProgress({
    required String uid,
    required String videoId,
    required String title,
    required String subject,
    required double progress,
    bool? completed,
    double playbackSpeed = 1.0,
  }) async {
    final clamped = progress.clamp(0.0, 1.0);
    await _col(uid, 'videoProgress').doc(videoId).set(
      {
        'videoId': videoId,
        'title': title,
        'subject': subject,
        'progress': clamped,
        'completed': completed ?? clamped >= 0.95,
        'playbackSpeed': playbackSpeed,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      SetOptions(merge: true),
    );
    await upsertContinueSession(
      uid: uid,
      id: 'video_$videoId',
      type: 'video',
      title: title,
      subtitle: subject.isEmpty ? 'Lecture' : subject,
      progress: clamped,
      payload: {'videoId': videoId},
    );
  }
}

class PersistedTestAttempt {
  const PersistedTestAttempt({
    required this.id,
    required this.testTitle,
    required this.dateTime,
    required this.totalQuestions,
    required this.attempted,
    required this.correct,
    required this.wrong,
    required this.score,
    required this.maxScore,
    required this.percentage,
    required this.timeTakenSeconds,
    this.testId = '',
    this.kind = 'test',
    this.subjectId = '',
    this.chapterId = '',
    this.questionResults = const [],
  });

  final String id;
  final String testId;
  final String testTitle;
  final DateTime dateTime;
  final int totalQuestions;
  final int attempted;
  final int correct;
  final int wrong;
  final double score;
  final double maxScore;
  final double percentage;
  final int timeTakenSeconds;
  final String kind;
  final String subjectId;
  final String chapterId;
  final List<QuestionResult> questionResults;

  factory PersistedTestAttempt.fromMap(Map<String, dynamic> map, String id) {
    return PersistedTestAttempt(
      id: id,
      testId: map['testId'] as String? ?? '',
      testTitle: map['testTitle'] as String? ?? '',
      dateTime:
          DateTime.tryParse(map['dateTime'] as String? ?? '') ?? DateTime.now(),
      totalQuestions: (map['totalQuestions'] as num?)?.toInt() ?? 0,
      attempted: (map['attempted'] as num?)?.toInt() ?? 0,
      correct: (map['correct'] as num?)?.toInt() ?? 0,
      wrong: (map['wrong'] as num?)?.toInt() ?? 0,
      score: (map['score'] as num?)?.toDouble() ?? 0,
      maxScore: (map['maxScore'] as num?)?.toDouble() ?? 0,
      percentage: (map['percentage'] as num?)?.toDouble() ?? 0,
      timeTakenSeconds: (map['timeTakenSeconds'] as num?)?.toInt() ?? 0,
      kind: map['kind'] as String? ?? _kindFromTitle(map['testTitle'] as String?),
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      questionResults: asMapList(map['questionResults']).map((m) {
        return QuestionResult(
          question: m['question'] as String? ?? '',
          options: asStringList(m['options']),
          correctIndex: (m['correctIndex'] as num?)?.toInt() ?? 0,
          selectedIndex: (m['selectedIndex'] as num?)?.toInt(),
          explanation: m['explanation'] as String?,
        );
      }).toList(),
    );
  }

  TestResult toTestResult() => TestResult(
        testTitle: testTitle,
        dateTime: dateTime,
        totalQuestions: totalQuestions,
        attempted: attempted,
        correct: correct,
        wrong: wrong,
        score: score,
        maxScore: maxScore,
        percentage: percentage,
        timeTakenSeconds: timeTakenSeconds,
        questionResults: questionResults,
      );
}

String _kindFromTitle(String? title) {
  final hay = (title ?? '').toLowerCase();
  if (hay.contains('pyq') || hay.contains('previous year')) return 'pyq';
  if (hay.contains('mcq') || hay.contains('practice')) return 'mcq';
  return 'test';
}

class CertificateItem {
  const CertificateItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.refId,
    required this.issuedAt,
  });

  final String id;
  final String title;
  final String subtitle;
  final String type;
  final String refId;
  final DateTime issuedAt;

  factory CertificateItem.fromMap(Map<String, dynamic> map, String id) {
    return CertificateItem(
      id: id,
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      type: map['type'] as String? ?? '',
      refId: map['refId'] as String? ?? '',
      issuedAt:
          DateTime.tryParse(map['issuedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

final StudentProgressRepository studentProgressRepository =
    StudentProgressRepository();
