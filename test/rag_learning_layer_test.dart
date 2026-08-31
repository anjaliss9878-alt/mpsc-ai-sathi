import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/chat_message.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_grounded_learning_service.dart';
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

class _LearnBackend extends RagBackendClient {
  _LearnBackend({this.failGemini = false}) : super(baseUrl: 'http://rag.test');

  final bool failGemini;
  int learnCalls = 0;
  Map<String, dynamic>? lastBody;

  @override
  Future<Map<String, dynamic>> learn(Map<String, dynamic> body) async {
    learnCalls++;
    lastBody = body;
    if (failGemini) {
      throw RagException.gemini('synthetic Gemini failure');
    }
    final mode = '${body['mode'] ?? 'answer'}';
    final chunks = (body['chunks'] as List?) ?? const [];
    if (chunks.isEmpty) return {'insufficient': true};
    switch (mode) {
      case 'summary':
        return {
          'insufficient': false,
          'detailed': 'तपशीलवार सारांश: मूलभूत अधिकार.',
          'shortNotes': 'संक्षिप्त टीप.',
          'fiveMinuteRevision': '५ मिनिटांचे पुनरावलोकन.',
          'importantFacts': ['कलम ३२'],
          'examPoints': ['MPSC मध्ये वारंवार'],
          'commonMistakes': ['कलम ३२ आणि २२ मिसळणे'],
          'chunkIndexes': [0],
        };
      case 'mcq':
        return {
          'insufficient': false,
          'questions': [
            {
              'question': 'कलम ३२ कशाशी संबंधित आहे?',
              'options': ['संवैधानिक उपाय', 'संपत्ती', 'मतदान', 'कर'],
              'correctIndex': 0,
              'explanation': 'स्रोतानुसार कलम ३२ संवैधानिक उपायांशी संबंधित आहे.',
              'difficulty': 'Easy',
              'topic': 'मूलभूत अधिकार',
              'chunkIndexes': [0],
            },
          ],
        };
      case 'flashcards':
        return {
          'insufficient': false,
          'cards': [
            {
              'front': 'कलम 32 कशाशी संबंधित आहे?',
              'back': 'संवैधानिक उपाय',
              'explanation': 'स्रोतातील स्पष्टीकरण',
              'chunkIndexes': [0],
            },
          ],
        };
      case 'revision':
        return {
          'insufficient': false,
          'keyFacts': ['मूलभूत अधिकार न्याय्य आहेत'],
          'terms': ['संवैधानिक उपाय'],
          'dates': <String>[],
          'articles': ['कलम ३२'],
          'committees': <String>[],
          'personalities': <String>[],
          'examTraps': ['कलम क्रमांक चुकवणे'],
          'chunkIndexes': [0],
        };
      case 'memory':
        return {
          'insufficient': false,
          'tricks': [
            {
              'trick': '३२ = ३+२ उपाय (स्रोतातील अर्थ न बदलता)',
              'chunkIndexes': [0],
            },
          ],
        };
      default:
        return {
          'insufficient': false,
          'answer': 'मूलभूत अधिकार हे न्याय्य अधिकार आहेत. कलम ३२ संवैधानिक उपाय देते.',
          'chunkIndexes': [0],
          'pageNumber': 99,
        };
    }
  }

  @override
  Future<List<double>> embedQuery(String query) async => fakeEmbed(query);
}

class _PermBackend extends RagBackendClient {
  _PermBackend() : super(baseUrl: 'http://rag.test');

  @override
  Future<List<double>> embedQuery(String query) async {
    throw RagException.permission('permission-denied');
  }
}

Future<void> _seedCorpus({
  required RagSourceRepository sources,
  required RagChunkRepository chunks,
}) async {
  await sources.create(
    RagSource(
      id: 'polity',
      title: 'Article 32',
      subject: 'Polity',
      subjectId: 'pol',
      chapter: 'Fundamental Rights',
      chapterId: 'fr',
      exam: kMpscDefaultExam,
      fileUrl: '',
      uploadedBy: 'admin',
      createdAt: DateTime(2026, 1, 1),
      status: RagSourceStatus.ready,
      published: true,
    ),
  );
  await sources.create(
    RagSource(
      id: 'geo',
      title: 'Indian Climate',
      subject: 'Geography',
      subjectId: 'geo',
      chapter: 'मान्सून',
      chapterId: 'mon',
      exam: kMpscDefaultExam,
      fileUrl: '',
      uploadedBy: 'admin',
      createdAt: DateTime(2026, 1, 1),
      status: RagSourceStatus.ready,
      published: true,
    ),
  );
  const rights =
      'भारतीय संविधानातील मूलभूत अधिकार न्याय्य आहेत. कलम ३२ संवैधानिक उपाय देते. Article 32.';
  const monsoon = 'मान्सून हा भारताच्या हवामानाचा मुख्य आधार आहे. पावसाळी हवामान.';
  await chunks.replaceSourceChunks(
    sourceId: 'polity',
    chunks: [
      RagChunk(
        id: 'c-rights',
        sourceId: 'polity',
        sourceTitle: 'Article 32',
        subject: 'Polity',
        subjectId: 'pol',
        chapter: 'Fundamental Rights',
        chapterId: 'fr',
        text: rights,
        embedding: fakeEmbed(rights),
        language: 'mr',
        sourceType: 'pdf',
        pageNumber: 24,
        published: true,
      ),
    ],
  );
  await chunks.replaceSourceChunks(
    sourceId: 'geo',
    chunks: [
      RagChunk(
        id: 'c-monsoon',
        sourceId: 'geo',
        sourceTitle: 'Indian Climate',
        subject: 'Geography',
        subjectId: 'geo',
        chapter: 'मान्सून',
        chapterId: 'mon',
        text: monsoon,
        embedding: fakeEmbed(monsoon),
        language: 'mr',
        sourceType: 'pdf',
        pageNumber: 8,
        published: true,
      ),
    ],
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late RagSourceRepository sources;
  late RagChunkRepository chunks;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    sources = RagSourceRepository(firestore: firestore);
    chunks = RagChunkRepository(firestore: firestore);
  });

  test('ChatMessage citations round-trip and omit unknown pages', () {
    final cited = ChatMessage(
      role: ChatRole.assistant,
      content: 'उत्तर',
      timestamp: DateTime(2026, 8, 20),
      citations: [
        RagCitation(
          sourceId: 's1',
          subject: 'Polity',
          chapter: 'Fundamental Rights',
          topic: 'Article 32',
          pageNumber: 24,
        ),
      ],
    );
    final restored = ChatMessage.fromMap(cited.toMap(), 'm1');
    expect(restored.citations.single.breadcrumb, contains('Polity'));
    expect(restored.citations.single.breadcrumb, contains('Page 24'));
    const noPage = RagCitation(
      sourceId: 's1',
      subject: 'History',
      chapter: '1857',
      topic: 'उठाव',
    );
    expect(noPage.breadcrumb.contains('Page'), isFalse);
  });

  test('empty question fails before retrieval or Gemini', () async {
    final backend = _LearnBackend();
    final service = RagGroundedLearningService(
      retrieval: RagRetrievalService(
        sources: sources,
        chunks: chunks,
        backend: backend,
        embedQuery: (q) async => fakeEmbed(q),
      ),
      backend: backend,
      loadPublishedPyqs: () async => const [],
    );
    await expectLater(
      service.answer(question: '   '),
      throwsA(isA<RagException>().having((e) => e.code, 'code', RagException.emptyQuery)),
    );
    expect(backend.learnCalls, 0);
  });

  test('no relevant source: insufficient Marathi line and no Gemini call', () async {
    await _seedCorpus(sources: sources, chunks: chunks);
    final backend = _LearnBackend();
    final service = RagGroundedLearningService(
      retrieval: RagRetrievalService(
        sources: sources,
        chunks: chunks,
        backend: backend,
        embedQuery: (q) async => fakeEmbed(q),
      ),
      backend: backend,
      loadPublishedPyqs: () async => const [],
    );
    final reply = await service.answer(
      question: 'xyzzyqwq quantum cryptography',
      filter: const RagSourceFilter(similarityThreshold: 0.55, hybrid: false),
    );
    expect(reply.insufficient, isTrue);
    expect(reply.markdown, kRagInsufficientEvidence);
    expect(reply.citations, isEmpty);
    expect(backend.learnCalls, 0);
  });

  test('RAG → Gemini → Marathi answer + citation from chunk metadata not Gemini page', () async {
    await _seedCorpus(sources: sources, chunks: chunks);
    String? lastQuery;
    final backend = _LearnBackend();
    final service = RagGroundedLearningService(
      retrieval: RagRetrievalService(
        sources: sources,
        chunks: chunks,
        backend: backend,
        embedQuery: (q) async {
          lastQuery = q;
          return fakeEmbed(q);
        },
      ),
      backend: backend,
      loadPublishedPyqs: () async => const [],
    );
    final reply = await service.answer(
      question: 'मूलभूत अधिकार सोप्या भाषेत समजावून सांग.',
      filter: const RagSourceFilter(similarityThreshold: 0.05, hybrid: false),
    );
    expect(reply.insufficient, isFalse);
    expect(reply.markdown, contains('कलम'));
    expect(backend.learnCalls, 1);
    expect(lastQuery, contains('मूलभूत अधिकार'));
    expect(reply.citations, isNotEmpty);
    final c = reply.citations.first;
    expect(c.subject, 'Polity');
    expect(c.chapter, 'Fundamental Rights');
    expect(c.topic, 'Article 32');
    expect(c.pageNumber, 24);
    expect(c.breadcrumb, contains('Page 24'));
  });

  test('conversation memory expands follow-up retrieval query', () async {
    await _seedCorpus(sources: sources, chunks: chunks);
    String? lastQuery;
    final backend = _LearnBackend();
    final service = RagGroundedLearningService(
      retrieval: RagRetrievalService(
        sources: sources,
        chunks: chunks,
        backend: backend,
        embedQuery: (q) async {
          lastQuery = q;
          return fakeEmbed(q);
        },
      ),
      backend: backend,
      loadPublishedPyqs: () async => const [],
    );
    await service.answer(
      question: 'Why is it important?',
      history: [
        ChatMessage(
          role: ChatRole.user,
          content: 'What is Article 32?',
          timestamp: DateTime(2026, 8, 20),
        ),
        ChatMessage(
          role: ChatRole.assistant,
          content: 'It is a constitutional remedy.',
          timestamp: DateTime(2026, 8, 20, 0, 1),
        ),
      ],
      filter: const RagSourceFilter(similarityThreshold: 0.01, hybrid: false),
    );
    expect(lastQuery, contains('Article 32'));
    expect(lastQuery, contains('Why is it important?'));
  });

  test('multiple selected sources restrict retrieval', () async {
    await _seedCorpus(sources: sources, chunks: chunks);
    final backend = _LearnBackend();
    final retrieval = RagRetrievalService(
      sources: sources,
      chunks: chunks,
      backend: backend,
      embedQuery: (q) async => fakeEmbed(q),
    );
    final hits = await retrieval.retrieve(
      query: 'मान्सून मूलभूत अधिकार',
      filter: RagSourceFilter.many(['geo']).copyWith(
        similarityThreshold: 0.01,
        hybrid: false,
      ),
    );
    expect(hits, isNotEmpty);
    expect(hits.every((h) => h.chunk.sourceId == 'geo'), isTrue);
  });

  test('Firebase permission error maps to permission_denied', () async {
    await _seedCorpus(sources: sources, chunks: chunks);
    final service = RagGroundedLearningService(
      retrieval: RagRetrievalService(
        sources: sources,
        chunks: chunks,
        backend: _PermBackend(),
      ),
      backend: _LearnBackend(),
      loadPublishedPyqs: () async => const [],
    );
    await expectLater(
      service.answer(question: 'मूलभूत अधिकार'),
      throwsA(
        isA<RagException>().having((e) => e.code, 'code', RagException.permissionDenied),
      ),
    );
  });

  test('Gemini failure maps to gemini_failed', () async {
    await _seedCorpus(sources: sources, chunks: chunks);
    final backend = _LearnBackend(failGemini: true);
    final service = RagGroundedLearningService(
      retrieval: RagRetrievalService(
        sources: sources,
        chunks: chunks,
        backend: backend,
        embedQuery: (q) async => fakeEmbed(q),
      ),
      backend: backend,
      loadPublishedPyqs: () async => const [],
    );
    await expectLater(
      service.answer(
        question: 'मूलभूत अधिकार',
        filter: const RagSourceFilter(similarityThreshold: 0.05, hybrid: false),
      ),
      throwsA(isA<RagException>().having((e) => e.code, 'code', RagException.geminiFailed)),
    );
  });

  test('summary, MCQ, flashcards, revision, memory tricks are source-grounded', () async {
    await _seedCorpus(sources: sources, chunks: chunks);
    final backend = _LearnBackend();
    final service = RagGroundedLearningService(
      retrieval: RagRetrievalService(
        sources: sources,
        chunks: chunks,
        backend: backend,
        embedQuery: (q) async => fakeEmbed(q),
      ),
      backend: backend,
      loadPublishedPyqs: () async => const [],
    );
    const filter = RagSourceFilter(similarityThreshold: 0.05, hybrid: false);
    final summary = await service.summary(topic: 'मूलभूत अधिकार', filter: filter);
    expect(summary.detailed, contains('सारांश'));
    expect(summary.citations.single.pageNumber, 24);

    final mcqs = await service.mcqs(topic: 'मूलभूत अधिकार', filter: filter);
    expect(mcqs.single.options, hasLength(4));
    expect(mcqs.single.difficulty, 'Easy');
    expect(mcqs.single.citations.single.pageNumber, 24);

    final cards = await service.flashcards(topic: 'मूलभूत अधिकार', filter: filter);
    expect(cards.single.front, contains('कलम'));
    expect(cards.single.citations.single.pageNumber, 24);

    final revision = await service.quickRevision(topic: 'मूलभूत अधिकार', filter: filter);
    expect(revision.articles, contains('कलम ३२'));
    expect(revision.dates, isEmpty);

    final tricks = await service.memoryTricks(topic: 'मूलभूत अधिकार', filter: filter);
    expect(tricks, isNotEmpty);
    expect(tricks.single.citations.single.pageNumber, 24);
  });

  test('PYQ connections never invent a year or question', () async {
    await _seedCorpus(sources: sources, chunks: chunks);
    final backend = _LearnBackend();
    final service = RagGroundedLearningService(
      retrieval: RagRetrievalService(
        sources: sources,
        chunks: chunks,
        backend: backend,
        embedQuery: (q) async => fakeEmbed(q),
      ),
      backend: backend,
      loadPublishedPyqs: () async => [
        const PyqItem(
          id: 'p1',
          title: 'Article 32 remedy',
          subtitle: 'MPSC',
          fileUrl: '',
          order: 1,
          year: 2019,
          examName: 'MPSC Prelims',
          question: 'कलम ३२ बद्दल विधान',
          answer: 'संवैधानिक उपाय',
          explanation: 'स्रोत PYQ',
          subjectId: 'pol',
          chapterId: 'fr',
          subject: 'Polity',
        ),
        const PyqItem(
          id: 'p2',
          title: 'Unrelated inflation',
          subtitle: '',
          fileUrl: '',
          order: 2,
          year: 2018,
          question: 'महागाई म्हणजे काय?',
          answer: 'किंमती वाढ',
          subject: 'Economics',
          subjectId: 'eco',
        ),
      ],
    );
    final pyqs = await service.pyqConnections(
      topic: 'मूलभूत अधिकार',
      filter: const RagSourceFilter(similarityThreshold: 0.05, hybrid: false),
    );
    expect(backend.learnCalls, 0);
    expect(pyqs, hasLength(1));
    expect(pyqs.single.year, 2019);
    expect(pyqs.any((p) => p.year == 2018), isFalse);
    expect(pyqs.any((p) => p.year == 2024), isFalse);

    final none = await service.pyqConnections(
      topic: 'xyzzyqwq',
      filter: const RagSourceFilter(similarityThreshold: 0.55, hybrid: false),
    );
    expect(none, isEmpty);
  });
}
