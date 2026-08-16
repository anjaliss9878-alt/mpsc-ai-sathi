import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/teaching_slide_deck_item.dart';

/// Reads/writes Teaching Slide decks in Firestore at `teachingSlides/{id}`.
class TeachingSlideRepository {
  TeachingSlideRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'teachingSlides';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<TeachingSlideDeckItem>> watchAll() {
    return _ref.snapshots().map(
          (snap) => snap.docs
              .map((d) => TeachingSlideDeckItem.fromMap(d.data(), d.id))
              .toList(),
        );
  }

  /// Used by the student Notes screen to show a "View Teaching Slides"
  /// button when a deck exists for the chapter being viewed.
  Stream<TeachingSlideDeckItem?> watchForChapter(String chapterId) {
    return _ref.where('chapterId', isEqualTo: chapterId).limit(1).snapshots().map(
          (snap) => snap.docs.isEmpty
              ? null
              : TeachingSlideDeckItem.fromMap(snap.docs.first.data(), snap.docs.first.id),
        );
  }

  Future<String> add(TeachingSlideDeckItem item) async {
    final doc = await _ref.add(item.toMap());
    return doc.id;
  }

  Future<void> update(TeachingSlideDeckItem item) async {
    await _ref.doc(item.id).set(item.toMap(), SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await _ref.doc(id).delete();
  }
}

/// Shared instance used by both the Admin Panel and student Notes screens.
final TeachingSlideRepository teachingSlideRepository = TeachingSlideRepository();
