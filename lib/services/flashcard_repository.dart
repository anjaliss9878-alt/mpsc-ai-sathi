import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/flashcard_item.dart';

/// Reads/writes flashcards at `flashcards/{id}`.
class FlashcardRepository {
  FlashcardRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'flashcards';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<FlashcardItem>> watchAll() {
    return _ref.orderBy('order').snapshots().map(
          (snap) => snap.docs
              .map((d) => FlashcardItem.fromMap(d.data(), d.id))
              .toList(),
        );
  }

  Stream<List<FlashcardItem>> watchPublished() {
    return watchAll().map(
      (all) => all.where((c) => c.isStudentVisible).toList(),
    );
  }

  Future<String> add(FlashcardItem item) async {
    final doc = await _ref.add(item.toMap());
    return doc.id;
  }

  Future<void> update(FlashcardItem item) async {
    await _ref.doc(item.id).set(item.toMap(), SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await _ref.doc(id).delete();
  }
}

final FlashcardRepository flashcardRepository = FlashcardRepository();
