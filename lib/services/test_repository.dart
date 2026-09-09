import 'dart:async';

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
    return _watchStudentVisible((t) => true);
  }

  Stream<List<TestItem>> watchForTopic(String topicId) {
    if (topicId.isEmpty) return Stream.value(const []);
    return _watchStudentVisible(
      (t) => contentLinkedToTopic(
        topicId: topicId,
        topicIdField: t.topicId,
        chapterIdField: t.chapterId,
        topicIds: t.topicIds,
      ),
    );
  }

  Stream<List<TestItem>> _watchStudentVisible(bool Function(TestItem t) extra) {
    return Stream.multi((controller) {
      StreamSubscription<List<TestItem>>? sub;
      var usingFallback = false;

      List<TestItem> filter(List<TestItem> all) =>
          all.where((t) => t.isStudentVisible && extra(t)).toList();

      void listenPublished({required bool requirePublishedStatus}) {
        Query<Map<String, dynamic>> query =
            _ref.where('published', isEqualTo: true);
        if (requirePublishedStatus) {
          query = query.where('status', isEqualTo: 'published');
        }
        sub = query.snapshots().map((snap) {
          final items = snap.docs
              .map((d) => TestItem.fromMap(d.data(), d.id))
              .toList()
            ..sort((a, b) => a.order.compareTo(b.order));
          return filter(items);
        }).listen(
          controller.add,
          onError: (Object error, StackTrace stackTrace) {
            if (!usingFallback &&
                !requirePublishedStatus &&
                error.toString().contains('permission-denied')) {
              usingFallback = true;
              sub?.cancel();
              listenPublished(requirePublishedStatus: true);
              return;
            }
            controller.addError(error, stackTrace);
          },
          onDone: controller.close,
        );
      }

      listenPublished(requirePublishedStatus: false);
      controller.onCancel = () async {
        await sub?.cancel();
      };
    });
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
