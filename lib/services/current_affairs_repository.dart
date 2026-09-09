import 'dart:async';

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
    return Stream.multi((controller) {
      StreamSubscription<List<CurrentAffairItem>>? sub;
      var usingFallback = false;

      List<CurrentAffairItem> filter(List<CurrentAffairItem> all) =>
          all.where((e) => e.isStudentVisible).toList();

      void listenPublished({required bool requirePublishedStatus}) {
        Query<Map<String, dynamic>> query =
            _ref.where('published', isEqualTo: true);
        if (requirePublishedStatus) {
          query = query.where('status', isEqualTo: 'published');
        }
        sub = query.snapshots().map((snap) {
          final items = snap.docs
              .map((d) => CurrentAffairItem.fromMap(d.data(), d.id))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
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
