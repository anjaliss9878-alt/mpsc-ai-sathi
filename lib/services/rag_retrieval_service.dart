import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/rag/rag_vector.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';

/// One retrieved chunk with similarity / hybrid score.
class RagHit {
  const RagHit({
    required this.chunk,
    required this.score,
    this.vectorScore = 0,
    this.keywordScoreValue = 0,
  });

  final RagChunk chunk;
  final double score;
  final double vectorScore;
  final double keywordScoreValue;
}

/// Query embedding + hybrid retrieval over published Ready sources.
///
/// Production default: authenticated `/rag/retrieve` (Firestore vector
/// index, 768-d). The previous in-memory corpus download remains as a
/// fallback when the server path is unavailable (tests, local worker).
class RagRetrievalService {
  RagRetrievalService({
    RagSourceRepository? sources,
    RagChunkRepository? chunks,
    RagBackendClient? backend,
    FirebaseFirestore? firestore,
    Future<List<double>> Function(String query)? embedQuery,
    bool serverFirst = true,
  })  : _sources = sources ?? ragSourceRepository,
        _chunks = chunks ?? ragChunkRepository,
        _backend = backend ?? ragBackendClient,
        _firestore = firestore,
        _embedQuery = embedQuery,
        _serverFirst = serverFirst && embedQuery == null;

  final RagSourceRepository _sources;
  final RagChunkRepository _chunks;
  final RagBackendClient _backend;
  final FirebaseFirestore? _firestore;
  final Future<List<double>> Function(String query)? _embedQuery;
  final bool _serverFirst;

  /// Server-side vector retrieval. `null` means use the existing local path.
  Future<List<RagHit>?> tryServerRetrieve({
    required String query,
    RagSourceFilter filter = RagSourceFilter.allPublished,
  }) async {
    if (!_serverFirst || query.trim().isEmpty) return null;
    try {
      final remote = await _backend.retrieveChunks(
        query: query.trim(),
        examId: filter.examId,
        subjectId: filter.subjectId,
        chapterId: filter.chapterId,
        topicId: filter.topicId,
        domains: [
          for (final d in filter.domains) ragDomainToString(d),
        ],
        sourceIds: filter.sourceIds,
        topK: filter.topK,
        similarityThreshold: filter.similarityThreshold,
        hybrid: filter.hybrid,
      );
      if (remote == null) return null;
      final hits = <RagHit>[];
      for (final row in remote.hits) {
        final hit = _hitFromServer(row);
        if (hit == null) continue;
        if (filter.onlyPublishedReady && !hit.chunk.published) continue;
        if (!matchesRagChunkMetadata(hit.chunk, filter)) continue;
        hits.add(hit);
      }
      return _take(hits, filter.topK);
    } catch (_) {
      return null;
    }
  }

  RagHit? _hitFromServer(Map<String, dynamic> row) {
    final chunkMap = row['chunk'];
    if (chunkMap is! Map) return null;
    final data = Map<String, dynamic>.from(chunkMap);
    final chunk = RagChunk.fromMap(data, '${data['id'] ?? ''}');
    if (chunk.id.isEmpty || chunk.text.trim().isEmpty) return null;
    return RagHit(
      chunk: chunk,
      score: (row['score'] as num?)?.toDouble() ?? 0,
      vectorScore: (row['vectorScore'] as num?)?.toDouble() ?? 0,
      keywordScoreValue: (row['keywordScore'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<List<RagHit>> retrieve({
    required String query,
    RagSourceFilter filter = RagSourceFilter.allPublished,
    List<double>? queryEmbedding,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    if (queryEmbedding == null) {
      final remote = await tryServerRetrieve(query: q, filter: filter);
      if (remote != null) return remote;
    }

    final allowed = await _sources.resolveFilter(filter);
    if (allowed.isEmpty) return const [];
    final allowedIds = allowed.map((s) => s.id).toSet();

    List<double> embedding;
    try {
      embedding = queryEmbedding ??
          await (_embedQuery != null
              ? _embedQuery(q)
              : _backend.embedQuery(q));
    } catch (e) {
      throw RagException.fromError(e);
    }
    if (embedding.isEmpty) {
      throw RagException.embedding('Empty query embedding.');
    }

    List<RagChunk>? nearest;
    if (filter.scope == RagSourceScope.allPublished && _firestore != null) {
      nearest = await _tryFindNearest(queryVector: embedding);
    }

    var candidates = await _loadCandidates(filter, allowed);
    if (nearest != null && nearest.isNotEmpty) {
      final fromIndex = nearest
          .where((c) => allowedIds.contains(c.sourceId) && c.embedding.isNotEmpty)
          .toList();
      if (fromIndex.length >= filter.topK) {
        candidates = fromIndex;
      }
    }
    candidates = candidates
        .where((c) => allowedIds.contains(c.sourceId))
        .where((c) => c.embedding.isNotEmpty)
        .where((c) => !filter.onlyPublishedReady || c.published)
        .where((c) => matchesRagChunkMetadata(c, filter))
        .toList();
    if (candidates.isEmpty) return const [];

    try {
      final vectorHits = _rankVector(
        candidates,
        embedding,
        threshold: 0,
      );
      if (!filter.hybrid) {
        return _take(
          vectorHits.where((h) => h.score >= filter.similarityThreshold),
          filter.topK,
        );
      }
      return _hybrid(
        query: q,
        candidates: candidates,
        vectorHits: vectorHits,
        topK: filter.topK,
        threshold: filter.similarityThreshold,
      );
    } catch (e) {
      throw RagException.vectorSearch('$e');
    }
  }

  Future<List<RagChunk>> _loadCandidates(
    RagSourceFilter filter,
    List<RagSource> allowed,
  ) async {
    final sourceIds = allowed.map((s) => s.id).toList();
    if (!filter.onlyPublishedReady && sourceIds.length == 1) {
      return _chunks.getForSource(sourceIds.first);
    }
    return _chunks.getPublished(
      sourceIds: filter.scope == RagSourceScope.selectedSources ||
              sourceIds.length == 1
          ? sourceIds
          : const [],
      subjectId: filter.subjectId,
      chapterId: filter.chapterId,
    );
  }

  /// Optional Firestore Vector Search. Returns null when unavailable.
  Future<List<RagChunk>?> _tryFindNearest({
    required List<double> queryVector,
  }) async {
    if (_firestore == null || queryVector.isEmpty) return null;
    try {
      final snapshot = await _firestore
          .pipeline()
          .collection(RagChunkRepository.collection)
          .findNearest(
            Field('embedding'),
            queryVector,
            DistanceMeasure.cosine,
            limit: 40,
          )
          .execute();
      final out = <RagChunk>[];
      for (final row in snapshot.result) {
        final data = row.data();
        if (data == null) continue;
        final id = row.document?.id ?? '';
        if (id.isEmpty) continue;
        out.add(RagChunk.fromMap(Map<String, dynamic>.from(data), id));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  List<RagHit> _rankVector(
    List<RagChunk> candidates,
    List<double> queryEmbedding, {
    required double threshold,
  }) {
    final hits = <RagHit>[];
    for (final chunk in candidates) {
      final sim = cosineSimilarity(queryEmbedding, chunk.embedding);
      hits.add(RagHit(chunk: chunk, score: sim, vectorScore: sim));
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return [
      for (final h in hits)
        if (h.score >= threshold) h,
    ];
  }

  List<RagHit> _hybrid({
    required String query,
    required List<RagChunk> candidates,
    required List<RagHit> vectorHits,
    required int topK,
    required double threshold,
  }) {
    final tokens = ragKeywordTokens(query, limit: 24);
    final keywordRanked = [
      for (final c in candidates)
        RagHit(
          chunk: c,
          score: keywordScore(tokens, '${c.text} ${c.sourceTitle} ${c.keywords.join(' ')}'),
          keywordScoreValue: keywordScore(
            tokens,
            '${c.text} ${c.sourceTitle} ${c.keywords.join(' ')}',
          ),
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));

    final vectorIds = [for (final h in vectorHits) h.chunk.id];
    final keywordIds = [
      for (final h in keywordRanked)
        if (h.score > 0) h.chunk.id,
    ];
    final fused = reciprocalRankFusion(vectorIds, keywordIds);
    final byId = {for (final c in candidates) c.id: c};
    final vectorById = {for (final h in vectorHits) h.chunk.id: h};
    final keywordById = {for (final h in keywordRanked) h.chunk.id: h};

    final merged = fused.entries.map((e) {
      final chunk = byId[e.key];
      if (chunk == null) return null;
      final v = vectorById[e.key]?.vectorScore ?? 0;
      final k = keywordById[e.key]?.keywordScoreValue ?? 0;
      return RagHit(
        chunk: chunk,
        score: e.value,
        vectorScore: v,
        keywordScoreValue: k,
      );
    }).whereType<RagHit>().toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final strongVector = merged.where((h) => h.vectorScore >= threshold);
    final picked = strongVector.isNotEmpty ? strongVector : merged;
    return _take(picked, topK);
  }

  List<RagHit> _take(Iterable<RagHit> hits, int topK) {
    final k = topK < 1 ? 8 : topK;
    return hits.take(k).toList(growable: false);
  }
}

final RagRetrievalService ragRetrievalService = RagRetrievalService();
