import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';

/// Reads/writes `ragChunks/{chunkId}`.
class RagChunkRepository {
  RagChunkRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'ragChunks';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Future<List<RagChunk>> getForSource(String sourceId) async {
    if (sourceId.isEmpty) return const [];
    final snap = await _ref.where('sourceId', isEqualTo: sourceId).get();
    final chunks = snap.docs
        .map((d) => RagChunk.fromMap(d.data(), d.id))
        .toList()
      ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
    return chunks;
  }

  /// Published chunks, optionally limited to selected source ids.
  Future<List<RagChunk>> getPublished({
    List<String> sourceIds = const [],
    String subjectId = '',
    String chapterId = '',
  }) async {
    Query<Map<String, dynamic>> q = _ref.where('published', isEqualTo: true);
    if (sourceIds.length == 1) {
      q = q.where('sourceId', isEqualTo: sourceIds.first);
    } else if (chapterId.isNotEmpty) {
      q = q.where('chapterId', isEqualTo: chapterId);
    } else if (subjectId.isNotEmpty) {
      q = q.where('subjectId', isEqualTo: subjectId);
    }
    final snap = await q.get();
    var chunks =
        snap.docs.map((d) => RagChunk.fromMap(d.data(), d.id)).toList();
    if (sourceIds.length > 1) {
      final ids = sourceIds.toSet();
      chunks = chunks.where((c) => ids.contains(c.sourceId)).toList();
    }
    if (sourceIds.length == 1) {
      if (subjectId.isNotEmpty) {
        chunks = chunks.where((c) => c.subjectId == subjectId).toList();
      }
      if (chapterId.isNotEmpty) {
        chunks = chunks.where((c) => c.chapterId == chapterId).toList();
      }
    } else if (chapterId.isNotEmpty && subjectId.isNotEmpty) {
      chunks = chunks.where((c) => c.subjectId == subjectId).toList();
    }
    return chunks;
  }

  Future<void> replaceSourceChunks({
    required String sourceId,
    required List<RagChunk> chunks,
  }) async {
    try {
      await deleteForSource(sourceId);
      if (chunks.isEmpty) return;
      const pageSize = 400;
      for (var i = 0; i < chunks.length; i += pageSize) {
        final batch = _firestore.batch();
        final slice = chunks.sublist(
          i,
          i + pageSize > chunks.length ? chunks.length : i + pageSize,
        );
        for (final chunk in slice) {
          final doc = chunk.id.isEmpty ? _ref.doc() : _ref.doc(chunk.id);
          batch.set(doc, _payload(chunk));
        }
        try {
          await batch.commit();
        } catch (_) {
          final fallback = _firestore.batch();
          for (final chunk in slice) {
            final doc = chunk.id.isEmpty ? _ref.doc() : _ref.doc(chunk.id);
            fallback.set(doc, chunk.toMap(includeVectorValue: false));
          }
          await fallback.commit();
        }
      }
    } catch (e) {
      throw RagException.fromError(e);
    }
  }

  Map<String, dynamic> _payload(RagChunk chunk) {
    try {
      return chunk.toMap(includeVectorValue: true);
    } catch (_) {
      return chunk.toMap(includeVectorValue: false);
    }
  }

  Future<void> setPublishedForSource(String sourceId, bool published) async {
    final existing = await getForSource(sourceId);
    if (existing.isEmpty) return;
    const pageSize = 400;
    for (var i = 0; i < existing.length; i += pageSize) {
      final batch = _firestore.batch();
      final slice = existing.sublist(
        i,
        i + pageSize > existing.length ? existing.length : i + pageSize,
      );
      for (final chunk in slice) {
        batch.set(
          _ref.doc(chunk.id),
          {'published': published},
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  Future<void> deleteForSource(String sourceId) async {
    if (sourceId.isEmpty) return;
    try {
      while (true) {
        final snap = await _ref.where('sourceId', isEqualTo: sourceId).limit(400).get();
        if (snap.docs.isEmpty) return;
        final batch = _firestore.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        if (snap.docs.length < 400) return;
      }
    } catch (e) {
      throw RagException.fromError(e);
    }
  }
}

final RagChunkRepository ragChunkRepository = RagChunkRepository();
