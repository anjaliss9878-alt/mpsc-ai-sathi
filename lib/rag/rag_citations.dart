import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';

RagCitation citationFromChunk(RagChunk chunk, {double confidence = 0}) {
  return RagCitation(
    sourceId: chunk.sourceId,
    subject: chunk.subject,
    chapter: chunk.chapter,
    topic: chunk.sourceTitle,
    pageNumber: chunk.pageNumber,
    sourceType: chunk.sourceType,
    examId: chunk.examId,
    subjectId: chunk.subjectId,
    chapterId: chunk.chapterId,
    topicId: chunk.topicId,
    contentType: chunk.contentType,
    language: chunk.language,
    source: chunk.source,
    year: chunk.year,
    difficulty: chunk.difficulty,
    status: chunk.status,
    ragDomain: chunk.ragDomain.isNotEmpty
        ? chunk.ragDomain
        : ragDomainToString(chunk.domain),
    confidence: confidence,
    sourceTitle: chunk.sourceTitle,
    chunkId: chunk.id,
  );
}

List<RagCitation> citationsFromHits(Iterable<RagHit> hits) {
  final seen = <String>{};
  final out = <RagCitation>[];
  for (final hit in hits) {
    final c = citationFromChunk(hit.chunk, confidence: hit.score);
    final key =
        '${c.sourceId}|${c.subject}|${c.chapter}|${c.topic}|${c.pageNumber}|${c.ragDomain}';
    if (seen.add(key)) out.add(c);
  }
  return out;
}

List<RagCitation> citationsFromChunkIndexes(
  List<RagHit> hits,
  Iterable<int> indexes,
) {
  final out = <RagCitation>[];
  final seen = <int>{};
  for (final i in indexes) {
    if (i < 0 || i >= hits.length) continue;
    if (!seen.add(i)) continue;
    out.add(citationFromChunk(hits[i].chunk));
  }
  return out;
}

List<int> parseChunkIndexes(dynamic raw) {
  if (raw is! List) return const [];
  final out = <int>[];
  for (final e in raw) {
    if (e is num) out.add(e.toInt());
    if (e is String) {
      final n = int.tryParse(e.trim());
      if (n != null) out.add(n);
    }
  }
  return out;
}
