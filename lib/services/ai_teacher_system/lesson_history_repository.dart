import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';

/// Reads/writes AI Teacher Classroom lesson history in Firestore:
///
/// - `students/{uid}/aiLessons/{lessonId}` — one document per generated
///   lesson (question, script, slides, summary, MCQs, notes, timestamp).
///
/// Final architecture step: "Save lesson history in Firebase". Every method
/// is designed to be called defensively from the UI (wrap in try/catch) — a
/// Firestore hiccup here must never block lesson playback itself.
class LessonHistoryRepository {
  LessonHistoryRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String studentsCollection = 'students';
  static const String lessonsSubcollection = 'aiLessons';

  CollectionReference<Map<String, dynamic>> _lessonsRef(String uid) {
    return _firestore
        .collection(studentsCollection)
        .doc(uid)
        .collection(lessonsSubcollection);
  }

  /// Live list of the student's past AI Teacher lessons, most recent first.
  Stream<List<GeneratedLesson>> watchHistory(String uid) {
    return _lessonsRef(uid).orderBy('createdAt', descending: true).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => GeneratedLesson.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<String> save(String uid, GeneratedLesson lesson) async {
    final doc = await _lessonsRef(uid).add(lesson.toMap());
    return doc.id;
  }

  Future<GeneratedLesson?> getById(String uid, String lessonId) async {
    final doc = await _lessonsRef(uid).doc(lessonId).get();
    if (!doc.exists || doc.data() == null) return null;
    return GeneratedLesson.fromMap(doc.data()!, doc.id);
  }

  Future<void> delete(String uid, String lessonId) async {
    await _lessonsRef(uid).doc(lessonId).delete();
  }
}

/// Shared instance used by the AI Teacher Classroom screen.
final LessonHistoryRepository lessonHistoryRepository = LessonHistoryRepository();
