import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/multi_rag_result.dart';
import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/multi_rag_retrieval.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_grounded_learning_service.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';
import 'package:mpsc_combine_ai/services/student_rag_context.dart';

List<double> _embed(String text) {
  final v = List<double>.filled(kRagEmbeddingDimensions, 0);
  final tokens = ragKeywordTokens(text, limit: 40);
  if (tokens.isEmpty) {
    v[0] = 1;
    return v;
  }
  for (final token in tokens) {
    v[token.hashCode.abs() % kRagEmbeddingDimensions] += 1;
  }
  var norm = 0.0;
  for (final n in v) {
    norm += n * n;
  }
  norm = math.sqrt(norm);
  if (norm == 0) return v;
  return [for (final n in v) n / norm];
}

class _CountChunks extends RagChunkRepository {
  _CountChunks(FakeFirebaseFirestore firestore) : super(firestore: firestore);

  int publishedReads = 0;
  int sourceReads = 0;

  @override
  Future<List<RagChunk>> getPublished({
    List<String> sourceIds = const [],
    String subjectId = '',
    String chapterId = '',
  }) async {
    publishedReads++;
    return super.getPublished(
      sourceIds: sourceIds,
      subjectId: subjectId,
      chapterId: chapterId,
    );
  }

  @override
  Future<List<RagChunk>> getForSource(String sourceId) async {
    sourceReads++;
    return super.getForSource(sourceId);
  }
}

class _ServerBackend extends RagBackendClient {
  _ServerBackend({
    this.hits = const [],
    this.throwOnRetrieve = false,
  }) : super(baseUrl: 'http://rag.test');

  List<Map<String, dynamic>> hits;
  bool throwOnRetrieve;
  int retrieveCalls = 0;
  int embedCalls = 0;

  @override
  Future<List<List<double>>> embed({
    required List<String> texts,
    String task = 'document',
  }) async {
    embedCalls++;
    return [for (final t in texts) _embed(t)];
  }

  @override
  Future<RagServerRetrieveResult?> retrieveChunks({
    required String query,
    String examId = '',
    String subjectId = '',
    String chapterId = '',
    String topicId = '',
    List<String> domains = const [],
    List<String> sourceIds = const [],
    int topK = 8,
    double similarityThreshold = 0.05,
    bool hybrid = true,
  }) async {
    retrieveCalls++;
    if (throwOnRetrieve) throw StateError('Vertex/vector down');
    var selected = hits;
    if (examId.isNotEmpty) {
      selected = [
        for (final h in selected)
          if ((h['chunk'] as Map)['examId'] == examId) h,
      ];
    }
    if (topicId.isNotEmpty) {
      selected = [
        for (final h in selected)
          if ((h['chunk'] as Map)['topicId'] == topicId) h,
      ];
    }
    if (selected.length > topK) selected = selected.take(topK).toList();
    return RagServerRetrieveResult(hits: selected);
  }
}

Map<String, dynamic> _hitMap({
  required String id,
  required String text,
  String sourceId = 's1',
  String examId = kDefaultExamId,
  String topicId = 'a14',
  String subjectId = 'pol',
  String chapterId = 'fr',
  String ragDomain = 'notes_rag',
  String contentType = kNotesPdfContentType,
  bool published = true,
  double score = 0.9,
}) {
  return {
    'score': score,
    'vectorScore': score,
    'keywordScore': 0.4,
    'domain': ragDomain,
    'chunk': {
      'id': id,
      'sourceId': sourceId,
      'sourceTitle': text,
      'subject': 'Polity',
      'subjectId': subjectId,
      'chapter': 'FR',
      'chapterId': chapterId,
      'topicId': topicId,
      'contentType': contentType,
      'examId': examId,
      'ragDomain': ragDomain,
      'text': text,
      'published': published,
      'language': 'en',
      'sourceType': 'pdf',
    },
  };
}

RagSource _source({
  required String id,
  bool published = true,
  RagSourceStatus status = RagSourceStatus.ready,
}) {
  return RagSource(
    id: id,
    title: id,
    subject: 'Polity',
    chapter: 'FR',
    exam: kMpscDefaultExam,
    fileUrl: '',
    uploadedBy: 'admin',
    createdAt: DateTime(2026, 1, 1),
    status: status,
    published: published,
    examId: kDefaultExamId,
    subjectId: 'pol',
    chapterId: 'fr',
  );
}

void main() {
  test('student path does not download the full ragChunks collection', () async {
    final firestore = FakeFirebaseFirestore();
    final sources = RagSourceRepository(firestore: firestore);
    final chunks = _CountChunks(firestore);
    await sources.create(_source(id: 's1'));
    await chunks.replaceSourceChunks(
      sourceId: 's1',
      chunks: [
        RagChunk(
          id: 's1_0',
          sourceId: 's1',
          sourceTitle: 'Article 14',
          subject: 'Polity',
          chapter: 'FR',
          text: 'noise chunk that must not be downloaded',
          embedding: _embed('noise'),
          language: 'en',
          sourceType: 'pdf',
          published: true,
        ),
      ],
    );
    final backend = _ServerBackend(
      hits: [
        _hitMap(id: 's1_live', text: 'Article 14 equality before law'),
      ],
    );
    final retrieval = RagRetrievalService(
      sources: sources,
      chunks: chunks,
      backend: backend,
    );
    final hits = await retrieval.retrieve(query: 'Article 14');
    expect(backend.retrieveCalls, 1);
    expect(chunks.publishedReads, 0);
    expect(chunks.sourceReads, 0);
    expect(hits, hasLength(1));
    expect(hits.single.chunk.text, contains('Article 14'));
    expect(hits.single.chunk.embedding, isEmpty);
  });

  test('top-K retrieval works from the server payload', () async {
    final backend = _ServerBackend(
      hits: [
        _hitMap(id: 'a', text: 'first', score: 0.9),
        _hitMap(id: 'b', text: 'second', score: 0.8),
        _hitMap(id: 'c', text: 'third', score: 0.7),
      ],
    );
    final retrieval = RagRetrievalService(
      sources: RagSourceRepository(firestore: FakeFirebaseFirestore()),
      chunks: RagChunkRepository(firestore: FakeFirebaseFirestore()),
      backend: backend,
    );
    final hits = await retrieval.retrieve(
      query: 'Article 14',
      filter: const RagSourceFilter(topK: 2),
    );
    expect(hits.map((h) => h.chunk.id), ['a', 'b']);
  });

  test('metadata filters drop the wrong exam and topic', () async {
    final backend = _ServerBackend(
      hits: [
        _hitMap(id: 'upsc', text: 'Article 14', examId: 'upsc'),
        _hitMap(id: 'a19', text: 'Article 14', topicId: 'a19'),
        _hitMap(id: 'ok', text: 'Article 14 equality', topicId: 'a14'),
      ],
    );
    final retrieval = RagRetrievalService(
      sources: RagSourceRepository(firestore: FakeFirebaseFirestore()),
      chunks: RagChunkRepository(firestore: FakeFirebaseFirestore()),
      backend: backend,
    );
    final hits = await retrieval.retrieve(
      query: 'Article 14',
      filter: const RagSourceFilter(
        examId: kDefaultExamId,
        topicId: 'a14',
      ),
    );
    expect(hits.map((h) => h.chunk.id), ['ok']);
  });

  test('unpublished chunks never come back from the server path', () async {
    final backend = _ServerBackend(
      hits: [
        _hitMap(id: 'draft', text: 'secret draft', published: false, score: 0.99),
        _hitMap(id: 'live', text: 'published Article 14', published: true),
      ],
    );
    final retrieval = RagRetrievalService(
      sources: RagSourceRepository(firestore: FakeFirebaseFirestore()),
      chunks: RagChunkRepository(firestore: FakeFirebaseFirestore()),
      backend: backend,
    );
    final hits = await retrieval.retrieve(query: 'Article 14');
    expect(hits.map((h) => h.chunk.id), ['live']);
    expect(hits.every((h) => h.chunk.published), isTrue);
  });

  test('Vertex/vector failure falls back to Gemini local retrieval', () async {
    final firestore = FakeFirebaseFirestore();
    final sources = RagSourceRepository(firestore: firestore);
    final chunks = _CountChunks(firestore);
    await sources.create(_source(id: 's1'));
    await chunks.replaceSourceChunks(
      sourceId: 's1',
      chunks: [
        RagChunk(
          id: 's1_0',
          sourceId: 's1',
          sourceTitle: 'Article 14',
          subject: 'Polity',
          chapter: 'FR',
          text: 'Article 14 equality before law',
          embedding: _embed('Article 14 equality before law'),
          language: 'en',
          sourceType: 'pdf',
          published: true,
          examId: kDefaultExamId,
          subjectId: 'pol',
          chapterId: 'fr',
        ),
      ],
    );
    final backend = _ServerBackend(throwOnRetrieve: true);
    final retrieval = RagRetrievalService(
      sources: sources,
      chunks: chunks,
      backend: backend,
    );
    final hits = await retrieval.retrieve(query: 'Article 14 equality');
    expect(backend.retrieveCalls, 1);
    expect(backend.embedCalls, greaterThan(0));
    expect(chunks.publishedReads, greaterThan(0));
    expect(hits, isNotEmpty);
  });

  test('empty server retrieval is insufficient evidence, not a corpus download',
      () async {
    final chunks = _CountChunks(FakeFirebaseFirestore());
    final backend = _ServerBackend(hits: const []);
    final retrieval = RagRetrievalService(
      sources: RagSourceRepository(firestore: FakeFirebaseFirestore()),
      chunks: chunks,
      backend: backend,
    );
    final hits = await retrieval.retrieve(query: 'unknown topic');
    expect(hits, isEmpty);
    expect(chunks.publishedReads, 0);
  });

  test('Student A cannot retrieve Student B performance via Multi-RAG', () async {
    final backend = _ServerBackend(
      hits: [
        _hitMap(id: 'notes', text: 'Article 14 notes'),
        _hitMap(
          id: 'b-secret',
          text: 'Student B secret weakness 12%',
          sourceId: 'student_performance',
          ragDomain: 'student_performance_rag',
          contentType: kStudentPerformanceContentType,
        ),
      ],
    );
    final retrieval = RagRetrievalService(
      sources: RagSourceRepository(firestore: FakeFirebaseFirestore()),
      chunks: RagChunkRepository(firestore: FakeFirebaseFirestore()),
      backend: backend,
    );
    final multi = MultiRagRetrievalService(retrieval: retrieval);
    final result = await multi.retrieve(
      const MultiRagQuery(
        query: 'Article 14',
        domains: [RagDomain.notes, RagDomain.studentPerformance],
        performance: [
          StudentPerformanceRecord(
            label: 'Student A weakness',
            topicId: 'a14',
            scorePercent: 20,
          ),
        ],
      ),
    );
    expect(
      result.hits.where((h) => h.domain == RagDomain.studentPerformance),
      hasLength(1),
    );
    expect(
      result.hits
          .where((h) => h.domain == RagDomain.studentPerformance)
          .single
          .chunk
          .text,
      contains('Student A weakness'),
    );
    expect(
      result.hits.any((h) => h.chunk.text.contains('Student B')),
      isFalse,
    );
  });

  test('StudentRagContext still blocks cross-uid performance loads', () async {
    final ctx = StudentRagContextService();
    await expectLater(
      ctx.load(uid: 'alice', requesterUid: 'bob'),
      throwsA(isA<StudentRagAccessException>()),
    );
  });

  test('empty retrieval + grounded answer stays insufficient-evidence JSON',
      () async {
    final grounded = RagGroundedLearningService(
      retrieval: RagRetrievalService(
        sources: RagSourceRepository(firestore: FakeFirebaseFirestore()),
        chunks: RagChunkRepository(firestore: FakeFirebaseFirestore()),
        backend: _ServerBackend(hits: const []),
      ),
    );
    final answer = await grounded.answer(question: 'unknown?');
    expect(answer.insufficient, isTrue);
    expect(answer.markdown, kRagInsufficientEvidence);
    expect(answer.citations, isEmpty);
  });
}
