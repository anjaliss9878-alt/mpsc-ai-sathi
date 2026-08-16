import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';

/// Reads/writes Previous Year Question entries in Firestore at `pyqs/{id}`.
class PyqRepository {
  PyqRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'pyqs';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<PyqItem>> watchAll() {
    return _ref.orderBy('order').snapshots().map(
          (snap) => snap.docs.map((d) => PyqItem.fromMap(d.data(), d.id)).toList(),
        );
  }

  Stream<List<PyqItem>> watchPublished() {
    return watchAll().map((all) => all.where((p) => p.published).toList());
  }

  Stream<List<PyqItem>> watchForChapter(String chapterId) {
    if (chapterId.isEmpty) return Stream.value(const []);
    return watchAll().map(
      (all) => all
          .where((p) => p.published && p.chapterId == chapterId)
          .toList(),
    );
  }

  Stream<List<PyqItem>> watchForSubjectId(String subjectId) {
    if (subjectId.isEmpty) return Stream.value(const []);
    return watchAll().map(
      (all) => all
          .where((p) => p.published && p.subjectId == subjectId)
          .toList(),
    );
  }

  Future<String> add(PyqItem item) async {
    final doc = await _ref.add(item.toMap());
    return doc.id;
  }

  Future<void> update(PyqItem item) async {
    await _ref.doc(item.id).set(item.toMap(), SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await _ref.doc(id).delete();
  }
}

/// Shared instance used by both the student PYQ screen and the Admin Panel.
final PyqRepository pyqRepository = PyqRepository();
