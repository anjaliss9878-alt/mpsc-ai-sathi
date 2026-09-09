import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/models/rag_study_pack.dart';
import 'package:mpsc_combine_ai/models/study_content_pack.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/rag_grounded_learning_service.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';
import 'package:mpsc_combine_ai/services/study_pack_repository.dart';

/// In-memory Study Content session: one retrieval, then grounded follow-ups.
class StudyContentSession {
  StudyContentSession({
    required this.topic,
    required this.hits,
    required this.notes,
    required this.insufficient,
    this.subjectTitle = '',
    this.subjectId = '',
    this.chapterId = '',
    this.examId = kDefaultExamId,
    this.topicId = '',
    this.mcqs,
    this.pyqs,
    this.revision,
    this.explanation,
  });

  factory StudyContentSession.insufficient({
    required String topic,
    String subjectTitle = '',
    String subjectId = '',
    String chapterId = '',
    String examId = kDefaultExamId,
    String topicId = '',
  }) {
    return StudyContentSession(
      topic: topic,
      hits: const [],
      notes: const RagSourceSummary(
        detailed: kStudyContentInsufficient,
        shortNotes: kStudyContentInsufficient,
        fiveMinuteRevision: kStudyContentInsufficient,
      ),
      insufficient: true,
      subjectTitle: subjectTitle,
      subjectId: subjectId,
      chapterId: chapterId,
      examId: examId,
      topicId: topicId,
    );
  }

  final String topic;
  final List<RagHit> hits;
  final RagSourceSummary notes;
  final bool insufficient;
  final String subjectTitle;
  final String subjectId;
  final String chapterId;
  final String examId;
  final String topicId;
  List<RagGeneratedMcq>? mcqs;
  List<RagVerifiedPyq>? pyqs;
  RagQuickRevision? revision;
  RagTeacherAnswer? explanation;

  List<String> get sourceIds => [
        for (final h in hits)
          if (h.chunk.sourceId.isNotEmpty) h.chunk.sourceId,
      ].toSet().toList();
}

/// Composes existing RAG retrieve + /rag/learn. Never falls back to generic Gemini.
class StudyContentSessionService {
  StudyContentSessionService({
    RagRetrievalService? retrieval,
    RagGroundedLearningService? grounded,
    StudyPackRepository? packs,
    NotesRepository? notes,
  })  : _retrieval = retrieval ?? ragRetrievalService,
        _grounded = grounded ?? ragGroundedLearningService,
        _packs = packs ?? studyPackRepository,
        _notes = notes ?? notesRepository;

  final RagRetrievalService _retrieval;
  final RagGroundedLearningService _grounded;
  final StudyPackRepository _packs;
  final NotesRepository _notes;

  static String examNotesQuestion(String topic) {
    return 'MPSC Group B exam-oriented notes for: $topic. '
        'Structure detailed notes with: Exam Focus; Core Concept; Important Facts; '
        'Comparison/differences where the evidence supports it; Confusing points/traps; '
        'PYQ connection only if present in the chunks; probable MCQs; and a 2-minute revision. '
        'Use only the retrieved approved material. Do not use generic textbook knowledge.';
  }

  static String explanationQuestion(String topic) {
    return 'Explain this MPSC Combine topic for exam answers: $topic';
  }

  Future<StudyContentSession> open({
    required String topic,
    String subjectTitle = '',
    String subjectId = '',
    String chapterId = '',
    String examId = '',
    String topicId = '',
  }) async {
    final q = topic.trim();
    if (q.isEmpty) {
      return StudyContentSession.insufficient(topic: topic);
    }

    var hits = await _retrieval.retrieve(
      query: q,
      filter: RagSourceFilter(
        onlyPublishedReady: true,
        topK: 12,
        examId: examId,
        subjectId: subjectId,
        chapterId: chapterId,
        topicId: topicId,
        scope: subjectId.isNotEmpty || chapterId.isNotEmpty
            ? RagSourceScope.subjectChapter
            : RagSourceScope.allPublished,
      ),
    );
    // New Group B chapter/topic ids often do not match older Ready sources.
    // Retry all published+Ready evidence rather than falling back to Gemini.
    if (hits.isEmpty &&
        (subjectId.isNotEmpty ||
            chapterId.isNotEmpty ||
            topicId.isNotEmpty ||
            examId.isNotEmpty)) {
      hits = await _retrieval.retrieve(
        query: q,
        filter: const RagSourceFilter(
          onlyPublishedReady: true,
          topK: 12,
        ),
      );
    }
    if (hits.isEmpty) {
      return StudyContentSession.insufficient(
        topic: q,
        subjectTitle: subjectTitle,
        subjectId: subjectId,
        chapterId: chapterId,
        examId: examId,
        topicId: topicId,
      );
    }

    final notes = await _grounded.summary(
      topic: examNotesQuestion(q),
      subjectHint: subjectTitle,
      prefetchedHits: hits,
    );
    if (_summaryInsufficient(notes)) {
      return StudyContentSession.insufficient(
        topic: q,
        subjectTitle: subjectTitle,
        subjectId: subjectId,
        chapterId: chapterId,
        examId: examId,
        topicId: topicId,
      );
    }

    return StudyContentSession(
      topic: q,
      hits: hits,
      notes: notes,
      insufficient: false,
      subjectTitle: subjectTitle,
      subjectId: subjectId,
      chapterId: chapterId,
      examId: examId,
      topicId: topicId,
    );
  }

  Future<List<RagGeneratedMcq>> loadMcqs(StudyContentSession session) async {
    if (session.insufficient || session.hits.isEmpty) return const [];
    if (session.mcqs != null) return session.mcqs!;
    final items = await _grounded.mcqs(
      topic: session.topic,
      subjectHint: session.subjectTitle,
      prefetchedHits: session.hits,
    );
    session.mcqs = items;
    return items;
  }

  Future<List<RagVerifiedPyq>> loadPyqs(StudyContentSession session) async {
    if (session.insufficient || session.hits.isEmpty) return const [];
    if (session.pyqs != null) return session.pyqs!;
    final items = await _grounded.pyqConnections(
      topic: session.topic,
      prefetchedHits: session.hits,
    );
    session.pyqs = items;
    return items;
  }

  Future<RagQuickRevision> loadRevision(StudyContentSession session) async {
    if (session.insufficient || session.hits.isEmpty) {
      return const RagQuickRevision();
    }
    if (session.revision != null) return session.revision!;
    final revision = await _grounded.quickRevision(
      topic: session.topic,
      subjectHint: session.subjectTitle,
      prefetchedHits: session.hits,
    );
    session.revision = revision;
    return revision;
  }

  Future<RagTeacherAnswer> loadExplanation(
    StudyContentSession session,
  ) async {
    if (session.insufficient || session.hits.isEmpty) {
      return const RagTeacherAnswer(
        markdown: kStudyContentInsufficient,
        citations: [],
        insufficient: true,
      );
    }
    if (session.explanation != null) return session.explanation!;
    final answer = await _grounded.answer(
      question: explanationQuestion(session.topic),
      subjectHint: session.subjectTitle,
      prefetchedHits: session.hits,
    );
    session.explanation = answer;
    return answer;
  }

  /// Student → admin review inbox. Never writes a published note.
  Future<String> submitForAdminReview(StudyContentSession session) async {
    if (session.insufficient) {
      throw StateError(kStudyContentInsufficient);
    }
    final uid = authService.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      throw StateError('Sign in to submit notes for admin review.');
    }
    final pack = StudyContentPack(
      id: '',
      uid: uid,
      topic: session.topic,
      subjectTitle: session.subjectTitle,
      subjectId: session.subjectId,
      chapterId: session.chapterId,
      examId: session.examId,
      insufficient: false,
      detailedNotes: session.notes.detailed,
      shortNotes: session.notes.shortNotes,
      fiveMinuteRevision: session.notes.fiveMinuteRevision,
      importantFacts: session.notes.importantFacts,
      examPoints: session.notes.examPoints,
      commonMistakes: session.notes.commonMistakes,
      citations: session.notes.citations,
      sourceIds: session.sourceIds,
      status: StudyPackReviewStatus.pendingReview,
      published: false,
      createdAt: DateTime.now(),
    );
    return _packs.submit(pack);
  }

  /// Admin: copy pack into `notes` as draft. Never publishes.
  Future<String> savePackAsNotesDraft(StudyContentPack pack) async {
    if (pack.insufficient || pack.detailedNotes.trim().isEmpty) {
      throw StateError(kStudyContentInsufficient);
    }
    final markdown = _draftMarkdown(pack);
    final noteId = await _notes.saveNote(
      subjectId: pack.subjectId,
      chapterId: pack.chapterId,
      examId: pack.examId.isEmpty ? kDefaultExamId : pack.examId,
      topicId: pack.chapterId,
      title: pack.topic,
      description: 'AI Study Content draft — review before publishing.',
      source: 'AI Study Content (unreviewed)',
      importantPoints: pack.importantFacts,
      revisionSummary: pack.examPoints.isNotEmpty
          ? pack.examPoints
          : pack.shortNotes
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
      contentMarkdown: markdown,
      status: NoteWorkflowStatus.aiGenerated,
      published: false,
      tags: const ['ai-generated', 'study-pack'],
    );
    await _packs.markSavedAsDraft(packId: pack.id, noteId: noteId);
    return noteId;
  }

  static bool _summaryInsufficient(RagSourceSummary notes) {
    final detailed = notes.detailed.trim();
    if (detailed.isEmpty) return true;
    if (detailed == kRagInsufficientEvidence) return true;
    if (detailed == kStudyContentInsufficient) return true;
    return false;
  }

  static String _draftMarkdown(StudyContentPack pack) {
    final citations = pack.citations
        .map((c) => '- ${c.breadcrumb}')
        .where((e) => e.trim().length > 2)
        .join('\n');
    return [
      pack.detailedNotes.trim(),
      if (pack.shortNotes.trim().isNotEmpty) '## Short notes\n${pack.shortNotes.trim()}',
      if (pack.commonMistakes.isNotEmpty)
        '## Common mistakes\n${pack.commonMistakes.map((e) => '- $e').join('\n')}',
      if (citations.isNotEmpty) '## Sources\n$citations',
    ].join('\n\n');
  }
}

final StudyContentSessionService studyContentSessionService =
    StudyContentSessionService();
