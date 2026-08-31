import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/current_affair_item.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/pdf_content_block.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_chunker.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';
import 'package:mpsc_combine_ai/services/storage_service.dart';

/// Admin-side pipeline: extract → clean → chunk → embed → index.
///
/// Never marks a source [RagSourceStatus.ready] unless embeddings were
/// written. Unchanged [contentHash] skips re-embedding.
class RagProcessingService {
  RagProcessingService({
    RagSourceRepository? sources,
    RagChunkRepository? chunks,
    RagBackendClient? backend,
    NotesRepository? notes,
    PyqRepository? pyqs,
    CurrentAffairsRepository? currentAffairs,
    StorageService? storage,
    FirebaseFirestore? firestore,
    RagChunker chunker = ragChunker,
  })  : _sources = sources ?? ragSourceRepository,
        _chunks = chunks ?? ragChunkRepository,
        _backend = backend ?? ragBackendClient,
        _notes = notes ?? notesRepository,
        _pyqs = pyqs ?? pyqRepository,
        _currentAffairs = currentAffairs ?? currentAffairsRepository,
        _storage = storage ?? storageService,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _chunker = chunker;

  final RagSourceRepository _sources;
  final RagChunkRepository _chunks;
  final RagBackendClient _backend;
  final NotesRepository _notes;
  final PyqRepository _pyqs;
  final CurrentAffairsRepository _currentAffairs;
  final StorageService _storage;
  final FirebaseFirestore _firestore;
  final RagChunker _chunker;

  /// Run (or retry) processing for [sourceId].
  Future<RagSource> processSource(
    String sourceId, {
    String? inlineText,
    bool force = false,
  }) async {
    final existing = await _sources.get(sourceId);
    if (existing == null) {
      throw RagException.processing('Source not found.');
    }

    await _chunks.setPublishedForSource(sourceId, false);
    await _sources.patch(sourceId, {
      'status': ragSourceStatusToString(RagSourceStatus.processing),
      'errorMessage': '',
    });

    try {
      final pages = await _extractPages(existing, inlineText: inlineText);
      final cleanedPages = [
        for (final p in pages)
          RagExtractedPage(
            pageNumber: p.pageNumber,
            text: cleanRagText(p.text),
          ),
      ].where((p) => p.text.isNotEmpty).toList();

      if (cleanedPages.isEmpty) {
        throw RagException.emptyDoc();
      }

      final joined = cleanedPages.map((p) => p.text).join('\n\n');
      final hash = ragContentHash(joined);
      final language = detectRagLanguage(joined);

      if (!force &&
          hash.isNotEmpty &&
          hash == existing.contentHash &&
          existing.status == RagSourceStatus.ready &&
          existing.chunkCount > 0) {
        final cached = await _chunks.getForSource(sourceId);
        if (cached.isNotEmpty && cached.every((c) => c.embedding.isNotEmpty)) {
          await _sources.patch(sourceId, {
            'status': ragSourceStatusToString(RagSourceStatus.ready),
            'errorMessage': '',
            'language': language,
            'chunkCount': cached.length,
            'needsReindex': false,
          });
          final live = (await _sources.get(sourceId)) ?? existing;
          await _restoreStudentChunkVisibility(sourceId, live);
          return live;
        }
      }

      final textChunks = _chunker.chunkPages(cleanedPages);
      if (textChunks.isEmpty) {
        throw RagException.emptyDoc('No usable chunks after splitting.');
      }

      final embeddings = await _embedAll(
        textChunks.map((c) => c.text).toList(growable: false),
      );

      final ragChunks = <RagChunk>[
        for (var i = 0; i < textChunks.length; i++)
          RagChunk(
            id: '${sourceId}_$i',
            sourceId: sourceId,
            sourceTitle: existing.title,
            subject: existing.subject,
            subjectId: existing.subjectId,
            chapter: existing.chapter,
            chapterId: existing.chapterId,
            topicId: existing.topicId,
            noteId: existing.noteId,
            contentType: existing.contentType,
            exam: existing.exam,
            examId: existing.examId.isNotEmpty
                ? existing.examId
                : kDefaultExamId,
            source: existing.source,
            year: existing.year,
            difficulty: existing.difficulty,
            status: existing.contentStatus.isNotEmpty
                ? existing.contentStatus
                : (existing.published
                    ? noteWorkflowStatusToString(NoteWorkflowStatus.published)
                    : noteWorkflowStatusToString(NoteWorkflowStatus.draft)),
            ragDomain: ragDomainToString(
              inferRagDomain(
                ragDomain: existing.ragDomain,
                contentType: existing.contentType,
                sourceType: ragSourceTypeToString(existing.sourceType),
                linkedCollection: existing.linkedCollection,
              ),
            ),
            pageNumber: textChunks[i].pageNumber,
            chunkIndex: textChunks[i].index,
            text: textChunks[i].text,
            embedding: embeddings[i],
            language: language,
            sourceType: ragSourceTypeToString(existing.sourceType),
            published: false,
            contentHash: hash,
            keywords: ragKeywordTokens(textChunks[i].text),
          ),
      ];

      await _chunks.replaceSourceChunks(sourceId: sourceId, chunks: ragChunks);
      await _sources.patch(sourceId, {
        'status': ragSourceStatusToString(RagSourceStatus.ready),
        'errorMessage': '',
        'contentHash': hash,
        'chunkCount': ragChunks.length,
        'language': language,
        'ragDomain': ragChunks.first.ragDomain,
        'needsReindex': false,
        if (existing.examId.isEmpty) 'examId': kDefaultExamId,
      });
      final live = (await _sources.get(sourceId)) ?? existing;
      await _restoreStudentChunkVisibility(sourceId, live);
      return live;
    } catch (e) {
      final err = RagException.fromError(e);
      await _sources.patch(sourceId, {
        'status': ragSourceStatusToString(RagSourceStatus.failed),
        'errorMessage': err.message,
        'chunkCount': 0,
      });
      try {
        await _chunks.setPublishedForSource(sourceId, false);
      } catch (_) {}
      throw err;
    }
  }

  /// Chunks are student-readable only when the source is published + Ready.
  /// Keeps `where published == true` list queries valid under Firestore rules.
  Future<void> _restoreStudentChunkVisibility(
    String sourceId,
    RagSource source,
  ) async {
    await _chunks.setPublishedForSource(
      sourceId,
      source.published && source.status == RagSourceStatus.ready,
    );
  }

  Future<void> setPublished(RagSource source, bool published) async {
    await _sources.patch(source.id, {'published': published});
    final live = await _sources.get(source.id);
    final status = live?.status ?? source.status;
    await _chunks.setPublishedForSource(
      source.id,
      published && status == RagSourceStatus.ready,
    );
  }

  /// Drops indexed chunks but keeps the source row as Draft (not a hard delete).
  Future<void> removeFromRag(RagSource source) async {
    await _chunks.deleteForSource(source.id);
    await _sources.patch(source.id, {
      'status': ragSourceStatusToString(RagSourceStatus.uploading),
      'published': false,
      'chunkCount': 0,
      'errorMessage': '',
      'needsReindex': false,
    });
  }

  /// Deletes chunks, then the source, then the Storage object only when the
  /// RAG module uploaded it (`ownsFile`). Linked notes/PYQ/CA files stay.
  Future<void> deleteSourceSafely(RagSource source) async {
    await _chunks.deleteForSource(source.id);
    if (source.ownsFile && source.fileUrl.trim().isNotEmpty) {
      await _storage.deleteByUrl(source.fileUrl);
    }
    await _sources.delete(source.id);
  }

  Future<List<RagExtractedPage>> _extractPages(
    RagSource source, {
    String? inlineText,
  }) async {
    final typed = (inlineText ?? '').trim();
    if (typed.isNotEmpty) {
      return [RagExtractedPage(text: typed)];
    }

    switch (source.sourceType) {
      case RagSourceType.pdf:
        if (source.fileUrl.trim().isEmpty) {
          throw RagException.pdfExtraction('No PDF URL on this source.');
        }
        return _backend.extractPdf(
          fileUrl: source.fileUrl,
          title: source.title,
        );
      case RagSourceType.text:
        throw RagException.emptyDoc('No text was provided for this source.');
      case RagSourceType.notes:
      case RagSourceType.pyq:
      case RagSourceType.currentAffairs:
      case RagSourceType.chapter:
        final text = await collectLinkedText(source);
        if (cleanRagText(text).isEmpty) {
          throw RagException.emptyDoc(
            'Linked ${ragSourceTypeLabel(source.sourceType)} has no indexable text.',
          );
        }
        return [RagExtractedPage(text: text)];
    }
  }

  Future<List<List<double>>> _embedAll(List<String> texts) async {
    const batchSize = 16;
    final out = <List<double>>[];
    for (var i = 0; i < texts.length; i += batchSize) {
      final slice = texts.sublist(
        i,
        i + batchSize > texts.length ? texts.length : i + batchSize,
      );
      try {
        final rows = await _backend.embed(texts: slice, task: 'document');
        out.addAll(rows);
      } catch (e) {
        throw RagException.embedding('$e');
      }
    }
    if (out.length != texts.length) {
      throw RagException.embedding('Incomplete embedding batch.');
    }
    return out;
  }

  /// Pulls text from existing curriculum collections — does not duplicate them.
  Future<String> collectLinkedText(RagSource source) async {
    final linkedId = source.linkedId.trim();
    switch (source.sourceType) {
      case RagSourceType.notes:
        return _notesText(linkedId, source.chapterId);
      case RagSourceType.pyq:
        return _pyqText(linkedId);
      case RagSourceType.currentAffairs:
        return _caText(linkedId);
      case RagSourceType.chapter:
        return _chapterText(linkedId, source.chapterId);
      case RagSourceType.pdf:
      case RagSourceType.text:
        return '';
    }
  }

  Future<String> _notesText(String noteId, String chapterId) async {
    NoteItem? note;
    if (noteId.isNotEmpty) {
      final snap = await _firestore
          .collection(NotesRepository.notesCollection)
          .doc(noteId)
          .get();
      if (snap.exists && snap.data() != null) {
        note = NoteItem.fromMap(snap.data()!, snap.id);
      }
    }
    note ??= chapterId.isEmpty
        ? null
        : await _notes.getNoteForChapter(chapterId);
    if (note == null) return '';
    return _formatNote(note);
  }

  String _formatNote(NoteItem note) {
    final buf = StringBuffer();
    if (note.title.trim().isNotEmpty) buf.writeln(note.title);
    if (note.contentMarkdown.trim().isNotEmpty) {
      buf.writeln(note.contentMarkdown);
    }
    for (final p in note.importantPoints) {
      if (p.trim().isNotEmpty) buf.writeln('- $p');
    }
    for (final p in note.revisionSummary) {
      if (p.trim().isNotEmpty) buf.writeln('- $p');
    }
    if (note.aiSummary.trim().isNotEmpty) buf.writeln(note.aiSummary);
    if (note.pdfStructuredBlocks.isNotEmpty) {
      buf.writeln(pdfBlocksToStructuredDocument(note.pdfStructuredBlocks));
    }
    return buf.toString();
  }

  Future<String> _pyqText(String pyqId) async {
    if (pyqId.isEmpty) return '';
    final items = await _pyqs.watchAll().first;
    PyqItem? match;
    for (final p in items) {
      if (p.id == pyqId) {
        match = p;
        break;
      }
    }
    if (match == null) return '';
    return match.searchableText;
  }

  Future<String> _caText(String id) async {
    if (id.isEmpty) return '';
    final items = await _currentAffairs.watchAll().first;
    CurrentAffairItem? match;
    for (final p in items) {
      if (p.id == id) {
        match = p;
        break;
      }
    }
    if (match == null) return '';
    return '${match.title}\n${match.category}\n${match.description}\n'
        '${match.detailedExplanation}\n${match.source}';
  }

  Future<String> _chapterText(String chapterIdOrLinked, String chapterId) async {
    final id = chapterIdOrLinked.isNotEmpty ? chapterIdOrLinked : chapterId;
    if (id.isEmpty) return '';
    final snap = await _firestore
        .collection(NotesRepository.chaptersCollection)
        .doc(id)
        .get();
    if (!snap.exists || snap.data() == null) return '';
    final chapter = ChapterItem.fromMap(snap.data()!, snap.id);
    final buf = StringBuffer()
      ..writeln(chapter.title)
      ..writeln(chapter.titleEn)
      ..writeln(chapter.description)
      ..writeln(chapter.aiSummary)
      ..writeln(chapter.revisionNotes);
    final note = await _notes.getNoteForChapter(chapter.id);
    if (note != null) buf.writeln(_formatNote(note));
    return buf.toString();
  }
}

final RagProcessingService ragProcessingService = RagProcessingService();
