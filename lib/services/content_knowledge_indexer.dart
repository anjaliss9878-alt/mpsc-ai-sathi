import 'package:mpsc_combine_ai/models/ai_teacher_content_item.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/current_affair_item.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/flashcard_item.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/models/smart_trick_item.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_content_repository.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/flashcard_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/rag_processing_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';
import 'package:mpsc_combine_ai/services/smart_trick_repository.dart';

/// Indexes Flashcards / Smart Tricks / Current Affairs / AI lessons / PYQs /
/// syllabus chapters into the *existing* RAG pipeline. Drafts are never
/// student-facing knowledge. Does not create a second engine.
class ContentKnowledgeIndexer {
  ContentKnowledgeIndexer({
    RagSourceRepository? sources,
    RagProcessingService? processing,
  })  : _sources = sources ?? ragSourceRepository,
        _processing = processing ?? ragProcessingService;

  final RagSourceRepository _sources;
  final RagProcessingService _processing;

  Future<void> syncFlashcard(FlashcardItem item) {
    return syncText(
      collection: FlashcardRepository.collection,
      linkedId: item.id,
      title: item.title.isNotEmpty ? item.title : item.front,
      text: '${item.front}\n${item.back}\n${item.explanation}',
      examId: item.examId,
      subjectId: item.subjectId,
      chapterId: item.chapterId,
      topicId: item.topicId,
      contentType: kFlashcardContentType,
      language: item.language,
      studentVisible: item.isStudentVisible,
      sourceType: RagSourceType.text,
      difficulty: item.difficulty,
      contentStatus: noteWorkflowStatusToString(item.status),
      ragDomain: ragDomainToString(RagDomain.notes),
    );
  }

  Future<void> syncSmartTrick(SmartTrickItem item) {
    return syncText(
      collection: SmartTrickRepository.collection,
      linkedId: item.id,
      title: item.title.isNotEmpty ? item.title : item.concept,
      text:
          '${item.concept}\n${item.memoryTrick}\n${item.explanation}\n${item.example}',
      examId: item.examId,
      subjectId: item.subjectId,
      chapterId: item.chapterId,
      topicId: item.topicId,
      contentType: kSmartTrickContentType,
      language: item.language,
      studentVisible: item.isStudentVisible,
      sourceType: RagSourceType.text,
      contentStatus: noteWorkflowStatusToString(item.status),
      ragDomain: ragDomainToString(RagDomain.notes),
    );
  }

  Future<void> syncCurrentAffair(CurrentAffairItem item) {
    return syncText(
      collection: CurrentAffairsRepository.collection,
      linkedId: item.id,
      title: item.title,
      text:
          '${item.title}\n${item.category}\n${item.description}\n${item.detailedExplanation}\n${item.source}',
      examId: item.examId,
      subjectId: item.subjectId,
      chapterId: item.chapterId,
      topicId: item.topicId,
      contentType: kCurrentAffairsContentType,
      language: item.language,
      studentVisible: item.isStudentVisible,
      sourceType: RagSourceType.currentAffairs,
      source: item.source,
      year: item.date.year,
      contentStatus: noteWorkflowStatusToString(item.status),
      ragDomain: ragDomainToString(RagDomain.currentAffairs),
    );
  }

  Future<void> syncAiLesson(AiTeacherContentItem item) {
    return syncText(
      collection: AiTeacherContentRepository.collection,
      linkedId: item.id,
      title: item.lessonTitle,
      text: item.lessonContentText,
      examId: item.examId,
      subjectId: item.subjectId,
      chapterId: item.chapterId,
      topicId: item.topicId,
      contentType: kAiLessonContentType,
      language: item.language,
      studentVisible: item.isStudentVisible,
      sourceType: RagSourceType.text,
      contentStatus: noteWorkflowStatusToString(item.status),
      ragDomain: ragDomainToString(RagDomain.aiTeacher),
    );
  }

  /// Index a saved PYQ into the existing pipeline. Same linked row is reused
  /// on update (no duplicate sources). Ready + published only after embed.
  Future<RagSource?> syncPyq(PyqItem item, {bool force = false}) {
    return _upsertIndexedText(
      collection: PyqRepository.collection,
      linkedId: item.id,
      title: item.title.isNotEmpty ? item.title : item.question,
      text: item.searchableText,
      examId: item.examId,
      subjectId: item.subjectId,
      chapterId: item.chapterId,
      topicId: item.topicId,
      contentType: kPyqContentType,
      studentVisible: item.isStudentVisible,
      sourceType: RagSourceType.pyq,
      source: item.source,
      year: item.year,
      difficulty: item.difficulty,
      contentStatus: noteWorkflowStatusToString(item.status),
      ragDomain: ragDomainToString(RagDomain.pyq),
      subjectTitle: item.subject,
      force: force,
    );
  }

  /// Index a saved chapter or topic as syllabus RAG. Notes PDF stays on the
  /// notes indexer; this is outline text only.
  Future<RagSource?> syncSyllabus(ChapterItem item, {bool force = false}) {
    final isTopic = !item.isGroupingChapter;
    return _upsertIndexedText(
      collection: NotesRepository.chaptersCollection,
      linkedId: item.id,
      title: item.title,
      text: item.searchableText,
      examId: item.examId,
      subjectId: item.subjectId,
      chapterId: isTopic && item.parentChapterId.isNotEmpty
          ? item.parentChapterId
          : item.id,
      topicId: isTopic ? item.id : '',
      contentType: kSyllabusContentType,
      studentVisible: item.published,
      sourceType: RagSourceType.chapter,
      ragDomain: ragDomainToString(RagDomain.syllabus),
      chapterTitle: item.title,
      force: force,
    );
  }

  /// Drops the linked RAG source + chunks (content delete).
  Future<void> removeLinked({
    required String collection,
    required String linkedId,
  }) async {
    final existing = await _sources.findLinked(
      collection: collection,
      linkedId: linkedId,
    );
    if (existing == null) return;
    await _processing.deleteSourceSafely(existing);
  }

  /// Removes syllabus RAG for a chapter/topic and any child topics indexed
  /// under that chapter id.
  Future<void> removeSyllabusNode(String nodeId) async {
    if (nodeId.isEmpty) return;
    final all = await _sources.watchAll().first;
    for (final row in all) {
      if (row.linkedCollection != NotesRepository.chaptersCollection) {
        continue;
      }
      if (row.linkedId == nodeId || row.chapterId == nodeId) {
        await _processing.deleteSourceSafely(row);
      }
    }
  }

  Future<RagSource?> retryPyq(PyqItem item) => syncPyq(item, force: true);

  Future<RagSource?> retrySyllabus(ChapterItem item) =>
      syncSyllabus(item, force: true);

  /// Upsert one linked source, embed via [RagProcessingService], then publish
  /// only when [studentVisible]. Does not replace [syncText] (CA / flashcards).
  Future<RagSource?> _upsertIndexedText({
    required String collection,
    required String linkedId,
    required String title,
    required String text,
    required String examId,
    required String subjectId,
    required String chapterId,
    required String topicId,
    required String contentType,
    required bool studentVisible,
    RagSourceType sourceType = RagSourceType.text,
    String source = '',
    int? year,
    String difficulty = '',
    String contentStatus = '',
    String ragDomain = '',
    String subjectTitle = '',
    String chapterTitle = '',
    bool force = false,
  }) async {
    if (linkedId.isEmpty) return null;

    final existing = await _sources.findLinked(
      collection: collection,
      linkedId: linkedId,
    );

    if (!studentVisible && existing != null) {
      await _processing.setPublished(existing, false);
    }

    final body = text.trim();
    if (body.isEmpty) {
      if (existing != null) {
        await _processing.setPublished(existing, false);
      }
      return existing;
    }

    String uid = '';
    try {
      uid = authService.currentUser?.uid ?? '';
    } catch (_) {}

    final row = RagSource(
      id: existing?.id ?? '',
      title: title,
      subject: subjectTitle,
      subjectId: subjectId,
      chapter: chapterTitle,
      chapterId: chapterId,
      exam: kMpscDefaultExam,
      fileUrl: '',
      uploadedBy:
          existing?.uploadedBy.isNotEmpty == true ? existing!.uploadedBy : uid,
      createdAt: existing?.createdAt ?? DateTime.now(),
      status: RagSourceStatus.processing,
      published: false,
      sourceType: sourceType,
      linkedCollection: collection,
      linkedId: linkedId,
      ownsFile: false,
      examId: examId.isEmpty ? kDefaultExamId : examId,
      topicId: topicId,
      contentType: contentType,
      source: source,
      year: year,
      difficulty: difficulty,
      contentStatus: contentStatus,
      ragDomain: ragDomain.isNotEmpty
          ? ragDomain
          : ragDomainToString(
              inferRagDomain(
                contentType: contentType,
                sourceType: ragSourceTypeToString(sourceType),
                linkedCollection: collection,
              ),
            ),
    );

    try {
      final sourceId =
          existing == null ? await _sources.create(row) : existing.id;
      if (existing != null) {
        await _sources.update(row);
      }
      final processed = await _processing.processSource(
        sourceId,
        inlineText: body,
        force: force,
      );
      await _processing.setPublished(processed, studentVisible);
      return (await _sources.get(sourceId)) ?? processed;
    } catch (e) {
      final failed = await _sources.findLinked(
        collection: collection,
        linkedId: linkedId,
      );
      if (failed != null) {
        try {
          await _processing.setPublished(failed, false);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Upsert a linked RAG source and process only when [studentVisible].
  /// Draft/unpublished content is unpublished on the source if one exists.
  Future<void> syncText({
    required String collection,
    required String linkedId,
    required String title,
    required String text,
    required String examId,
    required String subjectId,
    required String chapterId,
    required String topicId,
    required String contentType,
    required bool studentVisible,
    String language = '',
    RagSourceType sourceType = RagSourceType.text,
    String source = '',
    int? year,
    String difficulty = '',
    String contentStatus = '',
    String ragDomain = '',
  }) async {
    if (linkedId.isEmpty) return;

    final existing = await _sources.findLinked(
      collection: collection,
      linkedId: linkedId,
    );

    if (!studentVisible) {
      if (existing != null) {
        await _processing.setPublished(existing, false);
      }
      return;
    }

    final body = text.trim();
    if (body.isEmpty) return;

    String uid = '';
    try {
      uid = authService.currentUser?.uid ?? '';
    } catch (_) {}

    final row = RagSource(
      id: existing?.id ?? '',
      title: title,
      subject: '',
      subjectId: subjectId,
      chapter: '',
      chapterId: chapterId,
      exam: kMpscDefaultExam,
      fileUrl: '',
      uploadedBy:
          existing?.uploadedBy.isNotEmpty == true ? existing!.uploadedBy : uid,
      createdAt: existing?.createdAt ?? DateTime.now(),
      status: RagSourceStatus.processing,
      published: true,
      sourceType: sourceType,
      language: language,
      linkedCollection: collection,
      linkedId: linkedId,
      ownsFile: false,
      examId: examId.isEmpty ? kDefaultExamId : examId,
      topicId: topicId,
      contentType: contentType,
      source: source,
      year: year,
      difficulty: difficulty,
      contentStatus: contentStatus,
      ragDomain: ragDomain.isNotEmpty
          ? ragDomain
          : ragDomainToString(
              inferRagDomain(
                contentType: contentType,
                sourceType: ragSourceTypeToString(sourceType),
                linkedCollection: collection,
              ),
            ),
    );

    try {
      final sourceId = existing == null
          ? await _sources.create(row)
          : existing.id;
      if (existing != null) {
        await _sources.update(row);
      }
      final processed = await _processing.processSource(
        sourceId,
        inlineText: body,
      );
      await _processing.setPublished(processed, true);
    } catch (_) {
      if (existing != null) {
        try {
          await _processing.setPublished(existing, false);
        } catch (_) {}
      }
    }
  }
}

final ContentKnowledgeIndexer contentKnowledgeIndexer =
    ContentKnowledgeIndexer();
