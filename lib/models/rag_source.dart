import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Processing lifecycle. A source is never [ready] until extract + chunk +
/// embed all succeed.
enum RagSourceStatus {
  uploading,
  processing,
  ready,
  failed,
}

RagSourceStatus ragSourceStatusFromString(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'uploading':
      return RagSourceStatus.uploading;
    case 'processing':
      return RagSourceStatus.processing;
    case 'ready':
      return RagSourceStatus.ready;
    case 'failed':
      return RagSourceStatus.failed;
    default:
      return RagSourceStatus.uploading;
  }
}

String ragSourceStatusToString(RagSourceStatus status) {
  switch (status) {
    case RagSourceStatus.uploading:
      return 'Uploading';
    case RagSourceStatus.processing:
      return 'Processing';
    case RagSourceStatus.ready:
      return 'Ready';
    case RagSourceStatus.failed:
      return 'Failed';
  }
}

/// Kind of knowledge source. Existing notes/PYQs/CA/chapters are *linked*,
/// not copied into a second content collection.
enum RagSourceType {
  pdf,
  text,
  notes,
  pyq,
  currentAffairs,
  chapter,
}

RagSourceType ragSourceTypeFromString(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'pdf':
      return RagSourceType.pdf;
    case 'text':
      return RagSourceType.text;
    case 'notes':
    case 'mpsc notes':
    case 'mpsc_notes':
      return RagSourceType.notes;
    case 'pyq':
    case 'pyqs':
      return RagSourceType.pyq;
    case 'currentaffairs':
    case 'current_affairs':
    case 'current affairs':
      return RagSourceType.currentAffairs;
    case 'chapter':
    case 'chapter material':
    case 'chapter_material':
      return RagSourceType.chapter;
    default:
      return RagSourceType.pdf;
  }
}

String ragSourceTypeToString(RagSourceType type) {
  switch (type) {
    case RagSourceType.pdf:
      return 'pdf';
    case RagSourceType.text:
      return 'text';
    case RagSourceType.notes:
      return 'notes';
    case RagSourceType.pyq:
      return 'pyq';
    case RagSourceType.currentAffairs:
      return 'currentAffairs';
    case RagSourceType.chapter:
      return 'chapter';
  }
}

String ragSourceTypeLabel(RagSourceType type) {
  switch (type) {
    case RagSourceType.pdf:
      return 'PDF';
    case RagSourceType.text:
      return 'Text';
    case RagSourceType.notes:
      return 'MPSC Notes';
    case RagSourceType.pyq:
      return 'PYQs';
    case RagSourceType.currentAffairs:
      return 'Current Affairs';
    case RagSourceType.chapter:
      return 'Chapter material';
  }
}

/// Knowledge source metadata at `ragSources/{sourceId}`.
class RagSource {
  const RagSource({
    required this.id,
    required this.title,
    required this.subject,
    required this.chapter,
    required this.exam,
    required this.fileUrl,
    required this.uploadedBy,
    required this.createdAt,
    required this.status,
    required this.published,
    this.sourceType = RagSourceType.pdf,
    this.subjectId = '',
    this.chapterId = '',
    this.storagePath = '',
    this.errorMessage = '',
    this.contentHash = '',
    this.chunkCount = 0,
    this.language = '',
    this.linkedCollection = '',
    this.linkedId = '',
    this.ownsFile = false,
    this.examId = '',
    this.topicId = '',
    this.noteId = '',
    this.contentType = '',
    this.source = '',
    this.year,
    this.difficulty = '',
    this.contentStatus = '',
    this.ragDomain = '',
    this.needsReindex = false,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String subject;
  final String subjectId;
  final String chapter;
  final String chapterId;
  final String exam;
  final String fileUrl;
  final String storagePath;
  final String uploadedBy;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final RagSourceStatus status;
  final bool published;
  final RagSourceType sourceType;
  final String errorMessage;
  final String contentHash;
  final int chunkCount;
  final String language;
  final String linkedCollection;
  final String linkedId;
  final bool ownsFile;
  final String examId;
  final String topicId;
  final String noteId;
  final String contentType;
  final String source;
  final int? year;
  final String difficulty;

  /// Content workflow on the linked note/PYQ/CA (`published`, `draft`, …).
  /// Distinct from [status] which is RAG processing lifecycle.
  final String contentStatus;
  final String ragDomain;
  final bool needsReindex;

  bool get isReady => status == RagSourceStatus.ready;
  bool get isFailed => status == RagSourceStatus.failed;
  bool get isUsableForRetrieval => published && isReady;

  /// Logical Multi-RAG domain, inferred for legacy rows that omit [ragDomain].
  RagDomain get domain => inferRagDomain(
        ragDomain: ragDomain,
        contentType: contentType,
        sourceType: ragSourceTypeToString(sourceType),
        linkedCollection: linkedCollection,
      );

  factory RagSource.fromMap(Map<String, dynamic> map, String id) {
    return RagSource(
      id: id,
      title: map['title'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      subjectId: map['subjectId'] as String? ?? '',
      chapter: map['chapter'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      exam: (map['exam'] as String?)?.trim().isNotEmpty == true
          ? (map['exam'] as String).trim()
          : kMpscDefaultExam,
      fileUrl: map['fileUrl'] as String? ?? '',
      storagePath: map['storagePath'] as String? ?? '',
      uploadedBy: map['uploadedBy'] as String? ?? '',
      createdAt: _parseTime(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseTime(map['updatedAt']),
      status: ragSourceStatusFromString(map['status'] as String?),
      published: asBool(map['published'], defaultValue: false),
      sourceType: ragSourceTypeFromString(map['sourceType'] as String?),
      errorMessage: map['errorMessage'] as String? ?? '',
      contentHash: map['contentHash'] as String? ?? '',
      chunkCount: asInt(map['chunkCount']),
      language: map['language'] as String? ?? '',
      linkedCollection: map['linkedCollection'] as String? ?? '',
      linkedId: map['linkedId'] as String? ?? '',
      ownsFile: asBool(map['ownsFile'], defaultValue: false),
      examId: map['examId'] as String? ?? '',
      topicId: map['topicId'] as String? ?? '',
      noteId: map['noteId'] as String? ?? '',
      contentType: map['contentType'] as String? ?? '',
      source: map['source'] as String? ?? '',
      year: _yearFrom(map['year']),
      difficulty: map['difficulty'] as String? ?? '',
      contentStatus: map['contentStatus'] as String? ?? '',
      ragDomain: map['ragDomain'] as String? ?? '',
      needsReindex: asBool(map['needsReindex'], defaultValue: false),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subject': subject,
      'subjectId': subjectId,
      'chapter': chapter,
      'chapterId': chapterId,
      'exam': exam.isEmpty ? kMpscDefaultExam : exam,
      'fileUrl': fileUrl,
      'storagePath': storagePath,
      'uploadedBy': uploadedBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
      'status': ragSourceStatusToString(status),
      'published': published,
      'sourceType': ragSourceTypeToString(sourceType),
      'errorMessage': errorMessage,
      'contentHash': contentHash,
      'chunkCount': chunkCount,
      'language': language,
      'linkedCollection': linkedCollection,
      'linkedId': linkedId,
      'ownsFile': ownsFile,
      'examId': examId,
      'topicId': topicId,
      'noteId': noteId,
      'contentType': contentType,
      'source': source,
      'year': year,
      'difficulty': difficulty,
      'contentStatus': contentStatus,
      'ragDomain': ragDomain.isNotEmpty ? ragDomain : ragDomainToString(domain),
      'needsReindex': needsReindex,
    };
  }

  RagSource copyWith({
    String? title,
    String? subject,
    String? subjectId,
    String? chapter,
    String? chapterId,
    String? exam,
    String? fileUrl,
    String? storagePath,
    String? uploadedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    RagSourceStatus? status,
    bool? published,
    RagSourceType? sourceType,
    String? errorMessage,
    String? contentHash,
    int? chunkCount,
    String? language,
    String? linkedCollection,
    String? linkedId,
    bool? ownsFile,
    String? examId,
    String? topicId,
    String? noteId,
    String? contentType,
    String? source,
    int? year,
    String? difficulty,
    String? contentStatus,
    String? ragDomain,
    bool? needsReindex,
  }) {
    return RagSource(
      id: id,
      title: title ?? this.title,
      subject: subject ?? this.subject,
      subjectId: subjectId ?? this.subjectId,
      chapter: chapter ?? this.chapter,
      chapterId: chapterId ?? this.chapterId,
      exam: exam ?? this.exam,
      fileUrl: fileUrl ?? this.fileUrl,
      storagePath: storagePath ?? this.storagePath,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      published: published ?? this.published,
      sourceType: sourceType ?? this.sourceType,
      errorMessage: errorMessage ?? this.errorMessage,
      contentHash: contentHash ?? this.contentHash,
      chunkCount: chunkCount ?? this.chunkCount,
      language: language ?? this.language,
      linkedCollection: linkedCollection ?? this.linkedCollection,
      linkedId: linkedId ?? this.linkedId,
      ownsFile: ownsFile ?? this.ownsFile,
      examId: examId ?? this.examId,
      topicId: topicId ?? this.topicId,
      noteId: noteId ?? this.noteId,
      contentType: contentType ?? this.contentType,
      source: source ?? this.source,
      year: year ?? this.year,
      difficulty: difficulty ?? this.difficulty,
      contentStatus: contentStatus ?? this.contentStatus,
      ragDomain: ragDomain ?? this.ragDomain,
      needsReindex: needsReindex ?? this.needsReindex,
    );
  }
}

DateTime? _parseTime(dynamic value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

int? _yearFrom(dynamic value) {
  if (value == null) return null;
  if (value is num) {
    final n = value.toInt();
    return n >= 1 ? n : null;
  }
  if (value is String) {
    final n = int.tryParse(value.trim());
    if (n == null || n < 1) return null;
    return n;
  }
  return null;
}

/// Admin monitoring counts for the existing `ragSources` collection.
/// Indexed = Ready. Processing includes Uploading. Failed is failed only.
class RagAdminMonitorStats {
  const RagAdminMonitorStats({
    required this.total,
    required this.indexed,
    required this.processing,
    required this.failed,
  });

  final int total;
  final int indexed;
  final int processing;
  final int failed;
}

enum RagAdminStatusFilter { all, indexed, processing, failed, draft, needsReindex }

RagAdminMonitorStats ragAdminMonitorStats(Iterable<RagSource> sources) {
  var indexed = 0;
  var processing = 0;
  var failed = 0;
  var total = 0;
  for (final source in sources) {
    total++;
    switch (source.status) {
      case RagSourceStatus.ready:
        indexed++;
      case RagSourceStatus.processing:
      case RagSourceStatus.uploading:
        processing++;
      case RagSourceStatus.failed:
        failed++;
    }
  }
  return RagAdminMonitorStats(
    total: total,
    indexed: indexed,
    processing: processing,
    failed: failed,
  );
}

/// Local admin list filters. Does not change student retrieval
/// ([RagSourceFilter] / published-Ready only).
bool matchesRagAdminFilters(
  RagSource source, {
  String? subjectId,
  String? chapterId,
  String? topicId,
  String? contentType,
  String? examId,
  RagDomain? domain,
  RagAdminStatusFilter status = RagAdminStatusFilter.all,
}) {
  if (examId != null && examId.isNotEmpty && source.examId.isNotEmpty && source.examId != examId) {
    return false;
  }
  if (domain != null && source.domain != domain) {
    return false;
  }
  if (subjectId != null &&
      subjectId.isNotEmpty &&
      source.subjectId != subjectId) {
    return false;
  }
  if (chapterId != null &&
      chapterId.isNotEmpty &&
      source.chapterId != chapterId) {
    return false;
  }
  if (topicId != null && topicId.isNotEmpty && source.topicId != topicId) {
    return false;
  }
  if (contentType != null && contentType.isNotEmpty) {
    final type = contentType.trim();
    final sourceType = ragSourceTypeToString(source.sourceType);
    if (source.contentType != type && sourceType != type) {
      return false;
    }
  }
  switch (status) {
    case RagAdminStatusFilter.all:
      break;
    case RagAdminStatusFilter.indexed:
      if (source.status != RagSourceStatus.ready || source.needsReindex) {
        return false;
      }
    case RagAdminStatusFilter.processing:
      if (source.status != RagSourceStatus.processing &&
          source.status != RagSourceStatus.uploading) {
        return false;
      }
    case RagAdminStatusFilter.failed:
      if (source.status != RagSourceStatus.failed) return false;
    case RagAdminStatusFilter.draft:
      if (source.status != RagSourceStatus.uploading) return false;
    case RagAdminStatusFilter.needsReindex:
      if (!source.needsReindex) return false;
  }
  return true;
}
