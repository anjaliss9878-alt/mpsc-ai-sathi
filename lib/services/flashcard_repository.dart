import 'dart:async';

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

  /// Student revision: published workflow only. Drafts stay in Admin.
  Stream<List<FlashcardItem>> watchPublished() {
    return _watchStudentVisible();
  }

  Stream<List<FlashcardItem>> _watchStudentVisible() {
    return Stream.multi((controller) {
      StreamSubscription<List<FlashcardItem>>? sub;
      var usingFallback = false;

      List<FlashcardItem> filter(List<FlashcardItem> all) =>
          all.where((c) => c.isStudentVisible).toList();

      void listenPublished({required bool requirePublishedStatus}) {
        Query<Map<String, dynamic>> query =
            _ref.where('published', isEqualTo: true);
        if (requirePublishedStatus) {
          query = query.where('status', isEqualTo: 'published');
        }
        sub = query.snapshots().map((snap) {
          final items = snap.docs
              .map((d) => FlashcardItem.fromMap(d.data(), d.id))
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
