import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/multi_rag_result.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_router.dart';

/// Admin-facing index lifecycle on top of [RagSourceStatus].
/// Does not replace the existing processing pipeline.
enum RagManagementStatus {
  draft,
  processing,
  ready,
  failed,
  needsReindex,
}

String ragManagementStatusToString(RagManagementStatus status) {
  switch (status) {
    case RagManagementStatus.draft:
      return 'Draft';
    case RagManagementStatus.processing:
      return 'Processing';
    case RagManagementStatus.ready:
      return 'Ready';
    case RagManagementStatus.failed:
      return 'Failed';
    case RagManagementStatus.needsReindex:
      return 'Needs Re-index';
  }
}

RagManagementStatus ragManagementStatus(RagSource source) {
  if (source.status == RagSourceStatus.failed) {
    return RagManagementStatus.failed;
  }
  if (source.status == RagSourceStatus.processing) {
    return RagManagementStatus.processing;
  }
  if (source.needsReindex) return RagManagementStatus.needsReindex;
  if (source.status == RagSourceStatus.ready) {
    return RagManagementStatus.ready;
  }
  return RagManagementStatus.draft;
}

enum RagEmbeddingStatus { pending, processing, embedded, failed, stale }

String ragEmbeddingStatusLabel(RagEmbeddingStatus status) {
  switch (status) {
    case RagEmbeddingStatus.pending:
      return 'Not embedded';
    case RagEmbeddingStatus.processing:
      return 'Embedding';
    case RagEmbeddingStatus.embedded:
      return 'Embedded';
    case RagEmbeddingStatus.failed:
      return 'Failed';
    case RagEmbeddingStatus.stale:
      return 'Stale';
  }
}

RagEmbeddingStatus ragEmbeddingStatus(RagSource source) {
  final management = ragManagementStatus(source);
  switch (management) {
    case RagManagementStatus.failed:
      return RagEmbeddingStatus.failed;
    case RagManagementStatus.processing:
      return RagEmbeddingStatus.processing;
    case RagManagementStatus.needsReindex:
      return RagEmbeddingStatus.stale;
    case RagManagementStatus.ready:
      return source.chunkCount > 0
          ? RagEmbeddingStatus.embedded
          : RagEmbeddingStatus.stale;
    case RagManagementStatus.draft:
      return RagEmbeddingStatus.pending;
  }
}

/// Required Content Index fields before Index / Re-index.
class RagMetadataIssue {
  const RagMetadataIssue(this.field, this.message);

  final String field;
  final String message;
}

List<RagMetadataIssue> ragIndexMetadataIssues(RagSource source) {
  final issues = <RagMetadataIssue>[];
  if (source.title.trim().isEmpty) {
    issues.add(const RagMetadataIssue('title', 'Title is required.'));
  }
  if (source.examId.trim().isEmpty && source.exam.trim().isEmpty) {
    issues.add(const RagMetadataIssue('examId', 'Exam is required.'));
  }
  if (source.sourceType == RagSourceType.pdf && source.fileUrl.trim().isEmpty) {
    issues.add(const RagMetadataIssue('fileUrl', 'PDF URL is required.'));
  }
  if (source.sourceType == RagSourceType.notes ||
      source.sourceType == RagSourceType.pyq ||
      source.sourceType == RagSourceType.currentAffairs ||
      source.sourceType == RagSourceType.chapter) {
    if (source.linkedId.trim().isEmpty && source.chapterId.trim().isEmpty) {
      issues.add(
        const RagMetadataIssue(
          'linkedId',
          'Linked document or chapter id is required.',
        ),
      );
    }
  }
  return issues;
}

bool ragMetadataIsIndexable(RagSource source) =>
    ragIndexMetadataIssues(source).isEmpty;

String ragDocumentLabel(RagSource source) {
  if (source.linkedId.trim().isNotEmpty) return source.linkedId;
  if (source.fileUrl.trim().isNotEmpty) return 'PDF';
  if (source.title.trim().isNotEmpty) return source.title;
  return '—';
}

DateTime? ragLastIndexedAt(RagSource source) {
  if (source.status == RagSourceStatus.uploading && !source.needsReindex) {
    return null;
  }
  return source.updatedAt;
}

/// Builds a Multi-RAG test query. Student-performance domain is included only
/// when [studentUid] is explicitly set (admin opt-in).
MultiRagQuery buildAdminRagTestQuery({
  required String question,
  String examId = '',
  String subjectId = '',
  String chapterId = '',
  String topicId = '',
  List<RagDomain> domains = const [],
  String studentUid = '',
  List<StudentPerformanceRecord> performance = const [],
}) {
  final includePerformance = domains.contains(RagDomain.studentPerformance) &&
      studentUid.trim().isNotEmpty;
  final filtered = [
    for (final d in domains)
      if (d != RagDomain.studentPerformance || includePerformance) d,
  ];
  return MultiRagQuery(
    query: question.trim(),
    context: RagRouteContext(
      examId: examId.isEmpty ? kDefaultExamId : examId,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
    ),
    domains: filtered,
    examId: examId,
    subjectId: subjectId,
    chapterId: chapterId,
    topicId: topicId,
    performance: includePerformance ? performance : const [],
  );
}

bool adminRagTestAllowsStudentPerformance({
  required List<RagDomain> domains,
  required String studentUid,
}) {
  return domains.contains(RagDomain.studentPerformance) &&
      studentUid.trim().isNotEmpty;
}
