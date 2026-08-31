import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/test_item.dart';

/// Reads/writes Mock Test / CBT papers in Firestore at `tests/{id}`.
class TestRepository {
  TestRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'tests';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<TestItem>> watchAll() {
    return _ref.orderBy('order').snapshots().map(
          (snap) => snap.docs.map((d) => TestItem.fromMap(d.data(), d.id)).toList(),
        );
  }

  /// Student Tests / Mock Tests: published papers only. Legacy docs without
  /// `published` parse as published so existing papers stay visible.
  Stream<List<TestItem>> watchPublished() {
    return watchAll().map(
      (all) => all.where((t) => t.isStudentVisible).toList(),
    );
  }

  Stream<List<TestItem>> watchForTopic(String topicId) {
    if (topicId.isEmpty) return Stream.value(const []);
    return watchAll().map(
      (all) => all
          .where(
            (t) => contentLinkedToTopic(
              topicId: topicId,
              topicIdField: t.topicId,
              chapterIdField: t.chapterId,
              topicIds: t.topicIds,
            ),
          )
          .toList(),
    );
  }

  Future<TestItem?> getById(String id) async {
    final doc = await _ref.doc(id).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    return TestItem.fromMap(data, doc.id);
  }

  Future<String> add(TestItem item) async {
    final doc = await _ref.add(item.toMap());
    return doc.id;
  }

  Future<void> update(TestItem item) async {
    await _ref.doc(item.id).set(item.toMap(), SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await _ref.doc(id).delete();
  }
}

/// Shared instance used by both the student Mock Tests/CBT screens and the
/// Admin Panel.
final TestRepository testRepository = TestRepository();
