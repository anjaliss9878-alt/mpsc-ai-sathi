import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/live_class_item.dart';

/// Reads/writes Live Class entries in Firestore at `liveClasses/{id}`.
class LiveClassRepository {
  LiveClassRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'liveClasses';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<LiveClassItem>> watchAll() {
    return _ref.snapshots().map(
          (snap) =>
              snap.docs.map((d) => LiveClassItem.fromMap(d.data(), d.id)).toList(),
        );
  }

  /// Live updates for a single class — used by the Join/Countdown screen so
  /// a status change made from the Admin Panel (e.g. upcoming → live) is
  /// reflected instantly without the student needing to reopen the screen.
  Stream<LiveClassItem?> watchById(String id) {
    return _ref.doc(id).snapshots().map(
          (doc) => doc.exists ? LiveClassItem.fromMap(doc.data()!, doc.id) : null,
        );
  }

  Future<LiveClassItem?> getById(String id) async {
    final doc = await _ref.doc(id).get();
    if (!doc.exists) return null;
    return LiveClassItem.fromMap(doc.data()!, doc.id);
  }

  Future<String> add(LiveClassItem item) async {
    final doc = await _ref.add(item.toMap());
    return doc.id;
  }

  Future<void> update(LiveClassItem item) async {
    await _ref.doc(item.id).set(item.toMap(), SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await _ref.doc(id).delete();
  }
}

/// Shared instance used by both the student Live Classes screens and the
/// Admin Panel.
final LiveClassRepository liveClassRepository = LiveClassRepository();
