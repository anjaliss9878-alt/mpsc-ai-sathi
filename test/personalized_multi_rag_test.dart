import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/chat_message.dart';
import 'package:mpsc_combine_ai/models/daily_study_plan.dart';
import 'package:mpsc_combine_ai/models/multi_rag_result.dart';
import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/models/rag_study_pack.dart';
import 'package:mpsc_combine_ai/rag/rag_confidence.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_router.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/rag/student_rag_query.dart';
import 'package:mpsc_combine_ai/services/ai_weakness_tracker.dart';
import 'package:mpsc_combine_ai/services/daily_planner_service.dart';
import 'package:mpsc_combine_ai/services/multi_rag_retrieval.dart';
import 'package:mpsc_combine_ai/services/personalized_multi_rag_service.dart';
import 'package:mpsc_combine_ai/services/rag_grounded_learning_service.dart';
import 'package:mpsc_combine_ai/services/rag_monitor.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';
import 'package:mpsc_combine_ai/services/student_rag_context.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';

class _FakeRetriever implements MultiRagRetriever {
  _FakeRetriever(this.result);
  MultiRagResult result;

  @override
  Future<MultiRagResult> retrieve(MultiRagQuery query) async => result;
}

class _LearnGrounded extends RagGroundedLearningService {
  _LearnGrounded() : super();

  @override
  Future<RagTeacherAnswer> answer({
    required String question,
    List<ChatMessage> history = const [],
    RagSourceFilter filter = RagSourceFilter.allPublished,
    String subjectHint = '',
    List<RagHit>? prefetchedHits,
  }) async {
    if (prefetchedHits == null || prefetchedHits.isEmpty) {
      return const RagTeacherAnswer(
        markdown: kRagInsufficientEvidence,
        citations: [],
        insufficient: true,
      );
    }
    return RagTeacherAnswer(
      markdown: 'Grounded: ${prefetchedHits.first.chunk.text}',
      citations: [
        RagCitation(
          sourceId: prefetchedHits.first.chunk.sourceId,
          subject: 'Polity',
          chapter: 'Fundamental Rights',
          topic: 'Article 14',
        ),
      ],
      insufficient: false,
    );
  }
}

RagHit _hit({
  required String id,
  required String text,
  String sourceId = 'notes-1',
}) {
  return RagHit(
    chunk: RagChunk(
      id: id,
      sourceId: sourceId,
      sourceTitle: 'Polity notes',
      subject: 'Indian Polity',
      chapter: 'Fundamental Rights',
      exam: 'MPSC Combine',
      text: text,
      embedding: const [1],
      language: 'en',
      sourceType: 'notes',
      published: true,
      ragDomain: ragDomainToString(RagDomain.notes),
      contentType: 'notes',
    ),
    score: 0.9,
  );
}

StudentRagContext _studentA() {
  return StudentRagContext(
    uid: 'student-a',
    examId: 'mpsc_combine',
    targetExam: 'Combine',
    weakTopics: const [
      WeakTopicSignal(
        label: 'Fundamental Rights',
        scorePercent: 32,
        source: 'test',
        subjectId: 'pol',
        chapterId: 'fr',
        subjectTitle: 'Indian Polity',
        priority: 40,
      ),
    ],
    performance: const [
      StudentPerformanceRecord(
        label: 'Fundamental Rights',
        subjectId: 'pol',
        chapterId: 'fr',
        topicId: 'fr',
        scorePercent: 32,
        status: 'weak',
      ),
    ],
  );
}

void main() {
  test('Student A cannot load Student B private performance context', () async {
    final service = StudentRagContextService();
    expect(
      () => service.load(uid: 'student-b', requesterUid: 'student-a'),
      throwsA(isA<StudentRagAccessException>()),
    );
  });

  test('weak topic Indian Polity → Fundamental Rights uses notes + PYQ + syllabus',
      () {
    final plan = planStudentRagQuery(
      question: 'Indian Polity → Fundamental Rights',
      student: _studentA(),
      forceWeakTopicStudy: true,
    );
    expect(plan.domains, kWeakTopicStudyDomains);
    expect(plan.domains, [
      RagDomain.notes,
      RagDomain.pyq,
      RagDomain.syllabus,
    ]);
    expect(plan.includePerformance, isFalse);
    expect(plan.chapterId, 'fr');
    expect(plan.subjectId, 'pol');
  });

  test('student context is skipped for unrelated current-affairs questions', () {
    final plan = planStudentRagQuery(
      question: 'Current affairs Maharashtra today',
      student: _studentA(),
    );
    expect(plan.includePerformance, isFalse);
    expect(plan.domains, isEmpty);
    expect(plan.reason, 'router');
  });

  test('weakness intent attaches only the requesting student performance rows', () {
    final plan = planStudentRagQuery(
      question: 'My weak topics',
      student: _studentA(),
    );
    expect(plan.includePerformance, isTrue);
    expect(plan.performance, _studentA().performance);
    expect(plan.domains, [RagDomain.studentPerformance, RagDomain.notes]);
  });

  test('AI Teacher on a weak topic adds notes + syllabus to lesson context domains',
      () {
    final plan = planStudentRagQuery(
      question: 'Explain this lesson',
      student: _studentA(),
      fromAiTeacher: true,
      chapterId: 'fr',
      subjectId: 'pol',
    );
    expect(plan.domains, containsAll([RagDomain.aiTeacher, RagDomain.notes]));
    expect(plan.domains, contains(RagDomain.syllabus));
    expect(plan.includePerformance, isFalse);
  });

  test('high / medium / low confidence handling', () {
    const ok = RagTeacherAnswer(
      markdown: 'Article 14 guarantees equality.',
      citations: [
        RagCitation(
          sourceId: 'notes-1',
          subject: 'Polity',
          chapter: 'FR',
          topic: 'Art 14',
        ),
      ],
      insufficient: false,
    );
    final high = applyRagConfidence(answer: ok, confidence: 0.86);
    expect(high.insufficient, isFalse);
    expect(high.markdown, contains('Article 14'));
    expect(high.markdown, isNot(contains('medium confidence')));

    final medium = applyRagConfidence(answer: ok, confidence: 0.55);
    expect(medium.insufficient, isFalse);
    expect(medium.markdown, contains(kRagMediumConfidencePrefix));
    expect(medium.citations, isNotEmpty);

    final low = applyRagConfidence(answer: ok, confidence: 0.12);
    expect(low.insufficient, isTrue);
    expect(low.markdown, kRagInsufficientEvidence);
    expect(low.citations, isEmpty);
  });

  test('personalized answer records monitor without storing scores or names',
      () async {
    final retrieved = MultiRagResult(
      query: 'Fundamental Rights',
      plan: const RagRoutePlan(
        domains: kWeakTopicStudyDomains,
        confidence: 0.9,
        reason: 'weak_topic_study',
      ),
      hits: [
        MultiRagHit(
          domain: RagDomain.notes,
          hit: _hit(id: 'c1', text: 'Article 14 equality before law.'),
          confidence: 0.88,
          sourceRef: const RagCitation(
            sourceId: 'notes-1',
            subject: 'Polity',
            chapter: 'FR',
            topic: 'Art 14',
          ),
        ),
      ],
      confidence: 0.84,
    );
    final monitor = RagMonitor();
    final service = PersonalizedMultiRagService(
      context: _InjectedContext(_studentA()),
      retrieval: _FakeRetriever(retrieved),
      grounded: _LearnGrounded(),
      monitor: monitor,
    );
    final answer = await service.answer(
      uid: 'student-a',
      requesterUid: 'student-a',
      question: 'Indian Polity Fundamental Rights',
    );
    expect(answer.insufficient, isFalse);
    expect(answer.markdown, contains('Article 14'));
    final event = monitor.last!;
    expect(event.uid, 'student-a');
    expect(event.domains, kWeakTopicStudyDomains);
    expect(event.retrievalCount, 1);
    expect(event.sourceIds, ['notes-1']);
    expect(event.latencyMs, greaterThanOrEqualTo(0));
    expect(event.toMap().containsKey('scorePercent'), isFalse);
    expect(event.toMap().containsKey('email'), isFalse);
    expect(event.toMap().containsKey('name'), isFalse);
  });

  test('knowledge hits drop student_performance so scores are not stored in RAG',
      () {
    final retrieved = MultiRagResult(
      query: 'My weak topics',
      plan: const RagRoutePlan(
        domains: [RagDomain.studentPerformance, RagDomain.notes],
        confidence: 0.8,
      ),
      hits: [
        MultiRagHit(
          domain: RagDomain.studentPerformance,
          hit: _hit(
            id: 'perf',
            text: 'secret score 12%',
            sourceId: 'student_performance',
          ),
          confidence: 0.9,
          sourceRef: const RagCitation(
            sourceId: 'student_performance',
            subject: '',
            chapter: '',
            topic: 'FR',
          ),
        ),
        MultiRagHit(
          domain: RagDomain.notes,
          hit: _hit(id: 'n1', text: 'Published notes.'),
          confidence: 0.8,
          sourceRef: const RagCitation(
            sourceId: 'notes-1',
            subject: 'Polity',
            chapter: 'FR',
            topic: 'Art 14',
          ),
        ),
      ],
      confidence: 0.7,
    );
    final hits = knowledgeHits(retrieved);
    expect(hits.length, 1);
    expect(hits.single.chunk.sourceId, 'notes-1');
  });

  test('existing planner still prioritizes the weak topic', () {
    final plan = DailyPlannerService().buildPlan(
      uid: 'student-a',
      prefs: const PlannerPrefs(
        targetExam: 'Combine',
        examDate: '2026-12-01',
        dailyHours: 4,
      ),
      dateKey: '2026-08-21',
      syllabus: const SyllabusProgressSnapshot(topics: []),
      weakness: const WeaknessSnapshot(
        signals: [
          WeakTopicSignal(
            label: 'Fundamental Rights',
            scorePercent: 32,
            source: 'test',
            subjectId: 'pol',
            chapterId: 'fr',
            subjectTitle: 'Indian Polity',
            priority: 40,
          ),
        ],
        averageTestPercent: 32,
        attemptsThisWeek: 1,
      ),
      now: DateTime(2026, 8, 21),
    );
    expect(
      plan.tasks.any(
        (t) =>
            t.chapterId == 'fr' &&
            t.priority >= 40 &&
            (t.type == DailyPlanTaskType.revision ||
                t.type == DailyPlanTaskType.practiceMcq ||
                t.type == DailyPlanTaskType.pyq),
      ),
      isTrue,
    );
  });

  test('firestore.rules keep ragEvents owner-only and student progress isolated',
      () {
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules, contains('match /ragEvents/{eventId}'));
    expect(rules, contains('allow create: if isOwner(uid)'));
    expect(rules, contains('match /testAttempts/{attemptId}'));
    expect(rules, contains('function isOwner(uid)'));
  });
}

class _InjectedContext extends StudentRagContextService {
  _InjectedContext(this.snapshot);

  final StudentRagContext snapshot;

  @override
  Future<StudentRagContext> load({
    required String uid,
    required String requesterUid,
  }) async {
    if (uid != requesterUid) {
      throw const StudentRagAccessException(
        'Students may only use their own performance context.',
      );
    }
    if (uid != snapshot.uid) {
      throw const StudentRagAccessException(
        'Students may only use their own performance context.',
      );
    }
    return snapshot;
  }
}
