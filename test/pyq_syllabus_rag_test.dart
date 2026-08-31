import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/content_knowledge_indexer.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/note_rag_indexer.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_processing_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';

List<double> _fakeEmbed(String text) {
  final v = List<double>.filled(kRagEmbeddingDimensions, 0);
  final tokens = ragKeywordTokens(text, limit: 80);
  if (tokens.isEmpty) {
    v[0] = 1;
    return v;
  }
  for (final token in tokens) {
    final h = token.hashCode.abs();
    v[h % kRagEmbeddingDimensions] += 1;
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
  Future<List<RagExtractedPage>> extractPdf({
    required String fileUrl,
    String title = '',
  }) async {
    return const [
      RagExtractedPage(
        pageNumber: 1,
        text: 'Article 14 equality before law. समानता.',
      ),
    ];
  }

  @override
  Future<List<List<double>>> embed({
    required List<String> texts,
    String task = 'document',
  }) async {
    return [for (final t in texts) _fakeEmbed(t)];
  }
}

class _FailEmbed extends RagBackendClient {
  _FailEmbed() : super(baseUrl: 'http://rag.test');

  @override
  Future<List<List<double>>> embed({
    required List<String> texts,
    String task = 'document',
  }) async {
    throw StateError('embedding down');
  }
}

PyqItem _pyq({
  required String id,
  String title = 'Article 14 PYQ',
  String question = 'Which article guarantees equality before law?',
  bool published = true,
  NoteWorkflowStatus status = NoteWorkflowStatus.published,
  int year = 2019,
  String subjectId = 'pol',
  String chapterId = 'fr',
  String topicId = 'a14',
}) {
  return PyqItem(
    id: id,
    title: title,
    subtitle: '',
    fileUrl: '',
    order: 1,
    year: year,
    examName: 'MPSC Combine',
    question: question,
    answer: 'Article 14',
    explanation: 'Equality before law.',
    subjectId: subjectId,
    chapterId: chapterId,
    subject: 'Polity',
    published: published,
    examId: kDefaultExamId,
    topicId: topicId,
    status: status,
  );
}

ChapterItem _topic({
  required String id,
  String title = 'अनुच्छेद 14',
  String parentId = 'fr',
  bool published = true,
  String subjectId = 'pol',
}) {
  return ChapterItem(
    id: id,
    subjectId: subjectId,
    title: title,
    titleEn: 'Article 14',
    description: 'Equality before law',
    order: 0,
    examId: kDefaultExamId,
    parentChapterId: parentId,
    nodeType: contentNodeTypeToString(ContentNodeType.topic),
    published: published,
  );
}

RagProcessingService _processing(
  FakeFirebaseFirestore firestore,
  RagSourceRepository sources,
  RagChunkRepository chunks,
  RagBackendClient backend, {
  NotesRepository? notes,
  PyqRepository? pyqs,
}) {
  return RagProcessingService(
    sources: sources,
    chunks: chunks,
    backend: backend,
    firestore: firestore,
    notes: notes ?? NotesRepository(firestore: firestore),
    pyqs: pyqs ?? PyqRepository(firestore: firestore),
    currentAffairs: CurrentAffairsRepository(firestore: firestore),
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late RagSourceRepository sources;
  late RagChunkRepository chunks;
  late ContentKnowledgeIndexer indexer;
  late PyqRepository pyqs;
  late NotesRepository notes;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    sources = RagSourceRepository(firestore: firestore);
    chunks = RagChunkRepository(firestore: firestore);
    pyqs = PyqRepository(firestore: firestore);
    notes = NotesRepository(firestore: firestore);
    indexer = ContentKnowledgeIndexer(
      sources: sources,
      processing: _processing(
        firestore,
        sources,
        chunks,
        _FakeBackend(),
        notes: notes,
        pyqs: pyqs,
      ),
    );
  });

  test('create PYQ → RAG source exists with required metadata', () async {
    final id = await pyqs.add(_pyq(id: ''));
    final item = _pyq(id: id);
    final source = await indexer.syncPyq(item);
    expect(source, isNotNull);
    expect(source!.contentType, kPyqContentType);
    expect(source.sourceType, RagSourceType.pyq);
    expect(source.examId, kDefaultExamId);
    expect(source.subjectId, 'pol');
    expect(source.chapterId, 'fr');
    expect(source.topicId, 'a14');
    expect(source.year, 2019);
    expect(source.linkedId, id);
    expect(source.linkedCollection, PyqRepository.collection);
    expect(source.ragDomain, ragDomainToString(RagDomain.pyq));
    expect(source.status, RagSourceStatus.ready);
    expect(source.published, isTrue);
    expect(source.isUsableForRetrieval, isTrue);
    expect(source.id, isNotEmpty);
    final chunkRows = await chunks.getForSource(source.id);
    expect(chunkRows, isNotEmpty);
    expect(chunkRows.every((c) => c.sourceId == source.id), isTrue);
    expect(chunkRows.every((c) => c.contentType == kPyqContentType), isTrue);
    expect(chunkRows.every((c) => c.examId == kDefaultExamId), isTrue);
    expect(chunkRows.every((c) => c.subjectId == 'pol'), isTrue);
    expect(chunkRows.every((c) => c.year == 2019), isTrue);
    final all = await sources.watchAll().first;
    expect(all.where((s) => s.linkedId == id), hasLength(1));
  });

  test('update PYQ → same source updated, no duplicate', () async {
    final id = await pyqs.add(_pyq(id: ''));
    final created = await indexer.syncPyq(_pyq(id: id));
    await pyqs.update(_pyq(id: id, question: 'Updated equality question?'));
    final updated = await indexer.syncPyq(
      _pyq(id: id, question: 'Updated equality question?'),
    );
    expect(updated!.id, created!.id);
    final all = await sources.watchAll().first;
    expect(all.where((s) => s.linkedId == id), hasLength(1));
    final chunkRows = await chunks.getForSource(updated.id);
    expect(chunkRows, isNotEmpty);
    expect(
      chunkRows.any((c) => c.text.contains('Updated equality')),
      isTrue,
    );
  });

  test('publish/unpublish PYQ toggles student-visible RAG', () async {
    final id = await pyqs.add(_pyq(id: ''));
    await indexer.syncPyq(_pyq(id: id));
    var ready = await sources.getPublishedReadyOnce();
    expect(ready.where((s) => s.linkedId == id), hasLength(1));

    final draft = _pyq(
      id: id,
      published: false,
      status: NoteWorkflowStatus.unpublished,
    );
    await pyqs.update(draft);
    await indexer.syncPyq(draft);
    ready = await sources.getPublishedReadyOnce();
    expect(ready.where((s) => s.linkedId == id), isEmpty);
    final hidden = await sources.findLinked(
      collection: PyqRepository.collection,
      linkedId: id,
    );
    expect(hidden, isNotNull);
    expect(hidden!.published, isFalse);
    expect(hidden.isUsableForRetrieval, isFalse);
    final hiddenChunks = await chunks.getForSource(hidden.id);
    expect(hiddenChunks.every((c) => !c.published), isTrue);

    final live = _pyq(id: id);
    await pyqs.update(live);
    await indexer.syncPyq(live);
    ready = await sources.getPublishedReadyOnce();
    expect(ready.where((s) => s.linkedId == id), hasLength(1));
  });

  test('create/update syllabus topic → RAG source', () async {
    final chapterId = await notes.addChapter(
      const ChapterItem(
        id: '',
        subjectId: 'pol',
        title: 'Fundamental Rights',
        order: 0,
        examId: kDefaultExamId,
        nodeType: 'chapter',
        published: true,
      ),
    );
    final topicId = await notes.addChapter(
      _topic(id: '', parentId: chapterId),
    );
    final topic = _topic(id: topicId, parentId: chapterId);
    final source = await indexer.syncSyllabus(topic);
    expect(source, isNotNull);
    expect(source!.contentType, kSyllabusContentType);
    expect(source.sourceType, RagSourceType.chapter);
    expect(source.examId, kDefaultExamId);
    expect(source.subjectId, 'pol');
    expect(source.chapterId, chapterId);
    expect(source.topicId, topicId);
    expect(source.linkedId, topicId);
    expect(source.ragDomain, ragDomainToString(RagDomain.syllabus));
    expect(source.status, RagSourceStatus.ready);
    expect(source.published, isTrue);

    final renamed = _topic(
      id: topicId,
      parentId: chapterId,
      title: 'Article 14 equality',
    );
    final again = await indexer.syncSyllabus(renamed);
    expect(again!.id, source.id);
    final all = await sources.watchAll().first;
    expect(
      all.where((s) => s.linkedCollection == NotesRepository.chaptersCollection),
      hasLength(1),
    );
  });

  test('unpublished syllabus is excluded from student retrieval', () async {
    final topicId = await notes.addChapter(_topic(id: ''));
    await indexer.syncSyllabus(_topic(id: topicId));
    expect(
      (await sources.getPublishedReadyOnce())
          .where((s) => s.linkedId == topicId),
      hasLength(1),
    );
    await indexer.syncSyllabus(_topic(id: topicId, published: false));
    expect(
      (await sources.getPublishedReadyOnce())
          .where((s) => s.linkedId == topicId),
      isEmpty,
    );
  });

  test('failed indexing → Failed status + retry possible', () async {
    final id = await pyqs.add(_pyq(id: ''));
    final failing = ContentKnowledgeIndexer(
      sources: sources,
      processing: _processing(
        firestore,
        sources,
        chunks,
        _FailEmbed(),
        notes: notes,
        pyqs: pyqs,
      ),
    );
    await expectLater(failing.syncPyq(_pyq(id: id)), throwsA(isA<Object>()));
    final failed = await sources.findLinked(
      collection: PyqRepository.collection,
      linkedId: id,
    );
    expect(failed, isNotNull);
    expect(failed!.status, RagSourceStatus.failed);
    expect(failed.published, isFalse);
    expect(failed.isUsableForRetrieval, isFalse);

    final recovered = await indexer.retryPyq(_pyq(id: id));
    expect(recovered!.id, failed.id);
    expect(recovered.status, RagSourceStatus.ready);
    expect(recovered.published, isTrue);
    expect(recovered.isUsableForRetrieval, isTrue);
  });

  test('delete PYQ removes its RAG source and chunks', () async {
    final id = await pyqs.add(_pyq(id: ''));
    final source = await indexer.syncPyq(_pyq(id: id));
    await pyqs.delete(id);
    await indexer.removeLinked(
      collection: PyqRepository.collection,
      linkedId: id,
    );
    expect(await sources.get(source!.id), isNull);
    expect(await chunks.getForSource(source.id), isEmpty);
    expect(
      (await sources.getPublishedReadyOnce())
          .where((s) => s.linkedId == id),
      isEmpty,
    );
  });

  test('existing Notes RAG indexing still works', () async {
    final noteIndexer = NoteRagIndexer(
      notes: notes,
      sources: sources,
      processing: _processing(
        firestore,
        sources,
        chunks,
        _FakeBackend(),
        notes: notes,
        pyqs: pyqs,
      ),
    );
    final noteId = await notes.saveNote(
      subjectId: 'pol',
      chapterId: 'fr',
      examId: kDefaultExamId,
      topicId: 'a14',
      title: 'Article 14 notes',
      status: NoteWorkflowStatus.published,
      attachments: const [
        NoteAttachment(
          name: 'a14.pdf',
          url: 'https://example.com/a14.pdf',
          type: 'pdf',
        ),
      ],
    );
    final note = await notes.getNote(noteId);
    final indexed = await noteIndexer.indexNote(note!);
    expect(indexed.ragStatus, NoteRagStatus.indexed);
    expect(indexed.ragSourceId, isNotEmpty);
    final source = await sources.get(indexed.ragSourceId);
    expect(source!.contentType, kNotesPdfContentType);
    expect(source.isUsableForRetrieval, isTrue);
  });
}
