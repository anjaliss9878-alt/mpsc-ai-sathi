import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Exact student-facing line when retrieval does not support the question.
const String kRagInsufficientEvidence =
    'निवडलेल्या स्रोतांमध्ये या प्रश्नाचे पुरेसे संदर्भ उपलब्ध नाहीत.';

const String kRagNoPyqFound =
    'निवडलेल्या स्रोतांमध्ये संबंधित PYQ उपलब्ध नाहीत.';

/// Source-grounded citation. Page is included only when extraction observed it.
class RagCitation {
  const RagCitation({
    required this.sourceId,
    required this.subject,
    required this.chapter,
    required this.topic,
    this.pageNumber,
    this.sourceType = '',
    this.examId = '',
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
    this.contentType = '',
    this.language = '',
    this.source = '',
    this.year,
    this.difficulty = '',
    this.status = '',
    this.ragDomain = '',
    this.confidence = 0,
    this.sourceTitle = '',
    this.chunkId = '',
  });

  final String sourceId;
  final String subject;
  final String chapter;
  final String topic;
  final int? pageNumber;
  final String sourceType;
  final String examId;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final String contentType;
  final String language;
  final String source;
  final int? year;
  final String difficulty;
  final String status;
  final String ragDomain;
  final double confidence;
  final String sourceTitle;
  final String chunkId;

  /// Document/chunk locator used in student-facing source refs.
  String get documentRef {
    final parts = <String>[
      if (sourceId.trim().isNotEmpty) sourceId.trim(),
      if (chunkId.trim().isNotEmpty) chunkId.trim(),
    ];
    if (pageNumber != null) parts.add('p$pageNumber');
    return parts.join('#');
  }

  String get resolvedTitle =>
      sourceTitle.trim().isNotEmpty ? sourceTitle.trim() : topic.trim();

  factory RagCitation.fromMap(Map<String, dynamic> map) {
    final page = map['pageNumber'];
    int? pageNumber;
    if (page is num && page.toInt() >= 1) pageNumber = page.toInt();
    final yearRaw = map['year'];
    int? year;
    if (yearRaw is num && yearRaw.toInt() >= 1) year = yearRaw.toInt();
    return RagCitation(
      sourceId: map['sourceId'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      chapter: map['chapter'] as String? ?? '',
      topic: map['topic'] as String? ?? map['sourceTitle'] as String? ?? '',
      pageNumber: pageNumber,
      sourceType: map['sourceType'] as String? ?? '',
      examId: map['examId'] as String? ?? '',
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      topicId: map['topicId'] as String? ?? '',
      contentType: map['contentType'] as String? ?? '',
      language: map['language'] as String? ?? '',
      source: map['source'] as String? ?? '',
      year: year,
      difficulty: map['difficulty'] as String? ?? '',
      status: map['status'] as String? ?? '',
      ragDomain: map['ragDomain'] as String? ?? '',
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      sourceTitle: map['sourceTitle'] as String? ?? '',
      chunkId: map['chunkId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'sourceId': sourceId,
        'subject': subject,
        'chapter': chapter,
        'topic': topic,
        'pageNumber': pageNumber,
        'sourceType': sourceType,
        'examId': examId,
        'subjectId': subjectId,
        'chapterId': chapterId,
        'topicId': topicId,
        'contentType': contentType,
        'language': language,
        'source': source,
        'year': year,
        'difficulty': difficulty,
        'status': status,
        'ragDomain': ragDomain,
        'confidence': confidence,
        'sourceTitle': sourceTitle,
        'chunkId': chunkId,
      };

  /// Subject → Chapter → Topic → Page (omits empty parts and unknown pages).
  String get breadcrumb {
    final parts = <String>[
      if (subject.trim().isNotEmpty) subject.trim(),
      if (chapter.trim().isNotEmpty) chapter.trim(),
      if (topic.trim().isNotEmpty) topic.trim(),
      if (pageNumber != null) 'Page $pageNumber',
    ];
    return parts.join('\n→ ');
  }
}

List<RagCitation> citationsFromMaps(dynamic raw) {
  return asMapList(raw).map(RagCitation.fromMap).toList(growable: false);
}
