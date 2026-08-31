import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';

/// Reads/writes MCQ practice questions in Firestore at `mcqs/{id}`.
class McqRepository {
  McqRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'mcqs';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<McqItem>> watchAll() {
    return _ref.orderBy('order').snapshots().map(
          (snap) => snap.docs.map((d) => McqItem.fromMap(d.data(), d.id)).toList(),
        );
  }

  /// Student practice: published workflow only. Drafts stay in Admin.
  Stream<List<McqItem>> watchPublished() {
    return watchAll().map(
      (all) => all.where((q) => q.isStudentVisible).toList(),
    );
  }

  /// MCQs whose [McqItem.subject] matches [subjectName] (case-insensitive),
  /// used by the Notes detail screen to show related practice questions.
  Stream<List<McqItem>> watchForSubject(String subjectName) {
    final needle = subjectName.trim().toLowerCase();
    if (needle.isEmpty) {
      return Stream.value(const []);
    }
    return watchAll().map(
      (all) => all
          .where((q) => q.isStudentVisible)
          .where((q) => q.subject.trim().toLowerCase() == needle ||
              q.subject.trim().toLowerCase().contains(needle) ||
              needle.contains(q.subject.trim().toLowerCase()))
          .toList(),
    );
  }

  /// MCQs linked to a Firestore chapter id (preferred over name matching).
  Stream<List<McqItem>> watchForChapter(String chapterId) {
    if (chapterId.isEmpty) return Stream.value(const []);
    return watchAll().map(
      (all) => all
          .where(
            (q) =>
                q.isStudentVisible &&
                contentLinkedToTopic(
                  topicId: chapterId,
                  topicIdField: q.topicId,
                  chapterIdField: q.chapterId,
                ),
          )
          .toList(),
    );
  }

  /// MCQs for a subject id, published only.
  Stream<List<McqItem>> watchForSubjectId(String subjectId) {
    if (subjectId.isEmpty) return Stream.value(const []);
    return watchAll().map(
      (all) => all
          .where((q) => q.isStudentVisible && q.subjectId == subjectId)
          .toList(),
    );
  }

  Future<String> add(McqItem item) async {
    final doc = await _ref.add(item.toMap());
    return doc.id;
  }

  Future<void> update(McqItem item) async {
    await _ref.doc(item.id).set(item.toMap(), SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await _ref.doc(id).delete();
  }
}

/// Shared instance used by both the student MCQ Practice screen and the
/// Admin Panel.
final McqRepository mcqRepository = McqRepository();
