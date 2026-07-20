import 'package:cloud_firestore/cloud_firestore.dart';
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
