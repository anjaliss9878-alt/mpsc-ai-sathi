import 'package:mpsc_combine_ai/rag/rag_confidence.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';

/// Sanitized Multi-RAG monitor row. Never stores scores, names, or emails.
class RagMonitorEvent {
  const RagMonitorEvent({
    required this.uid,
    required this.domains,
    required this.retrievalCount,
    required this.confidence,
    required this.confidenceBand,
    required this.sourceIds,
    required this.latencyMs,
    this.fallbackReason = '',
    this.mode = 'answer',
    this.examId = '',
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
  });

  final String uid;
  final List<RagDomain> domains;
  final int retrievalCount;
  final double confidence;
  final RagConfidenceBand confidenceBand;
  final List<String> sourceIds;
  final int latencyMs;
  final String fallbackReason;
  final String mode;
  final String examId;
  final String subjectId;
  final String chapterId;
  final String topicId;

  Map<String, dynamic> toMap() {
    return {
      'domains': [for (final d in domains) ragDomainToString(d)],
      'retrievalCount': retrievalCount,
      'confidence': confidence,
      'confidenceBand': ragConfidenceBandToString(confidenceBand),
      'sourceIds': sourceIds,
      'latencyMs': latencyMs,
      'fallbackReason': fallbackReason,
      'mode': mode,
      'examId': examId,
      'subjectId': subjectId,
      'chapterId': chapterId,
      'topicId': topicId,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }
}
