import 'package:mpsc_combine_ai/models/multi_rag_result.dart';
import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/rag/rag_citations.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';

/// Numbered, source-grounded context. Never invents chunks.
class MultiRagContext {
  const MultiRagContext({
    required this.query,
    required this.domains,
    required this.chunks,
    this.citations = const [],
  });

  final String query;
  final List<RagDomain> domains;
  final List<Map<String, dynamic>> chunks;
  final List<RagCitation> citations;

  bool get hasEvidence => chunks.isNotEmpty;
}

/// Builds the generation payload from retrieved Multi-RAG hits.
/// Empty retrieval ⇒ empty context (callers must not generate).
class MultiRagContextBuilder {
  const MultiRagContextBuilder();

  MultiRagContext build(
    MultiRagResult retrieved, {
    bool includePerformance = false,
  }) {
    final chunks = <Map<String, dynamic>>[];
    final citations = <RagCitation>[];
    for (final hit in retrieved.hits) {
      if (!includePerformance && hit.domain == RagDomain.studentPerformance) {
        continue;
      }
      final c = hit.chunk;
      final citation = citationFromChunk(hit.chunk, confidence: hit.confidence);
      chunks.add({
        'index': chunks.length,
        'sourceId': c.sourceId,
        'chunkId': c.id,
        'sourceTitle': c.sourceTitle,
        'contentType': c.contentType,
        'topic': c.sourceTitle,
        'topicId': c.topicId,
        'subject': c.subject,
        'subjectId': c.subjectId,
        'chapter': c.chapter,
        'chapterId': c.chapterId,
        'examId': c.examId,
        'language': c.language,
        'year': c.year,
        'pageNumber': c.pageNumber,
        'ragDomain': ragDomainToString(hit.domain),
        'text': c.text,
        'documentRef': citation.documentRef,
      });
      citations.add(citation);
    }
    return MultiRagContext(
      query: retrieved.query,
      domains: retrieved.plan.domains,
      chunks: chunks,
      citations: citations,
    );
  }
}

const MultiRagContextBuilder multiRagContextBuilder = MultiRagContextBuilder();
