import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// One embedded chunk at `ragChunks/{chunkId}`.
class RagChunk {
  const RagChunk({
    required this.id,
    required this.sourceId,
    required this.sourceTitle,
    required this.subject,
    required this.chapter,
    required this.text,
    required this.embedding,
    required this.language,
    required this.sourceType,
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
    this.noteId = '',
    this.contentType = '',
    this.exam = kMpscDefaultExam,
    this.examId = '',
    this.source = '',
    this.year,
    this.difficulty = '',
    this.status = '',
    this.ragDomain = '',
    this.pageNumber,
    this.chunkIndex = 0,
    this.published = false,
    this.contentHash = '',
    this.keywords = const [],
  });

  final String id;
  final String sourceId;
  final String sourceTitle;
  final String subject;
  final String subjectId;
  final String chapter;
  final String chapterId;
  final String topicId;
  final String noteId;
  final String contentType;
  final String exam;
  final String examId;
  final String source;
  final int? year;
  final String difficulty;

  /// Content workflow (`published`, `draft`, …) — not RAG processing status.
  final String status;
  final String ragDomain;

  /// 1-based PDF page index when extraction observed a real page. Null otherwise.
  final int? pageNumber;
  final int chunkIndex;
  final String text;
  final List<double> embedding;
  final String language;
  final String sourceType;
  final bool published;
  final String contentHash;
  final List<String> keywords;

  /// Logical Multi-RAG domain, inferred for legacy rows that omit [ragDomain].
  RagDomain get domain => inferRagDomain(
        ragDomain: ragDomain,
        contentType: contentType,
        sourceType: sourceType,
      );

  factory RagChunk.fromMap(Map<String, dynamic> map, String id) {
    return RagChunk(
      id: id,
      sourceId: map['sourceId'] as String? ?? '',
      sourceTitle: map['sourceTitle'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      subjectId: map['subjectId'] as String? ?? '',
      chapter: map['chapter'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      topicId: map['topicId'] as String? ?? '',
      noteId: map['noteId'] as String? ?? '',
      contentType: map['contentType'] as String? ?? '',
      exam: (map['exam'] as String?)?.trim().isNotEmpty == true
          ? (map['exam'] as String).trim()
          : kMpscDefaultExam,
      examId: map['examId'] as String? ?? '',
      source: map['source'] as String? ?? '',
      year: _yearFrom(map['year']),
      difficulty: map['difficulty'] as String? ?? '',
      status: map['status'] as String? ?? '',
      ragDomain: map['ragDomain'] as String? ?? '',
      pageNumber: _pageFrom(map['pageNumber'] ?? map['page']),
      chunkIndex: asInt(map['chunkIndex']),
      text: map['text'] as String? ?? map['chunkText'] as String? ?? '',
      embedding: parseRagEmbedding(map),
      language: map['language'] as String? ?? '',
      sourceType: map['sourceType'] as String? ?? 'pdf',
      published: asBool(map['published'], defaultValue: false),
      contentHash: map['contentHash'] as String? ?? '',
      keywords: asStringList(map['keywords']),
    );
  }

  Map<String, dynamic> toMap({bool includeVectorValue = true}) {
    final values = embedding.map((e) => e.toDouble()).toList(growable: false);
    final map = <String, dynamic>{
      'sourceId': sourceId,
      'sourceTitle': sourceTitle,
      'subject': subject,
      'subjectId': subjectId,
      'chapter': chapter,
      'chapterId': chapterId,
      'topicId': topicId,
      'noteId': noteId,
      'contentType': contentType,
      'exam': exam,
      'examId': examId,
      'source': source,
      'year': year,
      'difficulty': difficulty,
      'status': status,
      'ragDomain': ragDomain.isNotEmpty ? ragDomain : ragDomainToString(domain),
      'pageNumber': pageNumber,
      'chunkIndex': chunkIndex,
      'text': text,
      'chunkText': text,
      'embeddingValues': values,
      'language': language,
      'sourceType': sourceType,
      'published': published,
      'contentHash': contentHash,
      'keywords': keywords,
      'searchText': text.toLowerCase(),
    };
    if (includeVectorValue && values.isNotEmpty) {
      map['embedding'] = VectorValue(values);
    }
    return map;
  }
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

int? _pageFrom(dynamic value) {
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

/// Reads either a Firestore [VectorValue] or a plain list of numbers.
List<double> parseRagEmbedding(Map<String, dynamic> map) {
  final primary = _asDoubles(map['embedding']);
  if (primary.isNotEmpty) return primary;
  return _asDoubles(map['embeddingValues']);
}

List<double> _asDoubles(dynamic value) {
  if (value is VectorValue) {
    return value.toArray().map((e) => e.toDouble()).toList(growable: false);
  }
  if (value is List) {
    final out = <double>[];
    for (final e in value) {
      if (e is num) {
        out.add(e.toDouble());
      } else if (e != null) {
        final parsed = double.tryParse(e.toString());
        if (parsed != null) out.add(parsed);
      }
    }
    return out;
  }
  return const [];
}
