import 'package:mpsc_combine_ai/models/chat_message.dart';
import 'package:mpsc_combine_ai/models/multi_rag_result.dart';
import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/models/rag_monitor_event.dart';
import 'package:mpsc_combine_ai/models/rag_study_pack.dart';
import 'package:mpsc_combine_ai/rag/rag_confidence.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_router.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/rag/student_rag_query.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/multi_rag_retrieval.dart';
import 'package:mpsc_combine_ai/services/rag_grounded_learning_service.dart';
import 'package:mpsc_combine_ai/services/rag_monitor.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';
import 'package:mpsc_combine_ai/services/student_rag_context.dart';

/// Grounded study pack for a weak topic. Generated from retrieved notes / PYQ /
/// syllabus only — never from stored student scores.
class PersonalizedStudyPack {
  const PersonalizedStudyPack({
    required this.explanation,
    required this.revision,
    required this.mcqs,
    required this.pyqs,
    required this.tricks,
    required this.flashcards,
    required this.monitor,
  });

  final RagTeacherAnswer explanation;
  final RagQuickRevision revision;
  final List<RagGeneratedMcq> mcqs;
  final List<RagVerifiedPyq> pyqs;
  final List<RagMemoryTrick> tricks;
  final List<RagFlashcard> flashcards;
  final RagMonitorEvent monitor;
}

/// Connects existing student personalization (profile, syllabus, tests, MCQs,
/// weakness, planner signals) to Multi-RAG without replacing those systems.
class PersonalizedMultiRagService {
  PersonalizedMultiRagService({
    StudentRagContextService? context,
    MultiRagRetriever? retrieval,
    RagGroundedLearningService? grounded,
    RagMonitor? monitor,
  })  : _context = context ?? studentRagContextService,
        _retrieval = retrieval ?? multiRagRetrievalService,
        _grounded = grounded ?? ragGroundedLearningService,
        _monitor = monitor ?? ragMonitor;

  final StudentRagContextService _context;
  final MultiRagRetriever _retrieval;
  final RagGroundedLearningService _grounded;
  final RagMonitor _monitor;

  RagMonitorEvent? get lastMonitorEvent => _monitor.last;

  Future<RagTeacherAnswer> answer({
    required String uid,
    required String requesterUid,
    required String question,
    List<ChatMessage> history = const [],
    RagSourceFilter filter = RagSourceFilter.allPublished,
    String subjectHint = '',
    bool fromAiTeacher = false,
    String examId = '',
    String subjectId = '',
    String chapterId = '',
    String topicId = '',
  }) async {
    final started = DateTime.now();
    try {
      final student = await _context.load(uid: uid, requesterUid: requesterUid);
      final plan = planStudentRagQuery(
        question: question,
        student: student,
        fromAiTeacher: fromAiTeacher,
        examId: examId.isNotEmpty ? examId : filter.examId,
        subjectId: subjectId.isNotEmpty ? subjectId : filter.subjectId,
        chapterId: chapterId.isNotEmpty ? chapterId : filter.chapterId,
        topicId: topicId.isNotEmpty ? topicId : filter.topicId,
      );
      final retrieved = await _retrieve(
        question: question,
        plan: plan,
        fromAiTeacher: fromAiTeacher,
      );
      final hits = knowledgeHits(retrieved);
      final event = _event(
        uid: uid,
        retrieved: retrieved,
        hits: hits,
        started: started,
        mode: 'answer',
        plan: plan,
        fallbackReason: hits.isEmpty ? 'empty_retrieval' : '',
      );
      await _monitor.record(event);

      if (ragConfidenceBand(retrieved.confidence) == RagConfidenceBand.low ||
          hits.isEmpty) {
        return applyRagConfidence(
          answer: const RagTeacherAnswer(
            markdown: kRagInsufficientEvidence,
            citations: [],
            insufficient: true,
          ),
          confidence: retrieved.confidence,
        );
      }

      final raw = await _grounded.answer(
        question: question,
        history: history,
        filter: filter,
        subjectHint: subjectHint,
        prefetchedHits: hits,
      );
      return applyRagConfidence(answer: raw, confidence: retrieved.confidence);
    } on StudentRagAccessException {
      rethrow;
    } catch (e) {
      await _monitor.record(
        RagMonitorEvent(
          uid: uid,
          domains: const [],
          retrievalCount: 0,
          confidence: 0,
          confidenceBand: RagConfidenceBand.low,
          sourceIds: const [],
          latencyMs: DateTime.now().difference(started).inMilliseconds,
          fallbackReason: 'multi_rag_retrieve_failed',
          mode: 'answer',
        ),
      );
      return _grounded.answer(
        question: question,
        history: history,
        filter: filter,
        subjectHint: subjectHint,
      );
    }
  }

  Future<PersonalizedStudyPack> studyPackForWeakTopic({
    required String uid,
    required String requesterUid,
    required String subjectTitle,
    required String topicLabel,
    String subjectId = '',
    String chapterId = '',
    String topicId = '',
    List<ChatMessage> history = const [],
  }) async {
    final started = DateTime.now();
    final student = await _context.load(uid: uid, requesterUid: requesterUid);
    final question = '$subjectTitle → $topicLabel';
    final plan = planStudentRagQuery(
      question: question,
      student: student,
      examId: student.examId,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      forceWeakTopicStudy: true,
    );
    final retrieved = await _retrieve(question: question, plan: plan);
    final hits = knowledgeHits(retrieved);
    final event = _event(
      uid: uid,
      retrieved: retrieved,
      hits: hits,
      started: started,
      mode: 'study_pack',
      plan: plan,
      fallbackReason: hits.isEmpty ? 'empty_retrieval' : '',
    );
    await _monitor.record(event);

    if (hits.isEmpty ||
        ragConfidenceBand(retrieved.confidence) == RagConfidenceBand.low) {
      return PersonalizedStudyPack(
        explanation: applyRagConfidence(
          answer: const RagTeacherAnswer(
            markdown: kRagInsufficientEvidence,
            citations: [],
            insufficient: true,
          ),
          confidence: retrieved.confidence,
        ),
        revision: const RagQuickRevision(),
        mcqs: const [],
        pyqs: const [],
        tricks: const [],
        flashcards: const [],
        monitor: event,
      );
    }

    final hint = subjectTitle;
    final explanation = applyRagConfidence(
      answer: await _grounded.answer(
        question: 'Targeted explanation: $question',
        history: history,
        subjectHint: hint,
        prefetchedHits: hits,
      ),
      confidence: retrieved.confidence,
    );
    return PersonalizedStudyPack(
      explanation: explanation,
      revision: await _grounded.quickRevision(
        topic: question,
        history: history,
        subjectHint: hint,
        prefetchedHits: hits,
      ),
      mcqs: await _grounded.mcqs(
        topic: question,
        history: history,
        subjectHint: hint,
        prefetchedHits: hits,
      ),
      pyqs: await _grounded.pyqConnections(
        topic: question,
        history: history,
        prefetchedHits: hits,
      ),
      tricks: await _grounded.memoryTricks(
        topic: question,
        history: history,
        subjectHint: hint,
        prefetchedHits: hits,
      ),
      flashcards: await _grounded.flashcards(
        topic: question,
        history: history,
        subjectHint: hint,
        prefetchedHits: hits,
      ),
      monitor: event,
    );
  }

  Future<List<RagHit>> retrieveKnowledgeHits({
    required String uid,
    required String requesterUid,
    required String question,
    bool fromAiTeacher = false,
    String examId = '',
    String subjectId = '',
    String chapterId = '',
    String topicId = '',
    bool forceWeakTopicStudy = false,
  }) async {
    final student = await _context.load(uid: uid, requesterUid: requesterUid);
    final plan = planStudentRagQuery(
      question: question,
      student: student,
      fromAiTeacher: fromAiTeacher,
      examId: examId,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      forceWeakTopicStudy: forceWeakTopicStudy,
    );
    final retrieved = await _retrieve(
      question: question,
      plan: plan,
      fromAiTeacher: fromAiTeacher,
    );
    return knowledgeHits(retrieved);
  }
  Future<String> lessonNotesSnippet({
    required String uid,
    required String requesterUid,
    required String topic,
    String subjectId = '',
    String chapterId = '',
    String topicId = '',
  }) async {
    try {
      final student = await _context.load(uid: uid, requesterUid: requesterUid);
      final plan = planStudentRagQuery(
        question: topic,
        student: student,
        fromAiTeacher: true,
        subjectId: subjectId,
        chapterId: chapterId,
        topicId: topicId,
      );
      final retrieved = await _retrieve(
        question: topic,
        plan: plan,
        fromAiTeacher: true,
      );
      final notes = [
        for (final hit in retrieved.hits)
          if (hit.domain == RagDomain.notes ||
              hit.domain == RagDomain.syllabus)
            hit.chunk.text.trim(),
      ].where((t) => t.isNotEmpty).take(4);
      if (notes.isEmpty) return '';
      return 'Retrieved RAG notes (weak topic + published sources):\n'
          '${notes.join('\n\n')}';
    } on StudentRagAccessException {
      return '';
    } catch (_) {
      return '';
    }
  }

  Future<MultiRagResult> _retrieve({
    required String question,
    required StudentRagQueryPlan plan,
    bool fromAiTeacher = false,
  }) {
    return _retrieval.retrieve(
      toMultiRagQuery(
        question: question,
        plan: plan,
        context: RagRouteContext(
          fromAiTeacher: fromAiTeacher,
          examId: plan.examId,
          subjectId: plan.subjectId,
          chapterId: plan.chapterId,
          topicId: plan.topicId,
        ),
      ),
    );
  }

  RagMonitorEvent _event({
    required String uid,
    required MultiRagResult retrieved,
    required List<RagHit> hits,
    required DateTime started,
    required String mode,
    required StudentRagQueryPlan plan,
    String fallbackReason = '',
  }) {
    final sourceIds = <String>[];
    final seen = <String>{};
    for (final hit in hits) {
      final id = hit.chunk.sourceId.trim();
      if (id.isEmpty || id == 'student_performance') continue;
      if (seen.add(id)) sourceIds.add(id);
    }
    return RagMonitorEvent(
      uid: uid,
      domains: retrieved.plan.domains,
      retrievalCount: hits.length,
      confidence: retrieved.confidence,
      confidenceBand: ragConfidenceBand(retrieved.confidence),
      sourceIds: sourceIds,
      latencyMs: DateTime.now().difference(started).inMilliseconds,
      fallbackReason: fallbackReason,
      mode: mode,
      examId: plan.examId,
      subjectId: plan.subjectId,
      chapterId: plan.chapterId,
      topicId: plan.topicId,
    );
  }
}

/// Published knowledge hits only — student scores stay out of generation.
List<RagHit> knowledgeHits(MultiRagResult retrieved) {
  return [
    for (final hit in retrieved.hits)
      if (hit.domain != RagDomain.studentPerformance) hit.hit,
  ];
}

final PersonalizedMultiRagService personalizedMultiRagService =
    PersonalizedMultiRagService();

/// Student-app entry: own uid only. Falls back to the existing grounded path.
Future<RagTeacherAnswer> answerWithStudentRag({
  required String question,
  List<ChatMessage> history = const [],
  RagSourceFilter filter = RagSourceFilter.allPublished,
  String subjectHint = '',
  bool fromAiTeacher = false,
  String chapterId = '',
  String subjectId = '',
  String topicId = '',
}) {
  final uid = authService.currentUser?.uid ?? '';
  if (uid.isEmpty) {
    return ragGroundedLearningService.answer(
      question: question,
      history: history,
      filter: filter,
      subjectHint: subjectHint,
    );
  }
  return personalizedMultiRagService.answer(
    uid: uid,
    requesterUid: uid,
    question: question,
    history: history,
    filter: filter,
    subjectHint: subjectHint,
    fromAiTeacher: fromAiTeacher,
    subjectId: subjectId,
    chapterId: chapterId,
    topicId: topicId,
  );
}
