import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/multi_rag_result.dart';
import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/rag/rag_citations.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_router.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';

/// Multi-RAG retrieval over the **existing** `ragSources` / `ragChunks`
/// collections. Domains are metadata filters — documents are never copied
/// into a second database.
abstract class MultiRagRetriever {
  Future<MultiRagResult> retrieve(MultiRagQuery query);
}

class MultiRagRetrievalService implements MultiRagRetriever {
  MultiRagRetrievalService({
    RagRetrievalService? retrieval,
    RagRouter router = ragRouter,
    Future<List<double>> Function(String query)? embedQuery,
  })  : _retrieval = retrieval ?? ragRetrievalService,
        _router = router,
        _embedQuery = embedQuery;

  final RagRetrievalService _retrieval;
  final RagRouter _router;
  final Future<List<double>> Function(String query)? _embedQuery;

  @override
  Future<MultiRagResult> retrieve(MultiRagQuery query) async {
    final q = query.query.trim();
    final plan = query.domains.isNotEmpty
        ? RagRoutePlan(
            domains: query.domains,
            confidence: 1,
            reason: 'explicit_domains',
            examId: query.examId,
            subjectId: query.subjectId,
            chapterId: query.chapterId,
            topicId: query.topicId,
          )
        : _router.route(q, context: query.context);

    if (plan.domains.isEmpty || q.isEmpty && !query.context.fromAiTeacher) {
      return MultiRagResult(
        query: q,
        plan: plan,
        hits: const [],
        confidence: 0,
      );
    }

    final examId = query.examId.isNotEmpty ? query.examId : plan.examId;
    final subjectId =
        query.subjectId.isNotEmpty ? query.subjectId : plan.subjectId;
    final chapterId =
        query.chapterId.isNotEmpty ? query.chapterId : plan.chapterId;
    final topicId = query.topicId.isNotEmpty ? query.topicId : plan.topicId;

    final knowledgeDomains = [
      for (final d in plan.domains)
        if (d != RagDomain.studentPerformance) d,
    ];
    final hits = <MultiRagHit>[];

    if (q.isNotEmpty &&
        knowledgeDomains.isNotEmpty &&
        query.queryEmbedding == null &&
        _embedQuery == null) {
      final remote = await _retrieval.tryServerRetrieve(
        query: q,
        filter: RagSourceFilter(
          examId: examId,
          subjectId: subjectId,
          chapterId: chapterId,
          topicId: topicId,
          language: query.language,
          year: query.year,
          domains: knowledgeDomains,
          topK: query.topKPerDomain,
          similarityThreshold: query.similarityThreshold,
          hybrid: query.hybrid,
          scope: subjectId.isNotEmpty || chapterId.isNotEmpty
              ? RagSourceScope.subjectChapter
              : RagSourceScope.allPublished,
        ),
      );
      if (remote != null) {
        for (final hit in remote) {
          final domain = inferRagDomain(
            ragDomain: hit.chunk.ragDomain,
            contentType: hit.chunk.contentType,
            sourceType: hit.chunk.sourceType,
          );
          if (!knowledgeDomains.contains(domain)) continue;
          final confidence = ragHitConfidence(hit);
          hits.add(
            MultiRagHit(
              domain: domain,
              hit: hit,
              confidence: confidence,
              sourceRef: citationFromChunk(hit.chunk, confidence: confidence),
            ),
          );
        }
        if (plan.domains.contains(RagDomain.studentPerformance)) {
          hits.addAll(_performanceHits(query.performance, examId: examId));
        }
        return _assembleResult(q, plan, hits);
      }
    }

    List<double>? embedding = query.queryEmbedding;
    if (embedding == null && q.isNotEmpty && _embedQuery != null) {
      embedding = await _embedQuery(q);
    }

    final weakTopicIds = [
      for (final row in query.performance)
        if (row.topicId.isNotEmpty) row.topicId,
      for (final row in query.performance)
        if (row.chapterId.isNotEmpty) row.chapterId,
    ];
    for (final domain in plan.domains) {
      if (domain == RagDomain.studentPerformance) {
        hits.addAll(_performanceHits(query.performance, examId: examId));
        continue;
      }
      if (q.isEmpty) continue;

      var filter = RagSourceFilter(
        examId: examId,
        subjectId: subjectId,
        chapterId: chapterId,
        topicId: domain == RagDomain.notes &&
                weakTopicIds.isNotEmpty &&
                topicId.isEmpty
            ? ''
            : topicId,
        topicIds: domain == RagDomain.notes &&
                weakTopicIds.isNotEmpty &&
                topicId.isEmpty
            ? weakTopicIds
            : const [],
        language: query.language,
        year: query.year,
        domains: [domain],
        topK: query.topKPerDomain,
        similarityThreshold: query.similarityThreshold,
        hybrid: query.hybrid,
        scope: subjectId.isNotEmpty || chapterId.isNotEmpty
            ? RagSourceScope.subjectChapter
            : RagSourceScope.allPublished,
      );

      final domainHits = await _retrieval.retrieve(
        query: q,
        filter: filter,
        queryEmbedding: embedding,
      );
      for (final hit in domainHits) {
        final confidence = ragHitConfidence(hit);
        hits.add(
          MultiRagHit(
            domain: domain,
            hit: hit,
            confidence: confidence,
            sourceRef: citationFromChunk(hit.chunk, confidence: confidence),
          ),
        );
      }
    }

    return _assembleResult(q, plan, hits);
  }

  MultiRagResult _assembleResult(
    String q,
    RagRoutePlan plan,
    List<MultiRagHit> hits,
  ) {
    final sourceRefs = <RagCitation>[];
    final seen = <String>{};
    for (final hit in hits) {
      final key =
          '${hit.sourceRef.sourceId}|${hit.sourceRef.topic}|${hit.sourceRef.pageNumber}|${hit.domain.name}';
      if (seen.add(key)) sourceRefs.add(hit.sourceRef);
    }

    final meanHit = hits.isEmpty
        ? 0.0
        : hits.map((h) => h.confidence).reduce((a, b) => a + b) / hits.length;
    final confidence = ragConfidenceScore(
      plan.confidence * (hits.isEmpty ? 0.35 : (0.45 + 0.55 * meanHit)),
    );

    return MultiRagResult(
      query: q,
      plan: plan,
      hits: hits,
      confidence: confidence,
      sourceRefs: sourceRefs,
    );
  }

  List<MultiRagHit> _performanceHits(
    List<StudentPerformanceRecord> rows, {
    required String examId,
  }) {
    if (rows.isEmpty) return const [];
    final out = <MultiRagHit>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final accuracy = row.scorePercent.clamp(0, 100);
      final confidence = ragConfidenceScore((100 - accuracy) / 100);
      final chunk = RagChunk(
        id: 'perf_${row.topicId.isNotEmpty ? row.topicId : i}',
        sourceId: 'student_performance',
        sourceTitle: row.label,
        subject: row.subjectId,
        subjectId: row.subjectId,
        chapter: row.chapterId,
        chapterId: row.chapterId,
        topicId: row.topicId,
        text:
            '${row.label}. Accuracy ${accuracy.toStringAsFixed(0)}%. ${row.source}',
        embedding: const [1],
        language: row.language,
        sourceType: kStudentPerformanceContentType,
        examId: row.examId.isNotEmpty ? row.examId : examId,
        contentType: kStudentPerformanceContentType,
        source: row.source,
        status: row.status,
        ragDomain: ragDomainToString(RagDomain.studentPerformance),
        exam: kMpscDefaultExam,
        published: false,
      );
      final hit = RagHit(chunk: chunk, score: confidence, vectorScore: confidence);
      out.add(
        MultiRagHit(
          domain: RagDomain.studentPerformance,
          hit: hit,
          confidence: confidence,
          sourceRef: citationFromChunk(chunk, confidence: confidence),
        ),
      );
    }
    return out;
  }
}

final MultiRagRetrievalService multiRagRetrievalService =
    MultiRagRetrievalService();
