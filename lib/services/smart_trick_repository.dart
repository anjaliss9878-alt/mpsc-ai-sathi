import 'dart:async';

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

  /// Student revision: published workflow only. Drafts stay in Admin.
  Stream<List<SmartTrickItem>> watchPublished() {
    return _watchStudentVisible();
  }

  Stream<List<SmartTrickItem>> _watchStudentVisible() {
    return Stream.multi((controller) {
      StreamSubscription<List<SmartTrickItem>>? sub;
      var usingFallback = false;

      List<SmartTrickItem> filter(List<SmartTrickItem> all) =>
          all.where((t) => t.isStudentVisible).toList();

      void listenPublished({required bool requirePublishedStatus}) {
        Query<Map<String, dynamic>> query =
            _ref.where('published', isEqualTo: true);
        if (requirePublishedStatus) {
          query = query.where('status', isEqualTo: 'published');
        }
        sub = query.snapshots().map((snap) {
          final items = snap.docs
              .map((d) => SmartTrickItem.fromMap(d.data(), d.id))
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
