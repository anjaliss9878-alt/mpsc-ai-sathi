import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';

/// How a student (or future AI Teacher) scopes RAG retrieval.
enum RagSourceScope {
  /// Every published, Ready source.
  allPublished,

  /// Explicit source document ids (one or many).
  selectedSources,

  /// All published Ready sources for a subject (optional chapter).
  subjectChapter,
}

/// Selection contract for retrieval. Unpublished / non-Ready sources are
/// never used when [onlyPublishedReady] is true (the default).
///
/// Multi-RAG domains are optional metadata filters on the same
/// `ragSources` / `ragChunks` collections. Empty [domains] means no domain
/// restriction (existing RAG behaviour).
class RagSourceFilter {
  const RagSourceFilter({
    this.scope = RagSourceScope.allPublished,
    this.sourceIds = const [],
    this.subject = '',
    this.subjectId = '',
    this.chapter = '',
    this.chapterId = '',
    this.exam = '',
    this.sourceType = '',
    this.examId = '',
    this.topicId = '',
    this.topicIds = const [],
    this.contentType = '',
    this.language = '',
    this.source = '',
    this.year,
    this.difficulty = '',
    this.contentStatus = '',
    this.domains = const [],
    this.onlyPublishedReady = true,
    this.topK = 8,
    this.similarityThreshold = 0.28,
    this.hybrid = true,
  });

  final RagSourceScope scope;

  /// Used when [scope] is [RagSourceScope.selectedSources].
  final List<String> sourceIds;

  final String subject;
  final String subjectId;
  final String chapter;
  final String chapterId;
  final String exam;
  final String sourceType;
  final String examId;
  final String topicId;
  final List<String> topicIds;
  final String contentType;
  final String language;
  final String source;
  final int? year;
  final String difficulty;
  final String contentStatus;
  final List<RagDomain> domains;
  final bool onlyPublishedReady;
  final int topK;
  final double similarityThreshold;
  final bool hybrid;

  static const RagSourceFilter allPublished = RagSourceFilter();

  factory RagSourceFilter.one(String sourceId) {
    return RagSourceFilter(
      scope: RagSourceScope.selectedSources,
      sourceIds: [sourceId],
    );
  }

  factory RagSourceFilter.many(List<String> sourceIds) {
    return RagSourceFilter(
      scope: RagSourceScope.selectedSources,
      sourceIds: sourceIds,
    );
  }

  factory RagSourceFilter.forSubject({
    String subject = '',
    String subjectId = '',
    String chapter = '',
    String chapterId = '',
  }) {
    return RagSourceFilter(
      scope: RagSourceScope.subjectChapter,
      subject: subject,
      subjectId: subjectId,
      chapter: chapter,
      chapterId: chapterId,
    );
  }

  factory RagSourceFilter.forDomain(
    RagDomain domain, {
    String examId = '',
    String subjectId = '',
    String chapterId = '',
    String topicId = '',
  }) {
    return RagSourceFilter(
      domains: [domain],
      examId: examId,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      scope: subjectId.isNotEmpty || chapterId.isNotEmpty
          ? RagSourceScope.subjectChapter
          : RagSourceScope.allPublished,
    );
  }

  RagSourceFilter copyWith({
    RagSourceScope? scope,
    List<String>? sourceIds,
    String? subject,
    String? subjectId,
    String? chapter,
    String? chapterId,
    String? exam,
    String? sourceType,
    String? examId,
    String? topicId,
    List<String>? topicIds,
    String? contentType,
    String? language,
    String? source,
    int? year,
    String? difficulty,
    String? contentStatus,
    List<RagDomain>? domains,
    bool? onlyPublishedReady,
    int? topK,
    double? similarityThreshold,
    bool? hybrid,
  }) {
    return RagSourceFilter(
      scope: scope ?? this.scope,
      sourceIds: sourceIds ?? this.sourceIds,
      subject: subject ?? this.subject,
      subjectId: subjectId ?? this.subjectId,
      chapter: chapter ?? this.chapter,
      chapterId: chapterId ?? this.chapterId,
      exam: exam ?? this.exam,
      sourceType: sourceType ?? this.sourceType,
      examId: examId ?? this.examId,
      topicId: topicId ?? this.topicId,
      topicIds: topicIds ?? this.topicIds,
      contentType: contentType ?? this.contentType,
      language: language ?? this.language,
      source: source ?? this.source,
      year: year ?? this.year,
      difficulty: difficulty ?? this.difficulty,
      contentStatus: contentStatus ?? this.contentStatus,
      domains: domains ?? this.domains,
      onlyPublishedReady: onlyPublishedReady ?? this.onlyPublishedReady,
      topK: topK ?? this.topK,
      similarityThreshold: similarityThreshold ?? this.similarityThreshold,
      hybrid: hybrid ?? this.hybrid,
    );
  }
}

bool _topicMatches(String topicId, String chapterId, RagSourceFilter filter) {
  final wanted = <String>{
    if (filter.topicId.trim().isNotEmpty) filter.topicId.trim(),
    ...filter.topicIds.where((id) => id.trim().isNotEmpty),
  };
  if (wanted.isEmpty) return true;
  return wanted.contains(topicId) ||
      (topicId.isEmpty && wanted.contains(chapterId));
}

bool _languageMatches(String item, String wanted) {
  if (wanted.trim().isEmpty) return true;
  final a = item.trim().toLowerCase();
  final b = wanted.trim().toLowerCase();
  if (a.isEmpty) return true;
  return a == b || a.startsWith(b) || b.startsWith(a);
}

/// Source-level Multi-RAG / content-index metadata filter.
bool matchesRagSourceMetadata(RagSource source, RagSourceFilter filter) {
  if (filter.examId.trim().isNotEmpty &&
      source.examId.isNotEmpty &&
      source.examId != filter.examId) {
    return false;
  }
  if (filter.topicId.trim().isNotEmpty || filter.topicIds.isNotEmpty) {
    if (!_topicMatches(source.topicId, source.chapterId, filter)) {
      return false;
    }
  }
  if (filter.contentType.trim().isNotEmpty) {
    final type = filter.contentType.trim();
    final sourceType = ragSourceTypeToString(source.sourceType);
    if (source.contentType != type && sourceType != type) {
      return false;
    }
  }
  if (!_languageMatches(source.language, filter.language)) return false;
  if (filter.source.trim().isNotEmpty &&
      source.source.trim().toLowerCase() != filter.source.trim().toLowerCase()) {
    return false;
  }
  if (filter.year != null && source.year != null && source.year != filter.year) {
    return false;
  }
  if (filter.difficulty.trim().isNotEmpty &&
      source.difficulty.trim().toLowerCase() !=
          filter.difficulty.trim().toLowerCase()) {
    return false;
  }
  if (filter.contentStatus.trim().isNotEmpty &&
      source.contentStatus.trim().isNotEmpty &&
      source.contentStatus.trim().toLowerCase() !=
          filter.contentStatus.trim().toLowerCase()) {
    return false;
  }
  if (!ragDomainIsAllowed(source.domain, filter.domains)) return false;
  return true;
}

/// Chunk-level Multi-RAG / content-index metadata filter.
bool matchesRagChunkMetadata(RagChunk chunk, RagSourceFilter filter) {
  if (filter.examId.trim().isNotEmpty &&
      chunk.examId.isNotEmpty &&
      chunk.examId != filter.examId) {
    return false;
  }
  if (filter.subjectId.trim().isNotEmpty &&
      chunk.subjectId.isNotEmpty &&
      chunk.subjectId != filter.subjectId) {
    return false;
  }
  if (filter.chapterId.trim().isNotEmpty &&
      chunk.chapterId.isNotEmpty &&
      chunk.chapterId != filter.chapterId &&
      chunk.topicId != filter.chapterId) {
    return false;
  }
  if (filter.topicId.trim().isNotEmpty || filter.topicIds.isNotEmpty) {
    if (!_topicMatches(chunk.topicId, chunk.chapterId, filter)) {
      return false;
    }
  }
  if (filter.contentType.trim().isNotEmpty &&
      chunk.contentType.isNotEmpty &&
      chunk.contentType != filter.contentType) {
    return false;
  }
  if (!_languageMatches(chunk.language, filter.language)) return false;
  if (filter.source.trim().isNotEmpty &&
      chunk.source.trim().toLowerCase() != filter.source.trim().toLowerCase()) {
    return false;
  }
  if (filter.year != null && chunk.year != null && chunk.year != filter.year) {
    return false;
  }
  if (filter.difficulty.trim().isNotEmpty &&
      chunk.difficulty.trim().isNotEmpty &&
      chunk.difficulty.trim().toLowerCase() !=
          filter.difficulty.trim().toLowerCase()) {
    return false;
  }
  if (filter.contentStatus.trim().isNotEmpty &&
      chunk.status.trim().isNotEmpty &&
      chunk.status.trim().toLowerCase() !=
          filter.contentStatus.trim().toLowerCase()) {
    return false;
  }
  if (!ragDomainIsAllowed(chunk.domain, filter.domains)) return false;
  return true;
}
