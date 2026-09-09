import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/study_content_pack.dart';

/// Student-submitted study packs at `studyPacks/{id}`. Never published.
class StudyPackRepository {
  StudyPackRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'studyPacks';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Future<String> submit(StudyContentPack pack) async {
    final data = pack.toMap();
    data['published'] = false;
    data['insufficient'] = false;
    if (pack.id.isNotEmpty) {
      await _ref.doc(pack.id).set(data, SetOptions(merge: true));
      return pack.id;
    }
    final doc = await _ref.add(data);
    return doc.id;
  }

  Stream<List<StudyContentPack>> watchMine(String uid) {
    return _ref.where('uid', isEqualTo: uid).snapshots().map((snap) {
      final items = snap.docs
          .map((d) => StudyContentPack.fromMap(d.data(), d.id))
          .toList()
        ..sort((a, b) {
          final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });
      return items;
    });
  }

  Stream<List<StudyContentPack>> watchPendingReview() {
    return _ref.snapshots().map((snap) {
      final items = snap.docs
          .map((d) => StudyContentPack.fromMap(d.data(), d.id))
          .where((p) => p.status == StudyPackReviewStatus.pendingReview)
          .toList()
        ..sort((a, b) {
          final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });
      return items;
    });
  }

  Future<void> markSavedAsDraft({
    required String packId,
    required String noteId,
  }) async {
    await _ref.doc(packId).set(
      {
        'status': studyPackReviewStatusToString(
          StudyPackReviewStatus.savedAsDraft,
        ),
        'noteId': noteId,
        'published': false,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> dismiss(String packId) async {
    await _ref.doc(packId).set(
      {
        'status': studyPackReviewStatusToString(
          StudyPackReviewStatus.dismissed,
        ),
        'published': false,
      },
      SetOptions(merge: true),
    );
  }
}

final StudyPackRepository studyPackRepository = StudyPackRepository();
