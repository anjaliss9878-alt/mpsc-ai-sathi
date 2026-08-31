import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/multi_rag_result.dart';
import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_router.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
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

class _FakeBackend extends RagBackendClient {
  _FakeBackend() : super(baseUrl: 'http://rag.test');

  @override
  Future<List<List<double>>> embed({
    required List<String> texts,
    String task = 'document',
  }) async {
    return [for (final t in texts) fakeEmbed(t)];
  }

  @override
  Future<List<double>> embedQuery(String query) async => fakeEmbed(query);
}

RagSource _source({
  required String id,
  required String title,
  required String contentType,
  RagSourceType sourceType = RagSourceType.text,
  String subjectId = 'pol',
  String chapterId = 'fr',
  String topicId = 'a14',
  String language = 'en',
  String source = 'Bare Act',
  int? year,
  String difficulty = 'Medium',
  String contentStatus = 'published',
  String ragDomain = '',
  String linkedCollection = '',
  bool published = true,
}) {
  return RagSource(
    id: id,
    title: title,
    subject: 'Polity',
    subjectId: subjectId,
    chapter: 'Fundamental Rights',
    chapterId: chapterId,
    exam: kMpscDefaultExam,
    fileUrl: '',
    uploadedBy: 'admin1',
    createdAt: DateTime(2026, 1, 1),
    status: RagSourceStatus.processing,
    published: published,
    sourceType: sourceType,
    language: language,
    linkedCollection: linkedCollection,
    linkedId: id,
    examId: kDefaultExamId,
    topicId: topicId,
    contentType: contentType,
    source: source,
    year: year,
    difficulty: difficulty,
    contentStatus: contentStatus,
    ragDomain: ragDomain,
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late RagSourceRepository sources;
  late RagChunkRepository chunks;
  late RagProcessingService processing;
  late RagRetrievalService retrieval;
  late MultiRagRetrievalService multi;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    sources = RagSourceRepository(firestore: firestore);
    chunks = RagChunkRepository(firestore: firestore);
    final backend = _FakeBackend();
    processing = RagProcessingService(
      sources: sources,
      chunks: chunks,
      backend: backend,
      firestore: firestore,
      notes: NotesRepository(firestore: firestore),
      pyqs: PyqRepository(firestore: firestore),
      currentAffairs: CurrentAffairsRepository(firestore: firestore),
    );
    retrieval = RagRetrievalService(
      sources: sources,
      chunks: chunks,
      backend: backend,
      embedQuery: (q) async => fakeEmbed(q),
    );
    multi = MultiRagRetrievalService(
      retrieval: retrieval,
      embedQuery: (q) async => fakeEmbed(q),
    );
  });

  Future<void> _index({
    required String id,
    required String title,
    required String text,
    required String contentType,
    RagSourceType sourceType = RagSourceType.text,
    String topicId = 'a14',
    String linkedCollection = '',
    int? year,
    String ragDomain = '',
    bool published = true,
  }) async {
    await sources.create(
      _source(
        id: id,
        title: title,
        contentType: contentType,
        sourceType: sourceType,
        topicId: topicId,
        linkedCollection: linkedCollection,
        year: year,
        ragDomain: ragDomain,
        published: published,
      ),
    );
    final ready = await processing.processSource(id, inlineText: text);
    await processing.setPublished(ready, published);
  }

  test('domain enum round-trips the six logical names', () {
    expect(ragDomainToString(RagDomain.notes), 'notes_rag');
    expect(ragDomainToString(RagDomain.pyq), 'pyq_rag');
    expect(ragDomainToString(RagDomain.syllabus), 'syllabus_rag');
    expect(ragDomainToString(RagDomain.currentAffairs), 'current_affairs_rag');
    expect(ragDomainToString(RagDomain.aiTeacher), 'ai_teacher_rag');
    expect(
      ragDomainToString(RagDomain.studentPerformance),
      'student_performance_rag',
    );
    for (final domain in RagDomain.values) {
      expect(ragDomainFromString(ragDomainToString(domain)), domain);
    }
  });

  test('legacy chunks without ragDomain still infer the right domain', () {
    expect(
      inferRagDomain(contentType: kNotesPdfContentType, sourceType: 'pdf'),
      RagDomain.notes,
    );
    expect(
      inferRagDomain(contentType: kPyqContentType, sourceType: 'pyq'),
      RagDomain.pyq,
    );
    expect(
      inferRagDomain(sourceType: 'chapter', linkedCollection: 'chapters'),
      RagDomain.syllabus,
    );
    expect(
      inferRagDomain(contentType: kCurrentAffairsContentType),
      RagDomain.currentAffairs,
    );
    expect(
      inferRagDomain(contentType: kAiLessonContentType),
      RagDomain.aiTeacher,
    );
    final legacy = RagChunk(
      id: 'c1',
      sourceId: 's1',
      sourceTitle: 'FR',
      subject: 'Polity',
      chapter: 'FR',
      text: 'Article 14',
      embedding: const [1],
      language: 'en',
      sourceType: 'pyq',
      contentType: kPyqContentType,
    );
    expect(legacy.ragDomain, isEmpty);
    expect(legacy.domain, RagDomain.pyq);
  });

  test('router examples pick the documented domain sets', () {
    const router = RagRouter();
    expect(
      router.route('Fundamental Rights explain').domains,
      [RagDomain.notes, RagDomain.syllabus],
    );
    expect(
      router.route('Fundamental Rights PYQs').domains,
      [RagDomain.pyq, RagDomain.notes],
    );
    expect(
      router.route('My weak topics').domains,
      [RagDomain.studentPerformance, RagDomain.notes],
    );
    expect(
      router.route('Current affairs Maharashtra').domains,
      [RagDomain.currentAffairs],
    );
    expect(
      router
          .route(
            'Fundamental Rights',
            context: const RagRouteContext(fromAiTeacher: true),
          )
          .domains,
      [RagDomain.aiTeacher, RagDomain.notes],
    );
    expect(router.route('Fundamental Rights explain').confidence, greaterThan(0.7));
    expect(router.route('').domains, isEmpty);
  });

  test('indexed chunks keep Exam → Subject → Chapter → Topic metadata', () async {
    await _index(
      id: 'note1',
      title: 'Article 14',
      text:
          'Fundamental Rights include equality before law. Article 14 of the Constitution.',
      contentType: kNotesPdfContentType,
      sourceType: RagSourceType.pdf,
      year: 2024,
    );
    final stored = await chunks.getForSource('note1');
    expect(stored, isNotEmpty);
    final chunk = stored.first;
    expect(chunk.examId, kDefaultExamId);
    expect(chunk.subjectId, 'pol');
    expect(chunk.chapterId, 'fr');
    expect(chunk.topicId, 'a14');
    expect(chunk.contentType, kNotesPdfContentType);
    expect(chunk.language, isNotEmpty);
    expect(chunk.source, 'Bare Act');
    expect(chunk.year, 2024);
    expect(chunk.difficulty, 'Medium');
    expect(chunk.status, 'published');
    expect(chunk.domain, RagDomain.notes);
    expect(chunk.ragDomain, 'notes_rag');
  });

  test('domain filters search one corpus — no second collection', () async {
    await _index(
      id: 'note1',
      title: 'Article 14 notes',
      text: 'Fundamental Rights equality before law Article 14.',
      contentType: kNotesPdfContentType,
      sourceType: RagSourceType.pdf,
    );
    await _index(
      id: 'pyq1',
      title: 'FR PYQ 2019',
      text: 'Fundamental Rights previous year question on Article 14 equality.',
      contentType: kPyqContentType,
      sourceType: RagSourceType.pyq,
      linkedCollection: 'pyqs',
      year: 2019,
    );
    await _index(
      id: 'syl1',
      title: 'Polity syllabus FR',
      text: 'Syllabus topic Fundamental Rights Articles 12 to 35.',
      contentType: kSyllabusContentType,
      sourceType: RagSourceType.chapter,
      linkedCollection: 'chapters',
    );
    await _index(
      id: 'ca1',
      title: 'Maharashtra CA',
      text: 'Current affairs Maharashtra budget and irrigation scheme.',
      contentType: kCurrentAffairsContentType,
      sourceType: RagSourceType.currentAffairs,
      linkedCollection: 'currentAffairs',
      topicId: 'mh',
    );
    await _index(
      id: 'ai1',
      title: 'AI Teacher FR lesson',
      text: 'Classroom lesson on Fundamental Rights and Article 32.',
      contentType: kAiLessonContentType,
    );

    final corpus = await chunks.getPublished();
    expect(corpus, isNotEmpty);
    expect(await sources.getPublishedReadyOnce(), isNotEmpty);
    expect(
      corpus.map((c) => c.sourceId).toSet(),
      containsAll(['note1', 'pyq1', 'syl1', 'ca1', 'ai1']),
    );
    expect(
      (await firestore.collection('notes_rag').get()).docs,
      isEmpty,
    );
    expect(
      (await firestore.collection('pyq_rag').get()).docs,
      isEmpty,
    );

    final notesOnly = await retrieval.retrieve(
      query: 'Fundamental Rights',
      filter: RagSourceFilter.forDomain(RagDomain.notes).copyWith(
        hybrid: false,
        similarityThreshold: 0.01,
      ),
    );
    expect(notesOnly, isNotEmpty);
    expect(notesOnly.every((h) => h.chunk.domain == RagDomain.notes), isTrue);

    final pyqOnly = await retrieval.retrieve(
      query: 'Fundamental Rights',
      filter: RagSourceFilter.forDomain(RagDomain.pyq).copyWith(
        hybrid: false,
        similarityThreshold: 0.01,
      ),
    );
    expect(pyqOnly, isNotEmpty);
    expect(pyqOnly.every((h) => h.chunk.domain == RagDomain.pyq), isTrue);
    expect(pyqOnly.every((h) => h.chunk.year == 2019), isTrue);

    final existingUnfiltered = await retrieval.retrieve(
      query: 'Fundamental Rights',
      filter: const RagSourceFilter(hybrid: false, similarityThreshold: 0.01),
    );
    expect(existingUnfiltered.length, greaterThanOrEqualTo(2));
    expect(
      existingUnfiltered.map((h) => h.chunk.domain).toSet(),
      containsAll([RagDomain.notes, RagDomain.pyq]),
    );
  });

  test('multi-RAG retrieve routes, scores confidence, and cites sources', () async {
    await _index(
      id: 'note1',
      title: 'Article 14 notes',
      text: 'Fundamental Rights equality before law Article 14.',
      contentType: kNotesPdfContentType,
      sourceType: RagSourceType.pdf,
    );
    await _index(
      id: 'pyq1',
      title: 'FR PYQ',
      text: 'Fundamental Rights PYQ Article 14 previous year.',
      contentType: kPyqContentType,
      sourceType: RagSourceType.pyq,
      linkedCollection: 'pyqs',
      year: 2018,
    );
    await _index(
      id: 'syl1',
      title: 'FR syllabus',
      text: 'Syllabus covers Fundamental Rights Articles 12 to 35.',
      contentType: kSyllabusContentType,
      sourceType: RagSourceType.chapter,
      linkedCollection: 'chapters',
    );
    await _index(
      id: 'ca1',
      title: 'Maharashtra current affairs',
      text: 'Current affairs Maharashtra cabinet decision on water.',
      contentType: kCurrentAffairsContentType,
      sourceType: RagSourceType.currentAffairs,
      linkedCollection: 'currentAffairs',
      topicId: 'mh',
    );
    await _index(
      id: 'ai1',
      title: 'AI Teacher FR',
      text: 'AI Teacher classroom lesson Fundamental Rights Article 32.',
      contentType: kAiLessonContentType,
    );

    final explain = await multi.retrieve(
      const MultiRagQuery(query: 'Fundamental Rights explain'),
    );
    expect(explain.plan.domains, [RagDomain.notes, RagDomain.syllabus]);
    expect(explain.hits, isNotEmpty);
    expect(explain.confidence, greaterThan(0));
    expect(explain.sourceRefs, isNotEmpty);
    expect(explain.sourceRefs.every((s) => s.examId == kDefaultExamId), isTrue);
    expect(explain.hitsFor(RagDomain.pyq), isEmpty);
    expect(explain.hitsFor(RagDomain.notes), isNotEmpty);

    final pyqs = await multi.retrieve(
      const MultiRagQuery(query: 'Fundamental Rights PYQs'),
    );
    expect(pyqs.plan.domains, [RagDomain.pyq, RagDomain.notes]);
    expect(pyqs.hitsFor(RagDomain.pyq), isNotEmpty);
    expect(pyqs.sourceRefs.any((s) => s.year == 2018), isTrue);

    final ca = await multi.retrieve(
      const MultiRagQuery(query: 'Current affairs Maharashtra'),
    );
    expect(ca.plan.domains, [RagDomain.currentAffairs]);
    expect(ca.hits.every((h) => h.domain == RagDomain.currentAffairs), isTrue);

    final teacher = await multi.retrieve(
      const MultiRagQuery(
        query: 'Fundamental Rights',
        context: RagRouteContext(fromAiTeacher: true, topicId: 'a14'),
      ),
    );
    expect(teacher.plan.domains, [RagDomain.aiTeacher, RagDomain.notes]);
    expect(teacher.hitsFor(RagDomain.aiTeacher), isNotEmpty);

    final weak = await multi.retrieve(
      const MultiRagQuery(
        query: 'My weak topics',
        performance: [
          StudentPerformanceRecord(
            label: 'Fundamental Rights',
            examId: kDefaultExamId,
            subjectId: 'pol',
            chapterId: 'fr',
            topicId: 'a14',
            scorePercent: 32,
            source: 'mock_test',
            status: 'weak',
          ),
        ],
      ),
    );
    expect(
      weak.plan.domains,
      [RagDomain.studentPerformance, RagDomain.notes],
    );
    expect(weak.hitsFor(RagDomain.studentPerformance), isNotEmpty);
    expect(weak.hitsFor(RagDomain.notes), isNotEmpty);
    expect(
      weak.sourceRefs.any(
        (s) => s.ragDomain == 'student_performance_rag' && s.topicId == 'a14',
      ),
      isTrue,
    );
    expect(
      (await chunks.getPublished()).any((c) => c.id.startsWith('perf_')),
      isFalse,
    );
  });

  test('existing all-published retrieval still excludes unpublished', () async {
    await _index(
      id: 'pub',
      title: 'Visible FR',
      text: 'Fundamental Rights Article 14 equality.',
      contentType: kNotesPdfContentType,
    );
    await _index(
      id: 'hid',
      title: 'Hidden FR',
      text: 'Fundamental Rights Article 14 equality.',
      contentType: kNotesPdfContentType,
      published: false,
    );
    final hits = await retrieval.retrieve(
      query: 'Fundamental Rights',
      filter: const RagSourceFilter(hybrid: false, similarityThreshold: 0.01),
    );
    expect(hits, isNotEmpty);
    expect(hits.every((h) => h.chunk.sourceId != 'hid'), isTrue);
  });
}
