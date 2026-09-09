import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
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
    return _watchStudentVisible((p) => true);
  }

  Stream<List<PyqItem>> watchForChapter(String chapterId) {
    if (chapterId.isEmpty) return Stream.value(const []);
    return _watchStudentVisible(
      (p) => contentLinkedToTopic(
        topicId: chapterId,
        topicIdField: p.topicId,
        chapterIdField: p.chapterId,
      ),
    );
  }

  Stream<List<PyqItem>> watchForSubjectId(String subjectId) {
    if (subjectId.isEmpty) return Stream.value(const []);
    return _watchStudentVisible((p) => p.subjectId == subjectId);
  }

  Stream<List<PyqItem>> _watchStudentVisible(bool Function(PyqItem p) extra) {
    return Stream.multi((controller) {
      StreamSubscription<List<PyqItem>>? sub;
      var usingFallback = false;

      List<PyqItem> filter(List<PyqItem> all) =>
          all.where((p) => p.isStudentVisible && extra(p)).toList();

      void listenPublished({required bool requirePublishedStatus}) {
        Query<Map<String, dynamic>> query =
            _ref.where('published', isEqualTo: true);
        if (requirePublishedStatus) {
          query = query.where('status', isEqualTo: 'published');
        }
        sub = query.snapshots().map((snap) {
          final items = snap.docs
              .map((d) => PyqItem.fromMap(d.data(), d.id))
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

  Future<String> add(PyqItem item) async {
    final doc = await _ref.add(item.toMap());
    return doc.id;
  }

  Future<void> update(PyqItem item) async {
    await _ref.doc(item.id).set(item.toMap(), SetOptions(merge: true));
  }

  /// Approve / publish / unpublish without rewriting official question text.
  Future<void> updateWorkflow(String id, NoteWorkflowStatus status) async {
    if (id.isEmpty) return;
    await _ref.doc(id).set({
      'status': contentWorkflowStatusToString(status),
      'published': contentWorkflowPublishedFlag(status),
    }, SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await _ref.doc(id).delete();
  }
}

/// Shared instance used by both the student PYQ screen and the Admin Panel.
final PyqRepository pyqRepository = PyqRepository();
