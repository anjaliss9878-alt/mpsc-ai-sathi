import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/ai_generated_content.dart';

/// Firestore `aiGeneratedContent/{id}` — staging drafts before Admin publish.
class AiGeneratedContentRepository {
  AiGeneratedContentRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'aiGeneratedContent';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<AiGeneratedContentItem>> watchBatch(String batchId) {
    if (batchId.isEmpty) return Stream.value(const []);
    return _ref
        .where('generationBatchId', isEqualTo: batchId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => AiGeneratedContentItem.fromMap(d.data(), d.id))
          .toList()
        ..sort((a, b) {
          final ac = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bc = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return ac.compareTo(bc);
        });
      return list;
    });
  }

  Future<List<AiGeneratedContentItem>> getBatchOnce(String batchId) async {
    if (batchId.isEmpty) return const [];
    final snap =
        await _ref.where('generationBatchId', isEqualTo: batchId).get();
    return snap.docs
        .map((d) => AiGeneratedContentItem.fromMap(d.data(), d.id))
        .toList();
  }

  Future<String> add(AiGeneratedContentItem item) async {
    final data = item.toMap();
    final doc = await _ref.add(data);
    return doc.id;
  }

  Future<void> update(AiGeneratedContentItem item) async {
    if (item.id.isEmpty) return;
    await _ref.doc(item.id).set(item.toMap(), SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    if (id.isEmpty) return;
    await _ref.doc(id).delete();
  }

  Future<AiGeneratedContentItem?> get(String id) async {
    if (id.isEmpty) return null;
    final snap = await _ref.doc(id).get();
    if (!snap.exists || snap.data() == null) return null;
    return AiGeneratedContentItem.fromMap(snap.data()!, snap.id);
  }

  /// Content fingerprints already saved for this batch (retry / de-dupe).
  Future<Set<String>> existingFingerprints(String batchId) async {
    final items = await getBatchOnce(batchId);
    return {
      for (final item in items) fingerprintFor(item.contentType, item.content),
    };
  }

  static String fingerprintFor(
    AiGeneratedContentType type,
    Map<String, dynamic> content,
  ) {
    switch (type) {
      case AiGeneratedContentType.mcq:
        return 'mcq:${'${content['question']}'.trim().toLowerCase()}';
      case AiGeneratedContentType.flashcard:
        return 'fc:${'${content['front']}'.trim().toLowerCase()}';
      case AiGeneratedContentType.smartTrick:
        return 'st:${'${content['title']}'.trim().toLowerCase()}';
      case AiGeneratedContentType.notes:
        return 'notes:${'${content['title']}'.trim().toLowerCase()}';
      case AiGeneratedContentType.revisionSummary:
        return 'rev:${'${content['title']}'.trim().toLowerCase()}';
      case AiGeneratedContentType.importantPoints:
        return 'pts:${'${content['points']}'.toString().hashCode}';
      case AiGeneratedContentType.aiTeacherLesson:
        return 'lesson:${'${content['title']}'.trim().toLowerCase()}';
    }
  }
}

final AiGeneratedContentRepository aiGeneratedContentRepository =
    AiGeneratedContentRepository();
