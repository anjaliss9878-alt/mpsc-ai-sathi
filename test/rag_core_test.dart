import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_chunker.dart';
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/rag/rag_vector.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_processing_service.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';

/// Deterministic 768-d bag-of-tokens embedding for tests (no API key).
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
  _FakeBackend({this.failExtract = false, this.failEmbed = false})
      : super(baseUrl: 'http://rag.test');

  final bool failExtract;
  final bool failEmbed;
  int embedCalls = 0;

  @override
  Future<List<RagExtractedPage>> extractPdf({
    required String fileUrl,
    String title = '',
  }) async {
    if (failExtract) {
      throw RagException.pdfExtraction('synthetic extract failure');
    }
    if (fileUrl.contains('empty')) {
      throw RagException.emptyDoc();
    }
    return [
      const RagExtractedPage(
        pageNumber: 1,
        text: 'भारतीय संविधानातील संसद ही द्विसदनी आहे. लोकसभा आणि राज्यसभा.',
      ),
      const RagExtractedPage(
        pageNumber: 2,
        text: 'MPSC Prelims मध्ये संसद रचना वारंवार विचारली जाते.',
      ),
    ];
  }

  @override
  Future<List<List<double>>> embed({
    required List<String> texts,
    String task = 'document',
  }) async {
    embedCalls++;
    if (failEmbed) {
      throw RagException.embedding('synthetic embed failure');
    }
    return [for (final t in texts) fakeEmbed(t)];
  }

  @override
  Future<List<double>> embedQuery(String query) async {
    if (failEmbed) {
      throw RagException.embedding('synthetic embed failure');
    }
    return fakeEmbed(query);
  }
}

RagSource _source({
  required String id,
  RagSourceStatus status = RagSourceStatus.processing,
  bool published = true,
  String contentHash = '',
  int chunkCount = 0,
  RagSourceType type = RagSourceType.text,
  String fileUrl = '',
  String subject = 'राज्यशास्त्र',
  String chapter = 'संसद',
  String subjectId = 'sub1',
  String chapterId = 'ch1',
}) {
  return RagSource(
    id: id,
    title: 'संसद',
    subject: subject,
    subjectId: subjectId,
    chapter: chapter,
    chapterId: chapterId,
    exam: kMpscDefaultExam,
    fileUrl: fileUrl,
    uploadedBy: 'admin1',
    createdAt: DateTime(2026, 1, 1),
    status: status,
    published: published,
    sourceType: type,
    contentHash: contentHash,
    chunkCount: chunkCount,
  );
}

RagProcessingService _processing(
  RagSourceRepository sources,
  RagChunkRepository chunks,
  FakeFirebaseFirestore firestore,
  _FakeBackend backend, {
  RagChunker chunker = ragChunker,
}) {
  return RagProcessingService(
    sources: sources,
    chunks: chunks,
    backend: backend,
    firestore: firestore,
    notes: NotesRepository(firestore: firestore),
    pyqs: PyqRepository(firestore: firestore),
    currentAffairs: CurrentAffairsRepository(firestore: firestore),
    chunker: chunker,
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

  test('chunking preserves real page numbers and never invents them', () {
    final out = const RagChunker().chunkPages([
      RagExtractedPage(pageNumber: 2, text: 'Alpha paragraph about संसद. ' * 20),
      RagExtractedPage(text: 'No page on this blob. ' * 20),
    ]);
    expect(out, isNotEmpty);
    expect(out.first.pageNumber, 2);
    expect(out.any((c) => c.pageNumber == null), isTrue);
    expect(out.every((c) => c.pageNumber == null || c.pageNumber! >= 1), isTrue);
  });

  test('clean + hash is stable for unchanged text', () {
    const a = '  संसद\n\n\nलोकसभा  ';
    const b = 'संसद\n\nलोकसभा';
    expect(ragContentHash(cleanRagText(a)), ragContentHash(cleanRagText(b)));
  });

  test('PDF upload path: extract → chunk → embed → Ready', () async {
    final backend = _FakeBackend();
    final processing = _processing(
      sources,
      chunks,
      firestore,
      backend,
      chunker: const RagChunker(targetChars: 90, maxChars: 140, overlapChars: 20),
    );
    await sources.create(_source(id: 's1', type: RagSourceType.pdf, fileUrl: 'https://x/file.pdf'));
    final ready = await processing.processSource('s1');
    expect(ready.status, RagSourceStatus.ready);
    expect(ready.chunkCount, greaterThan(0));
    expect(ready.errorMessage, isEmpty);
    final stored = await chunks.getForSource('s1');
    expect(stored, isNotEmpty);
    expect(stored.every((c) => c.embedding.length == kRagEmbeddingDimensions), isTrue);
    expect(stored.any((c) => c.pageNumber == 1), isTrue);
    expect(stored.any((c) => c.pageNumber == 2), isTrue);
  });

  test('text extraction empty document is Failed not Ready', () async {
    final processing = _processing(sources, chunks, firestore, _FakeBackend());
    await sources.create(_source(id: 'empty1', type: RagSourceType.text));
    await expectLater(
      processing.processSource('empty1', inlineText: '   \n'),
      throwsA(isA<RagException>().having((e) => e.code, 'code', RagException.emptyDocument)),
    );
    final failed = await sources.get('empty1');
    expect(failed!.status, RagSourceStatus.failed);
    expect(failed.errorMessage, isNotEmpty);
  });

  test('PDF extraction failure marks Failed', () async {
    final processing = _processing(
      sources,
      chunks,
      firestore,
      _FakeBackend(failExtract: true),
    );
    await sources.create(
      _source(id: 'badpdf', type: RagSourceType.pdf, fileUrl: 'https://x/a.pdf'),
    );
    await expectLater(
      processing.processSource('badpdf'),
      throwsA(isA<RagException>().having((e) => e.code, 'code', RagException.pdfExtractionFailed)),
    );
    expect((await sources.get('badpdf'))!.status, RagSourceStatus.failed);
  });

  test('embedding failure never marks Ready', () async {
    final processing = _processing(
      sources,
      chunks,
      firestore,
      _FakeBackend(failEmbed: true),
    );
    await sources.create(_source(id: 's2', type: RagSourceType.text));
    await expectLater(
      processing.processSource('s2', inlineText: 'संसद ही भारतीय संविधानातील केंद्रीय विधिमंडळ आहे.'),
      throwsA(isA<RagException>().having((e) => e.code, 'code', RagException.embeddingFailed)),
    );
    final failed = await sources.get('s2');
    expect(failed!.status, RagSourceStatus.failed);
    expect(await chunks.getForSource('s2'), isEmpty);
  });

  test('unchanged contentHash skips re-embedding', () async {
    final backend = _FakeBackend();
    final processing = _processing(sources, chunks, firestore, backend);
    const body = 'राज्यघटनेतील संसद रचना. लोकसभा थेट निवडून येते.';
    await sources.create(_source(id: 's3', type: RagSourceType.text));
    await processing.processSource('s3', inlineText: body);
    final firstCalls = backend.embedCalls;
    expect(firstCalls, greaterThan(0));
    await processing.processSource('s3', inlineText: body);
    expect(backend.embedCalls, firstCalls);
    expect((await sources.get('s3'))!.status, RagSourceStatus.ready);
  });

  test('vector search + source filtering + unpublished exclusion', () async {
    final backend = _FakeBackend();
    final processing = _processing(sources, chunks, firestore, backend);

    await sources.create(_source(id: 'pub', published: true));
    await processing.processSource(
      'pub',
      inlineText: 'भारतीय संसद द्विसदनी आहे. लोकसभा आणि राज्यसभा.',
    );
    await processing.setPublished((await sources.get('pub'))!, true);

    await sources.create(
      _source(id: 'hid', published: false, chapter: 'अर्थव्यवस्था', subject: 'अर्थशास्त्र'),
    );
    await processing.processSource(
      'hid',
      inlineText: 'भारतीय संसद द्विसदनी आहे. लोकसभा आणि राज्यसभा.',
    );

    await sources.create(
      _source(id: 'geo', published: true, subject: 'भूगोल', chapter: 'मान्सून', subjectId: 'sub2', chapterId: 'ch2'),
    );
    await processing.processSource(
      'geo',
      inlineText: 'मान्सून हा भारताच्या हवामानाचा मुख्य आधार आहे.',
    );
    await processing.setPublished((await sources.get('geo'))!, true);

    final retrieval = RagRetrievalService(
      sources: sources,
      chunks: chunks,
      backend: backend,
      embedQuery: (q) async => fakeEmbed(q),
    );

    final all = await retrieval.retrieve(
      query: 'संसद लोकसभा',
      filter: const RagSourceFilter(hybrid: false, similarityThreshold: 0.05),
    );
    expect(all, isNotEmpty);
    expect(all.every((h) => h.chunk.sourceId != 'hid'), isTrue);

    final one = await retrieval.retrieve(
      query: 'संसद',
      filter: RagSourceFilter.one('pub').copyWith(
        hybrid: false,
        similarityThreshold: 0.01,
      ),
    );
    expect(one, isNotEmpty);
    expect(one.every((h) => h.chunk.sourceId == 'pub'), isTrue);

    final many = await retrieval.retrieve(
      query: 'मान्सून',
      filter: RagSourceFilter.many(['geo', 'pub']).copyWith(
        hybrid: false,
        similarityThreshold: 0.01,
      ),
    );
    expect(many, isNotEmpty);
    expect(many.first.chunk.sourceId, 'geo');

    final chapter = await retrieval.retrieve(
      query: 'मान्सून',
      filter: RagSourceFilter.forSubject(subjectId: 'sub2', chapterId: 'ch2')
          .copyWith(hybrid: false, similarityThreshold: 0.01),
    );
    expect(chapter, isNotEmpty);
    expect(chapter.every((h) => h.chunk.chapterId == 'ch2'), isTrue);
  });

  test('hybrid keyword + vector prefers overlapping tokens', () {
    final a = fakeEmbed('संसद लोकसभा राज्यसभा');
    final b = fakeEmbed('मान्सून पाऊस हवामान');
    final q = fakeEmbed('संसद लोकसभा');
    expect(cosineSimilarity(q, a), greaterThan(cosineSimilarity(q, b)));
    expect(keywordScore(['संसद'], 'भारतीय संसद द्विसदनी'), greaterThan(0));
  });

  test('permission-denied maps to a useful RagException', () {
    final err = RagException.fromError(
      Exception('permission-denied Missing or insufficient permissions.'),
    );
    expect(err.code, RagException.permissionDenied);
    expect(err.message.toLowerCase(), contains('permission'));
  });

  test('applyFilter keeps only published Ready sources', () {
    final list = [
      _source(id: 'a', status: RagSourceStatus.ready, published: true),
      _source(id: 'b', status: RagSourceStatus.failed, published: true),
      _source(id: 'c', status: RagSourceStatus.ready, published: false),
    ];
    final filtered = RagSourceRepository.applyFilter(
      list,
      const RagSourceFilter(),
    );
    expect(filtered.map((s) => s.id), ['a']);
  });

  test('safe delete removes chunks but not unrelated sources', () async {
    final backend = _FakeBackend();
    final processing = _processing(sources, chunks, firestore, backend);
    await sources.create(_source(id: 'keep'));
    await processing.processSource(
      'keep',
      inlineText: 'भारतीय संविधानातील संसद रचना स्पष्ट करा. लोकसभा थेट निवडून येते.',
    );
    await processing.setPublished((await sources.get('keep'))!, true);
    await sources.create(_source(id: 'gone'));
    await processing.processSource(
      'gone',
      inlineText: 'भारतीय संविधानातील संसद रचना स्पष्ट करा. लोकसभा थेट निवडून येते.',
    );
    await processing.deleteSourceSafely((await sources.get('gone'))!);
    expect(await sources.get('gone'), isNull);
    expect(await chunks.getForSource('gone'), isEmpty);
    expect(await sources.get('keep'), isNotNull);
    expect(await chunks.getForSource('keep'), isNotEmpty);
  });
}
