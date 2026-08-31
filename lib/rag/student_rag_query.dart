import 'package:mpsc_combine_ai/models/multi_rag_result.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_router.dart';
import 'package:mpsc_combine_ai/services/student_rag_context.dart';

/// Weak-topic study pack always searches notes + PYQ + syllabus — not a
/// second database.
const List<RagDomain> kWeakTopicStudyDomains = [
  RagDomain.notes,
  RagDomain.pyq,
  RagDomain.syllabus,
];

class StudentRagQueryPlan {
  const StudentRagQueryPlan({
    required this.domains,
    this.examId = '',
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
    this.performance = const [],
    this.includePerformance = false,
    this.reason = '',
  });

  final List<RagDomain> domains;
  final String examId;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final List<StudentPerformanceRecord> performance;
  final bool includePerformance;
  final String reason;
}

/// Chooses Multi-RAG domains from the question + optional student snapshot.
/// Student performance is attached only when it is relevant.
StudentRagQueryPlan planStudentRagQuery({
  required String question,
  StudentRagContext? student,
  bool fromAiTeacher = false,
  String examId = '',
  String subjectId = '',
  String chapterId = '',
  String topicId = '',
  bool forceWeakTopicStudy = false,
}) {
  final weak = student?.matchWeakTopic(
    question: question,
    subjectId: subjectId,
    chapterId: chapterId,
    topicId: topicId,
  );
  final exam = examId.isNotEmpty ? examId : (student?.examId ?? '');
  final weaknessQuestion = ragQueryIsWeakness(question);

  if (forceWeakTopicStudy ||
      (weak != null && !weaknessQuestion && !fromAiTeacher)) {
    return StudentRagQueryPlan(
      domains: kWeakTopicStudyDomains,
      examId: exam,
      subjectId: (weak?.subjectId.isNotEmpty ?? false)
          ? weak!.subjectId
          : subjectId,
      chapterId: (weak?.chapterId.isNotEmpty ?? false)
          ? weak!.chapterId
          : chapterId,
      topicId: topicId.isNotEmpty ? topicId : (weak?.chapterId ?? ''),
      includePerformance: false,
      reason: 'weak_topic_study',
    );
  }

  if (student != null && weaknessQuestion) {
    return StudentRagQueryPlan(
      domains: const [RagDomain.studentPerformance, RagDomain.notes],
      examId: exam,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      performance: student.performance,
      includePerformance: true,
      reason: 'weakness_intent',
    );
  }

  if (fromAiTeacher) {
    return StudentRagQueryPlan(
      domains: weak != null
          ? const [
              RagDomain.aiTeacher,
              RagDomain.notes,
              RagDomain.syllabus,
            ]
          : const [RagDomain.aiTeacher, RagDomain.notes],
      examId: exam,
      subjectId: (weak?.subjectId.isNotEmpty ?? false)
          ? weak!.subjectId
          : subjectId,
      chapterId: (weak?.chapterId.isNotEmpty ?? false)
          ? weak!.chapterId
          : chapterId,
      topicId: topicId,
      includePerformance: false,
      reason: weak != null ? 'ai_teacher_weak_topic' : 'ai_teacher',
    );
  }

  return StudentRagQueryPlan(
    domains: const [],
    examId: exam,
    subjectId: subjectId,
    chapterId: chapterId,
    topicId: topicId,
    reason: 'router',
  );
}

MultiRagQuery toMultiRagQuery({
  required String question,
  required StudentRagQueryPlan plan,
  RagRouteContext context = const RagRouteContext(),
}) {
  return MultiRagQuery(
    query: question.trim(),
    context: context,
    domains: plan.domains,
    examId: plan.examId,
    subjectId: plan.subjectId,
    chapterId: plan.chapterId,
    topicId: plan.topicId,
    performance: plan.includePerformance ? plan.performance : const [],
  );
}
