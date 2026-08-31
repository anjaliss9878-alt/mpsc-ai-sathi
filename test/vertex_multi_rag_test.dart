import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/multi_rag_result.dart';
import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/multi_rag_context.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';
import 'package:mpsc_combine_ai/rag/rag_router.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/multi_rag_answer_service.dart';
import 'package:mpsc_combine_ai/services/multi_rag_retrieval.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_processing_service.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';

List<double> fakeEmbed(String text) {
  final v = List<double>.filled(kRagEmbeddingDimensions, 0);
  final tokens = ragKeywordTokens(text, limit: 80);
  if (tokens.isEmpty) {
    v[0] = 1;
    return v;
  }
  for (final token in tokens) {
    final h = token.hashCode.abs();
    v[h % kRagEmbeddingDimensions] += 1;
    v[(h ~/ 97) % kRagEmbeddingDimensions] += 0.35;
  }
  var norm = 0.0;
  for (final n in v) {
    norm += n * n;
  }
  norm = math.sqrt(norm);
  if (norm == 0) return v;
  return [for (final n in v) n / norm];
}

class _VertexFakeBackend extends RagBackendClient {
  _VertexFakeBackend({
    this.failVertexEmbed = false,
    this.failVertexLearn = false,
    this.vertexInsufficient = false,
  }) : super(baseUrl: 'http://rag.test');

  final bool failVertexEmbed;
  final bool failVertexLearn;
  final bool vertexInsufficient;
  int vertexEmbedCalls = 0;
  int vertexLearnCalls = 0;
  int embedCalls = 0;
  int learnCalls = 0;
  Map<String, dynamic>? lastLearnBody;

  @override
  Future<List<List<double>>> vertexEmbed({
    required List<String> texts,
    String task = 'document',
  }) async {
    vertexEmbedCalls++;
    if (failVertexEmbed) {
      throw RagException.embedding('Vertex unavailable');
    }
    return [for (final t in texts) fakeEmbed(t)];
  }

  @override
  Future<List<double>> vertexEmbedQuery(String query) async {
    final rows = await vertexEmbed(texts: [query], task: 'query');
    return rows.first;
  }

  @override
  Future<Map<String, dynamic>> vertexLearn(Map<String, dynamic> body) async {
    vertexLearnCalls++;
    lastLearnBody = body;
    if (failVertexLearn) {
      throw RagException.gemini('Vertex unavailable');
    }
    if (vertexInsufficient) {
      return {'insufficient': true, 'answer': '', 'provider': 'vertex'};
    }
    return {
      'insufficient': false,
      'answer': 'Article 14 is equality before law, from the retrieved notes.',
      'chunkIndexes': [0],
      'provider': 'vertex',
    };
  }

  @override
  Future<List<List<double>>> embed({
    required List<String> texts,
    String task = 'document',
  }) async {
    embedCalls++;
    return [for (final t in texts) fakeEmbed(t)];
  }

  @override
  Future<List<double>> embedQuery(String query) async {
    final rows = await embed(texts: [query], task: 'query');
    return rows.first;
  }

  @override
  Future<Map<String, dynamic>> learn(Map<String, dynamic> body) async {
    learnCalls++;
    lastLearnBody = body;
    return {
      'insufficient': false,
      'answer': 'Fallback answer from existing RAG generation.',
      'chunkIndexes': [0],
      'provider': 'existing',
    };
  }
}

void main() {
  late FakeFirebaseFirestore firestore;
  late RagSourceRepository sources;
  late RagChunkRepository chunks;
  late RagProcessingService processing;
  late MultiRagRetrievalService retrieval;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    sources = RagSourceRepository(firestore: firestore);
    chunks = RagChunkRepository(firestore: firestore);
    final backend = _VertexFakeBackend();
    processing = RagProcessingService(
      sources: sources,
      chunks: chunks,
      backend: backend,
      firestore: firestore,
      notes: NotesRepository(firestore: firestore),
      pyqs: PyqRepository(firestore: firestore),
      currentAffairs: CurrentAffairsRepository(firestore: firestore),
    );
    retrieval = MultiRagRetrievalService(
      retrieval: RagRetrievalService(
        sources: sources,
        chunks: chunks,
        backend: backend,
        embedQuery: (q) async => fakeEmbed(q),
      ),
      embedQuery: (q) async => fakeEmbed(q),
    );
  });

  Future<void> seedNotes() async {
    await sources.create(
      RagSource(
        id: 'note1',
        title: 'Article 14 notes',
        subject: 'Polity',
        subjectId: 'pol',
        chapter: 'Fundamental Rights',
        chapterId: 'fr',
        exam: kMpscDefaultExam,
        fileUrl: '',
        uploadedBy: 'admin',
        createdAt: DateTime(2026, 1, 1),
        status: RagSourceStatus.processing,
        published: true,
        sourceType: RagSourceType.pdf,
        language: 'en',
        examId: kDefaultExamId,
        topicId: 'a14',
        contentType: kNotesPdfContentType,
        source: 'Bare Act',
        year: 2024,
        contentStatus: 'published',
        ragDomain: ragDomainToString(RagDomain.notes),
      ),
    );
    final ready = await processing.processSource(
      'note1',
      inlineText:
          'Fundamental Rights. Article 14 equality before law. Equality is a core right.',
    );
    await processing.setPublished(ready, true);
  }

  test('context builder copies source title, content type, topic, chunk ref', () {
    const citation = RagCitation(
      sourceId: 'note1',
      subject: 'Polity',
      chapter: 'FR',
      topic: 'Article 14 notes',
      contentType: kNotesPdfContentType,
      sourceTitle: 'Article 14 notes',
      chunkId: 'note1_0',
      pageNumber: 2,
    );
    expect(citation.resolvedTitle, 'Article 14 notes');
    expect(citation.contentType, kNotesPdfContentType);
    expect(citation.topic, 'Article 14 notes');
    expect(citation.documentRef, 'note1#note1_0#p2');

    const builder = MultiRagContextBuilder();
    final empty = builder.build(
      const MultiRagResult(
        query: 'x',
        plan: RagRoutePlan(domains: [RagDomain.notes], confidence: 1),
        hits: [],
        confidence: 0,
      ),
    );
    expect(empty.hasEvidence, isFalse);
    expect(empty.chunks, isEmpty);
  });

  test('Vertex embed + generate with citations from retrieved chunks', () async {
    await seedNotes();
    final backend = _VertexFakeBackend();
    final service = MultiRagAnswerService(
      retrieval: retrieval,
      backend: backend,
    );
    final answer = await service.answer(
      const MultiRagQuery(query: 'Fundamental Rights explain'),
    );
    expect(answer.insufficient, isFalse);
    expect(answer.provider, MultiRagProvider.vertex);
    expect(answer.embedProvider, MultiRagProvider.vertex);
    expect(answer.fellBack, isFalse);
    expect(backend.vertexEmbedCalls, 1);
    expect(backend.vertexLearnCalls, 1);
    expect(backend.learnCalls, 0);
    expect(answer.citations, isNotEmpty);
    final c = answer.citations.first;
    expect(c.resolvedTitle, isNotEmpty);
    expect(c.contentType, kNotesPdfContentType);
    expect(c.topic, isNotEmpty);
    expect(c.chunkId, isNotEmpty);
    expect(c.documentRef, isNotEmpty);
    expect(c.examId, kDefaultExamId);
    final chunks = backend.lastLearnBody!['chunks'] as List;
    expect(chunks, isNotEmpty);
    expect(chunks.first['sourceTitle'], isNotEmpty);
    expect(chunks.first['contentType'], kNotesPdfContentType);
    expect(chunks.first['documentRef'], isNotEmpty);
  });

  test('Vertex embed failure falls back to existing embed + generate', () async {
    await seedNotes();
    final backend = _VertexFakeBackend(failVertexEmbed: true, failVertexLearn: true);
    final service = MultiRagAnswerService(
      retrieval: retrieval,
      backend: backend,
    );
    final answer = await service.answer(
      const MultiRagQuery(query: 'Fundamental Rights explain'),
    );
    expect(answer.insufficient, isFalse);
    expect(answer.provider, MultiRagProvider.existingRag);
    expect(answer.embedProvider, MultiRagProvider.existingRag);
    expect(answer.fellBack, isTrue);
    expect(backend.embedCalls, greaterThan(0));
    expect(backend.learnCalls, 1);
    expect(answer.markdown, contains('Fallback'));
    expect(answer.citations, isNotEmpty);
  });

  test('Vertex generate failure falls back to existing learn', () async {
    await seedNotes();
    final backend = _VertexFakeBackend(failVertexLearn: true);
    final service = MultiRagAnswerService(
      retrieval: retrieval,
      backend: backend,
    );
    final answer = await service.answer(
      const MultiRagQuery(query: 'Fundamental Rights explain'),
    );
    expect(answer.provider, MultiRagProvider.existingRag);
    expect(answer.embedProvider, MultiRagProvider.vertex);
    expect(answer.fellBack, isTrue);
    expect(backend.vertexLearnCalls, 1);
    expect(backend.learnCalls, 1);
    expect(answer.citations.first.contentType, kNotesPdfContentType);
  });

  test('no retrieved chunks: never calls generation and does not fabricate', () async {
    await seedNotes();
    final backend = _VertexFakeBackend();
    final service = MultiRagAnswerService(
      retrieval: retrieval,
      backend: backend,
    );
    final answer = await service.answer(
      const MultiRagQuery(
        query: 'xyzzyqwq quantum cryptography unexplained',
        similarityThreshold: 0.99,
        hybrid: false,
      ),
    );
    expect(answer.insufficient, isTrue);
    expect(answer.markdown, kRagInsufficientEvidence);
    expect(answer.citations, isEmpty);
    expect(backend.vertexLearnCalls, 0);
    expect(backend.learnCalls, 0);
  });

  test('Vertex insufficient payload is not replaced with invented context', () async {
    await seedNotes();
    final backend = _VertexFakeBackend(vertexInsufficient: true);
    final service = MultiRagAnswerService(
      retrieval: retrieval,
      backend: backend,
    );
    final answer = await service.answer(
      const MultiRagQuery(query: 'Fundamental Rights explain'),
    );
    expect(answer.insufficient, isTrue);
    expect(answer.markdown, kRagInsufficientEvidence);
    expect(answer.citations, isEmpty);
    expect(backend.learnCalls, 0);
  });

  test('empty question fails before Vertex or existing generation', () async {
    final backend = _VertexFakeBackend();
    final service = MultiRagAnswerService(
      retrieval: retrieval,
      backend: backend,
    );
    await expectLater(
      service.answer(const MultiRagQuery(query: '  ')),
      throwsA(
        isA<RagException>().having((e) => e.code, 'code', RagException.emptyQuery),
      ),
    );
    expect(backend.vertexEmbedCalls, 0);
    expect(backend.learnCalls, 0);
  });
}
