import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/bookmark_item.dart';
import 'package:mpsc_combine_ai/models/continue_session.dart';
import 'package:mpsc_combine_ai/models/study_goal.dart';
import 'package:mpsc_combine_ai/models/study_plan.dart';
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
/// - `studyPlans/{yyyy-Www}`
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
