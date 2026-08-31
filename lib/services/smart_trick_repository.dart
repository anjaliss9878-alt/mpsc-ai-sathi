import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/smart_trick_item.dart';

/// Reads/writes memory tricks at `smartTricks/{id}`.
class SmartTrickRepository {
  SmartTrickRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'smartTricks';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<SmartTrickItem>> watchAll() {
    return _ref.orderBy('order').snapshots().map(
          (snap) => snap.docs
              .map((d) => SmartTrickItem.fromMap(d.data(), d.id))
              .toList(),
        );
  }

  Stream<List<SmartTrickItem>> watchPublished() {
    return watchAll().map(
      (all) => all.where((t) => t.isStudentVisible).toList(),
    );
  }

  Future<String> add(SmartTrickItem item) async {
    final doc = await _ref.add(item.toMap());
    return doc.id;
  }

  Future<void> update(SmartTrickItem item) async {
    await _ref.doc(item.id).set(item.toMap(), SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await _ref.doc(id).delete();
  }
}

final SmartTrickRepository smartTrickRepository = SmartTrickRepository();
