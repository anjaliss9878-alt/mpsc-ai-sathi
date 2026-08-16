import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/ai_teacher_content_item.dart';

/// Reads/writes admin-authored AI Teacher lessons in Firestore at
/// `aiTeacherContent/{id}`.
class AiTeacherContentRepository {
  AiTeacherContentRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'aiTeacherContent';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<AiTeacherContentItem>> watchAll() {
    return _ref.snapshots().map(
          (snap) => snap.docs
              .map((d) => AiTeacherContentItem.fromMap(d.data(), d.id))
              .toList(),
        );
  }

  Future<String> add(AiTeacherContentItem item) async {
    final doc = await _ref.add(item.toMap());
    return doc.id;
  }

  Future<void> update(AiTeacherContentItem item) async {
    await _ref.doc(item.id).set(item.toMap(), SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await _ref.doc(id).delete();
  }

  /// Finds the first authored lesson whose [AiTeacherContentItem.keywords]
  /// contains a case-insensitive match somewhere in [question]. Returns
  /// `null` if none match — the AI Teacher Classroom then falls back to
  /// live Gemini generation exactly as it did before this module existed.
  Future<AiTeacherContentItem?> findMatchingLesson(String question) async {
    final normalized = question.toLowerCase();
    if (normalized.trim().isEmpty) return null;
    final snap = await _ref.get();
    for (final doc in snap.docs) {
      final item = AiTeacherContentItem.fromMap(doc.data(), doc.id);
      for (final keyword in item.keywords) {
        if (keyword.trim().isEmpty) continue;
        if (normalized.contains(keyword.toLowerCase().trim())) {
          return item;
        }
      }
    }
    return null;
  }
}

/// Shared instance used by the Admin Panel and the AI Teacher Classroom.
final AiTeacherContentRepository aiTeacherContentRepository =
    AiTeacherContentRepository();
