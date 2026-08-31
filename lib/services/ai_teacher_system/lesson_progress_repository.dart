import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';

/// Learning progress for the AI Classroom Video Lesson Engine.
///
/// Stored at `students/{uid}/classroomProgress/{chapterId}`.
class ClassroomProgress {
  const ClassroomProgress({
    required this.chapterId,
    required this.subjectId,
    required this.topicName,
    required this.scenesCompleted,
    required this.totalScenes,
    required this.quizScore,
    required this.quizTotal,
    required this.completed,
    required this.updatedAt,
    this.lastSceneIndex = 0,
    this.lastPositionFraction = 0,
  });

  final String chapterId;
  final String subjectId;
  final String topicName;
  final int scenesCompleted;
  final int totalScenes;
  final int quizScore;
  final int quizTotal;
  final bool completed;
  final DateTime updatedAt;
  final int lastSceneIndex;
  final double lastPositionFraction;

  double get fraction =>
      totalScenes == 0 ? 0 : (scenesCompleted / totalScenes).clamp(0.0, 1.0);

  Map<String, dynamic> toMap() => {
        'chapterId': chapterId,
        'subjectId': subjectId,
        'topicName': topicName,
        'scenesCompleted': scenesCompleted,
        'totalScenes': totalScenes,
        'quizScore': quizScore,
        'quizTotal': quizTotal,
        'completed': completed,
        'lastSceneIndex': lastSceneIndex,
        'lastPositionFraction': lastPositionFraction,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ClassroomProgress.fromMap(Map<String, dynamic> map) {
    return ClassroomProgress(
      chapterId: map['chapterId'] as String? ?? '',
      subjectId: map['subjectId'] as String? ?? '',
      topicName: map['topicName'] as String? ?? '',
      scenesCompleted: (map['scenesCompleted'] as num?)?.toInt() ?? 0,
      totalScenes: (map['totalScenes'] as num?)?.toInt() ?? 0,
      quizScore: (map['quizScore'] as num?)?.toInt() ?? 0,
      quizTotal: (map['quizTotal'] as num?)?.toInt() ?? 0,
      completed: map['completed'] as bool? ?? false,
      lastSceneIndex: (map['lastSceneIndex'] as num?)?.toInt() ?? 0,
      lastPositionFraction:
          (map['lastPositionFraction'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class LessonProgressRepository {
  LessonProgressRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid, String chapterId) =>
      _db.collection('students').doc(uid).collection('classroomProgress').doc(chapterId);

  Future<void> saveProgress({
    required String uid,
    required GeneratedLesson lesson,
    required int sceneIndex,
    int quizScore = 0,
    int quizTotal = 0,
    bool completed = false,
  }) async {
    final chapterId = lesson.chapterId.isNotEmpty
        ? lesson.chapterId
        : (lesson.id.isNotEmpty ? lesson.id : 'adhoc_${lesson.topicName.hashCode}');
    final total = lesson.slides.isNotEmpty ? lesson.slides.length : lesson.script.length;
    final progress = ClassroomProgress(
      chapterId: chapterId,
      subjectId: lesson.subjectId,
      topicName: lesson.topicName,
      scenesCompleted: (sceneIndex + 1).clamp(0, total),
      totalScenes: total,
      quizScore: quizScore,
      quizTotal: quizTotal,
      completed: completed,
      lastSceneIndex: sceneIndex,
      lastPositionFraction: 0,
      updatedAt: DateTime.now(),
    );
    await _doc(uid, chapterId).set(progress.toMap(), SetOptions(merge: true));
  }

  Future<void> savePosition({
    required String uid,
    required String chapterId,
    required double fraction,
    bool completed = false,
  }) async {
    await _doc(uid, chapterId).set({
      'lastPositionFraction': fraction.clamp(0.0, 1.0),
      'completed': completed,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<ClassroomProgress?> getProgress(String uid, String chapterId) async {
    final snap = await _doc(uid, chapterId).get();
    if (!snap.exists || snap.data() == null) return null;
    return ClassroomProgress.fromMap(snap.data()!);
  }

  Stream<List<ClassroomProgress>> watchAll(String uid, {int limit = 40}) {
    return _db
        .collection('students')
        .doc(uid)
        .collection('classroomProgress')
        .limit(limit)
        .snapshots()
        .map((snap) {
      return snap.docs.map((d) => ClassroomProgress.fromMap(d.data())).toList();
    });
  }

  /// Full classroom history for syllabus / planner (not the UI preview limit).
  Future<List<ClassroomProgress>> getAllOnce(String uid) async {
    final snap = await _db
        .collection('students')
        .doc(uid)
        .collection('classroomProgress')
        .get();
    return snap.docs.map((d) => ClassroomProgress.fromMap(d.data())).toList();
  }

  Stream<ClassroomProgress?> watchProgress(String uid, String chapterId) {
    return _doc(uid, chapterId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return ClassroomProgress.fromMap(snap.data()!);
    });
  }
}

final LessonProgressRepository lessonProgressRepository = LessonProgressRepository();
