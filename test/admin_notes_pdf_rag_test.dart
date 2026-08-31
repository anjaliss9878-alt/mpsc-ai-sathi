import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/note_rag_indexer.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_processing_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';
import 'package:mpsc_combine_ai/utils/pdf_meta.dart';

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

void main() {
  late FakeFirebaseFirestore firestore;
  late NotesRepository notes;
  late RagSourceRepository sources;
  late RagChunkRepository chunks;
  late NoteRagIndexer indexer;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    notes = NotesRepository(firestore: firestore);
    sources = RagSourceRepository(firestore: firestore);
    chunks = RagChunkRepository(firestore: firestore);
    final processing = RagProcessingService(
      sources: sources,
      chunks: chunks,
      backend: _FakeBackend(),
      firestore: firestore,
      notes: notes,
      pyqs: PyqRepository(firestore: firestore),
      currentAffairs: CurrentAffairsRepository(firestore: firestore),
    );
    indexer = NoteRagIndexer(
      notes: notes,
      sources: sources,
      processing: processing,
    );
  });

  test('draft notes are hidden from students; published PDF notes appear', () async {
    final draftId = await notes.saveNote(
      subjectId: 'pol',
      chapterId: 'const',
      topicId: 'fr',
      title: 'Draft FR',
      status: NoteWorkflowStatus.draft,
      attachments: const [
        NoteAttachment(name: 'fr.pdf', url: 'https://example.com/fr.pdf', type: 'pdf'),
      ],
    );
    expect(await notes.watchPublishedNoteForChapter('fr').first, isNull);

    await notes.saveNote(
      noteId: draftId,
      subjectId: 'pol',
      chapterId: 'const',
      topicId: 'fr',
      status: NoteWorkflowStatus.published,
    );
    final visible = await notes.watchPublishedNoteForChapter('fr').first;
    expect(visible, isNotNull);
    expect(visible!.pdfUrl, 'https://example.com/fr.pdf');
    expect(visible.status, NoteWorkflowStatus.published);
  });

  test('unpublish hides note from students', () async {
    final id = await notes.saveNote(
      subjectId: 'pol',
      chapterId: 'const',
      topicId: 'fr',
      title: 'FR',
      status: NoteWorkflowStatus.published,
    );
    expect(await notes.watchPublishedNoteForChapter('fr').first, isNotNull);
    await notes.saveNote(
      noteId: id,
      subjectId: 'pol',
      chapterId: 'const',
      topicId: 'fr',
      status: NoteWorkflowStatus.unpublished,
    );
    expect(await notes.watchPublishedNoteForChapter('fr').first, isNull);
  });

  test('saveNote stores PDF metadata and workflow fields', () async {
    final id = await notes.saveNote(
      examId: 'mpsc_combine',
      subjectId: 'pol',
      chapterId: 'const',
      topicId: 'fr',
      title: 'Article 14',
      description: 'Equality notes',
      language: 'mr',
      difficulty: 'Medium',
      source: 'Laxmikanth',
      status: NoteWorkflowStatus.draft,
      pdfFileName: 'article-14.pdf',
      pdfFileSize: 4096,
      pdfPageCount: 12,
      pdfStoragePath: 'notes/1_article-14.pdf',
      attachments: const [
        NoteAttachment(
          name: 'article-14.pdf',
          url: 'https://example.com/article-14.pdf',
          type: 'pdf',
        ),
      ],
      tags: const ['polity', 'article-14'],
    );
    final snap = await firestore.collection('notes').doc(id).get();
    final data = snap.data()!;
    expect(data['examId'], 'mpsc_combine');
    expect(data['topicId'], 'fr');
    expect(data['status'], 'draft');
    expect(data['published'], isFalse);
    expect(data['pdfFileName'], 'article-14.pdf');
    expect(data['pdfFileSize'], 4096);
    expect(data['pdfPageCount'], 12);
    expect(data['source'], 'Laxmikanth');
    expect(data['ragStatus'], 'notIndexed');
  });

  test('published note PDF is indexed via existing RAG pipeline', () async {
    final noteId = await notes.saveNote(
      examId: 'mpsc_combine',
      subjectId: 'pol',
      chapterId: 'const',
      topicId: 'fr',
      title: 'Article 14',
      language: 'mr',
      source: 'Bare Act',
      status: NoteWorkflowStatus.published,
      attachments: const [
        NoteAttachment(
          name: 'a14.pdf',
          url: 'https://example.com/a14.pdf',
          type: 'pdf',
        ),
      ],
    );
    var note = await notes.getNote(noteId);
    note = await indexer.indexNote(
      note!,
      subjectTitle: 'Polity',
      chapterTitle: 'Constitution',
      examTitle: kMpscDefaultExam,
    );
    expect(note.ragStatus, NoteRagStatus.indexed);
    expect(note.ragSourceId, isNotEmpty);

    final source = await sources.get(note.ragSourceId);
    expect(source, isNotNull);
    expect(source!.contentType, kNotesPdfContentType);
    expect(source.noteId, noteId);
    expect(source.topicId, 'fr');
    expect(source.chapterId, 'const');
    expect(source.examId, 'mpsc_combine');
    expect(source.linkedCollection, 'notes');
    expect(source.ownsFile, isFalse);
    expect(source.published, isTrue);
    expect(source.status, RagSourceStatus.ready);
    expect(source.sourceType, RagSourceType.pdf);

    final ragChunks = await chunks.getForSource(note.ragSourceId);
    expect(ragChunks, isNotEmpty);
    expect(ragChunks.first.topicId, 'fr');
    expect(ragChunks.first.noteId, noteId);
    expect(ragChunks.first.contentType, kNotesPdfContentType);
    expect(ragChunks.first.published, isTrue);
  });

  test('unpublished note RAG source is not student-usable', () async {
    final noteId = await notes.saveNote(
      subjectId: 'pol',
      chapterId: 'const',
      topicId: 'fr',
      title: 'Article 14',
      status: NoteWorkflowStatus.published,
      attachments: const [
        NoteAttachment(name: 'a14.pdf', url: 'https://example.com/a14.pdf', type: 'pdf'),
      ],
    );
    var note = await notes.getNote(noteId);
    note = await indexer.indexNote(note!);
    expect(note.ragStatus, NoteRagStatus.indexed);

    await notes.saveNote(
      noteId: noteId,
      subjectId: 'pol',
      chapterId: 'const',
      topicId: 'fr',
      status: NoteWorkflowStatus.unpublished,
    );
    note = await notes.getNote(noteId);
    await indexer.syncPublished(note!);
    final source = await sources.get(note.ragSourceId);
    expect(source!.published, isFalse);
    expect(source.isUsableForRetrieval, isFalse);
  });

  test('failed RAG index can be retried', () async {
    final noteId = await notes.saveNote(
      subjectId: 'pol',
      chapterId: 'const',
      topicId: 'fr',
      title: 'Article 14',
      status: NoteWorkflowStatus.approved,
      attachments: const [
        NoteAttachment(name: 'a14.pdf', url: 'https://example.com/empty.pdf', type: 'pdf'),
      ],
    );
    var note = await notes.getNote(noteId);
    await notes.patchNote(noteId, {
      'ragStatus': noteRagStatusToString(NoteRagStatus.failed),
      'ragError': 'synthetic',
    });
    note = await notes.getNote(noteId);
    expect(note!.ragStatus, NoteRagStatus.failed);
    final retried = await indexer.retry(note);
    expect(retried.ragStatus, NoteRagStatus.indexed);
  });

  test('pdfPageCountFromBytes reads /Count from a Pages catalog', () {
    final pdf = Uint8List.fromList(
      '%PDF-1.4\n1 0 obj\n<< /Type /Pages /Count 3 /Kids [] >>\nendobj\n%%EOF'
          .codeUnits,
    );
    expect(pdfPageCountFromBytes(pdf), 3);
  });

  test('indexer without PDF marks Not Indexed', () async {
    final id = await notes.saveNote(
      subjectId: 'pol',
      chapterId: 'ch',
      title: 'No pdf',
      status: NoteWorkflowStatus.draft,
    );
    final note = await notes.getNote(id);
    final result = await indexer.indexNote(note!);
    expect(result.ragStatus, NoteRagStatus.notIndexed);
  });
}
