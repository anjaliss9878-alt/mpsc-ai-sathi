import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_router.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';

/// One retrieved item with domain, confidence, and content-index metadata.
class MultiRagHit {
  const MultiRagHit({
    required this.domain,
    required this.hit,
    required this.confidence,
    required this.sourceRef,
  });

  final RagDomain domain;
  final RagHit hit;
  final double confidence;
  final RagCitation sourceRef;

  RagChunk get chunk => hit.chunk;
}

/// Combined Multi-RAG answer contract used by later parts.
class MultiRagResult {
  const MultiRagResult({
    required this.query,
    required this.plan,
    required this.hits,
    required this.confidence,
    this.sourceRefs = const [],
  });

  final String query;
  final RagRoutePlan plan;
  final List<MultiRagHit> hits;
  final double confidence;
  final List<RagCitation> sourceRefs;

  bool get isEmpty => hits.isEmpty;

  List<MultiRagHit> hitsFor(RagDomain domain) =>
      hits.where((h) => h.domain == domain).toList(growable: false);
}

/// Student-owned performance row used by [RagDomain.studentPerformance].
/// Never written into `ragChunks`.
class StudentPerformanceRecord {
  const StudentPerformanceRecord({
    required this.label,
    this.examId = '',
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
    this.scorePercent = 0,
    this.source = '',
    this.status = '',
    this.language = '',
  });

  final String label;
  final String examId;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final double scorePercent;
  final String source;
  final String status;
  final String language;
}

/// Query for the Multi-RAG retrieval interface.
class MultiRagQuery {
  const MultiRagQuery({
    required this.query,
    this.context = const RagRouteContext(),
    this.domains = const [],
    this.examId = '',
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
    this.language = '',
    this.year,
    this.topKPerDomain = 8,
    this.similarityThreshold = 0.05,
    this.hybrid = true,
    this.performance = const [],
    this.queryEmbedding,
  });

  final String query;
  final RagRouteContext context;

  /// When non-empty, skip the router and search these domains.
  final List<RagDomain> domains;
  final String examId;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final String language;
  final int? year;
  final int topKPerDomain;
  final double similarityThreshold;
  final bool hybrid;

  /// Injected student performance rows (tests + later student wiring).
  final List<StudentPerformanceRecord> performance;

  /// Precomputed query vector (Vertex or existing embed). When set, retrieval
  /// skips a second embed call.
  final List<double>? queryEmbedding;
}

/// Clamps a retrieval / router score into 0..1.
double ragConfidenceScore(double raw) {
  if (raw.isNaN) return 0;
  if (raw >= 1) return 1;
  if (raw <= 0) return 0;
  return raw;
}

double ragHitConfidence(RagHit hit) {
  if (hit.vectorScore > 0) return ragConfidenceScore(hit.vectorScore);
  return ragConfidenceScore(hit.score);
}
