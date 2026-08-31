import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/rag_processing_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';

/// Sends a notes PDF through the *existing* RAG pipeline
/// (extract → clean → chunk → embed). Never creates a second engine.
class NoteRagIndexer {
  NoteRagIndexer({
    NotesRepository? notes,
    RagSourceRepository? sources,
    RagProcessingService? processing,
  })  : _notes = notes ?? notesRepository,
        _sources = sources ?? ragSourceRepository,
        _processing = processing ?? ragProcessingService;

  final NotesRepository _notes;
  final RagSourceRepository _sources;
  final RagProcessingService _processing;

  /// Index (or retry) the original PDF attached to [note].
  ///
  /// Student-facing RAG only receives the source when the note is published.
  Future<NoteItem> indexNote(
    NoteItem note, {
    bool force = false,
    String subjectTitle = '',
    String chapterTitle = '',
    String examTitle = '',
  }) async {
    if (note.id.isEmpty) {
      throw StateError('Save the note before indexing RAG.');
    }
    if (note.pdfUrl.trim().isEmpty) {
      await _notes.patchNote(note.id, {
        'ragStatus': noteRagStatusToString(NoteRagStatus.notIndexed),
        'ragError': 'No PDF to index.',
      });
      return (await _notes.getNote(note.id)) ?? note;
    }

    await _notes.patchNote(note.id, {
      'ragStatus': noteRagStatusToString(NoteRagStatus.processing),
      'ragError': '',
    });

    final existing = note.ragSourceId.isNotEmpty
        ? await _sources.get(note.ragSourceId)
        : await _sources.findLinked(
            collection: NotesRepository.notesCollection,
            linkedId: note.id,
          );

    String uid = '';
    try {
      uid = authService.currentUser?.uid ?? '';
    } catch (_) {}
    final source = RagSource(
      id: existing?.id ?? '',
      title: note.title.isNotEmpty ? note.title : chapterTitle,
      subject: subjectTitle,
      subjectId: note.subjectId,
      chapter: chapterTitle,
      chapterId: note.chapterId,
      exam: examTitle.isNotEmpty ? examTitle : kMpscDefaultExam,
      fileUrl: note.pdfUrl,
      storagePath: note.pdfStoragePath,
      uploadedBy: existing?.uploadedBy.isNotEmpty == true
          ? existing!.uploadedBy
          : uid,
      createdAt: existing?.createdAt ?? DateTime.now(),
      status: RagSourceStatus.processing,
      published: note.isStudentVisible,
      sourceType: RagSourceType.pdf,
      language: note.language,
      linkedCollection: NotesRepository.notesCollection,
      linkedId: note.id,
      ownsFile: false,
      examId: note.examId.isNotEmpty ? note.examId : kDefaultExamId,
      topicId: note.resolvedTopicId,
      noteId: note.id,
      contentType: kNotesPdfContentType,
      source: note.source,
      difficulty: note.difficulty,
      contentStatus: noteWorkflowStatusToString(note.status),
      ragDomain: ragDomainToString(RagDomain.notes),
    );

    try {
      final sourceId = existing == null
          ? await _sources.create(source)
          : existing.id;
      if (existing != null) {
        await _sources.update(source.copyWith());
      }
      await _notes.patchNote(note.id, {'ragSourceId': sourceId});

      final processed = await _processing.processSource(sourceId, force: force);
      await _processing.setPublished(processed, note.isStudentVisible);

      await _notes.patchNote(note.id, {
        'ragStatus': noteRagStatusToString(NoteRagStatus.indexed),
        'ragSourceId': sourceId,
        'ragError': '',
        if (processed.language.isNotEmpty && note.language.isEmpty)
          'language': processed.language,
      });
    } catch (e) {
      await _notes.patchNote(note.id, {
        'ragStatus': noteRagStatusToString(NoteRagStatus.failed),
        'ragError': e.toString(),
      });
      rethrow;
    }

    return (await _notes.getNote(note.id)) ?? note;
  }

  /// Publish flag on the linked RAG source follows note visibility.
  Future<void> syncPublished(NoteItem note) async {
    final id = note.ragSourceId.trim();
    if (id.isEmpty) return;
    final source = await _sources.get(id);
    if (source == null) return;
    await _processing.setPublished(source, note.isStudentVisible);
  }

  Future<NoteItem> retry(
    NoteItem note, {
    String subjectTitle = '',
    String chapterTitle = '',
    String examTitle = '',
  }) {
    return indexNote(
      note,
      force: true,
      subjectTitle: subjectTitle,
      chapterTitle: chapterTitle,
      examTitle: examTitle,
    );
  }
}

final NoteRagIndexer noteRagIndexer = NoteRagIndexer();
