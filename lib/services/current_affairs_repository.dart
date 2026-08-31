import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/current_affair_item.dart';

/// Reads/writes Current Affairs entries in Firestore at
/// `currentAffairs/{id}`.
class CurrentAffairsRepository {
  CurrentAffairsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'currentAffairs';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<CurrentAffairItem>> watchAll() {
    return _ref.orderBy('date', descending: true).snapshots().map(
          (snap) => snap.docs
              .map((d) => CurrentAffairItem.fromMap(d.data(), d.id))
              .toList(),
        );
  }

  /// Students only see published entries. Legacy docs without status stay
  /// visible (treated as published).
  Stream<List<CurrentAffairItem>> watchPublished() {
    return watchAll().map(
      (all) => all.where((e) => e.isStudentVisible).toList(),
    );
  }

  Future<String> add(CurrentAffairItem item) async {
    final doc = await _ref.add(item.toMap());
    return doc.id;
  }

  Future<void> update(CurrentAffairItem item) async {
    await _ref.doc(item.id).set(item.toMap(), SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await _ref.doc(id).delete();
  }
}

/// Shared instance used by both the student Current Affairs screen and the
/// Admin Panel.
final CurrentAffairsRepository currentAffairsRepository =
    CurrentAffairsRepository();
