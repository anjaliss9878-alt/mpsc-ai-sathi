import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/video_item.dart';

/// Reads/writes study video entries in Firestore at `videos/{id}`.
class VideoRepository {
  VideoRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'videos';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<VideoItem>> watchAll() {
    return _ref.snapshots().map(
          (snap) => snap.docs.map((d) => VideoItem.fromMap(d.data(), d.id)).toList(),
        );
  }

  Future<String> add(VideoItem item) async {
    final doc = await _ref.add(item.toMap());
    return doc.id;
  }

  Future<void> update(VideoItem item) async {
    await _ref.doc(item.id).set(item.toMap(), SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await _ref.doc(id).delete();
  }
}

/// Shared instance used by both the student Videos screen and the Admin
/// Panel.
final VideoRepository videoRepository = VideoRepository();
