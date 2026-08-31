import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/job_alert.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/models/test_item.dart';
import 'package:mpsc_combine_ai/services/job_alerts_repository.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';

RagSource _rag({
  required String id,
  RagSourceStatus status = RagSourceStatus.ready,
  String subjectId = 'pol',
  String chapterId = 'fr',
  String topicId = 'a14',
  String contentType = kNotesPdfContentType,
}) {
  return RagSource(
    id: id,
    title: id,
    subject: 'Polity',
    chapter: 'Fundamental Rights',
    exam: 'MPSC Combine',
    fileUrl: '',
    uploadedBy: 'admin',
    createdAt: DateTime(2026, 8, 1),
    status: status,
    published: status == RagSourceStatus.ready,
    examId: kDefaultExamId,
    subjectId: subjectId,
    chapterId: chapterId,
    topicId: topicId,
    contentType: contentType,
    linkedId: id,
  );
}

String _ruleBlock(String rules, String matchLine) {
  final start = rules.indexOf(matchLine);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $matchLine');
  final from = start + matchLine.length;
  final next = rules.indexOf('match /', from);
  return rules.substring(start, next < 0 ? start + 180 : next);
}

void main() {
  test('admin filters match Group / Subject / Chapter / Topic / Status / Difficulty',
      () {
    expect(
      matchesAdminContentFilters(
        targetGroup: 'groupB',
        itemTargetGroup: 'groupC',
      ),
      isFalse,
    );
    expect(
      matchesAdminContentFilters(
        targetGroup: 'groupB',
        itemTargetGroup: 'groupB',
        subjectId: 'pol',
        itemSubjectId: 'pol',
        chapterId: 'fr',
        itemChapterId: 'fr',
        topicId: 'a14',
        itemTopicId: 'a14',
        status: NoteWorkflowStatus.draft,
        itemStatus: NoteWorkflowStatus.draft,
        difficulty: 'Hard',
        itemDifficulty: 'Hard',
      ),
      isTrue,
    );
    expect(
      matchesAdminContentFilters(
        date: DateTime(2026, 8, 27),
        itemDate: DateTime(2026, 8, 26),
      ),
      isFalse,
    );
  });

  test('Approve is not student-visible; Publish is', () {
    const approvedMcq = McqItem(
      id: 'q1',
      setTitle: 'Article 14',
      subject: 'Polity',
      difficulty: 'Medium',
      question: 'Article 14 guarantees?',
      options: ['Equality', 'Speech', 'Life', 'Religion'],
      correctIndex: 0,
      explanation: 'Equality before law',
      order: 0,
      status: NoteWorkflowStatus.approved,
      published: false,
    );
    expect(approvedMcq.isStudentVisible, isFalse);
    expect(approvedMcq.copyWith(status: NoteWorkflowStatus.published).isStudentVisible,
        isTrue);

    const approvedNote = NoteItem(
      id: 'n1',
      subjectId: 'pol',
      chapterId: 'fr',
      topicId: 'a14',
      title: 'Article 14',
      importantPoints: ['Equality'],
      revisionSummary: ['Equals'],
      status: NoteWorkflowStatus.approved,
      published: false,
    );
    expect(approvedNote.isStudentVisible, isFalse);

    const publishedPyq = PyqItem(
      id: 'p1',
      title: 'Article 14 PYQ',
      subtitle: '',
      fileUrl: '',
      order: 0,
      status: NoteWorkflowStatus.published,
      published: true,
    );
    expect(publishedPyq.isStudentVisible, isTrue);
    expect(
      publishedPyq.copyWith(status: NoteWorkflowStatus.unpublished).isStudentVisible,
      isFalse,
    );

    const test = TestItem(
      id: 't1',
      title: 'Article 14 Test',
      subtitle: '',
      durationSeconds: 600,
      correctMarks: 2,
      negativeMarks: 0.5,
      questions: [],
      order: 0,
      status: NoteWorkflowStatus.draft,
      published: false,
    );
    expect(test.isStudentVisible, isFalse);
  });

  test('AI-generated MCQs stay Draft until an admin publishes', () {
    const generated = McqItem(
      id: 'ai1',
      setTitle: 'AI draft set',
      subject: 'Polity',
      difficulty: 'Medium',
      question: 'Generated?',
      options: ['A', 'B', 'C', 'D'],
      correctIndex: 0,
      explanation: 'draft',
      order: 0,
      status: NoteWorkflowStatus.draft,
      published: false,
    );
    expect(generated.status, NoteWorkflowStatus.draft);
    expect(generated.isStudentVisible, isFalse);
  });

  test('student MCQ stream hides approved and draft rows', () async {
    final db = FakeFirebaseFirestore();
    final repo = McqRepository(firestore: db);
    await repo.add(
      const McqItem(
        id: '',
        setTitle: 'Article 14 — Practice Set',
        subject: 'Polity',
        difficulty: 'Easy',
        question: 'Draft question',
        options: ['A', 'B', 'C', 'D'],
        correctIndex: 0,
        explanation: '',
        order: 0,
        status: NoteWorkflowStatus.draft,
        published: false,
      ),
    );
    await repo.add(
      const McqItem(
        id: '',
        setTitle: 'Article 14 — Practice Set',
        subject: 'Polity',
        difficulty: 'Easy',
        question: 'Live question',
        options: ['A', 'B', 'C', 'D'],
        correctIndex: 0,
        explanation: '',
        order: 1,
        status: NoteWorkflowStatus.published,
        published: true,
      ),
    );
    final student = await repo.watchPublished().first;
    expect(student.map((q) => q.question), ['Live question']);
    final admin = await repo.watchAll().first;
    expect(admin.length, 2);
  });

  test('RAG admin monitoring counts Indexed / Processing / Failed', () {
    final sources = [
      _rag(id: 'ready-1'),
      _rag(id: 'ready-2'),
      _rag(id: 'proc', status: RagSourceStatus.processing),
      _rag(id: 'up', status: RagSourceStatus.uploading),
      _rag(id: 'fail', status: RagSourceStatus.failed),
    ];
    final stats = ragAdminMonitorStats(sources);
    expect(stats.total, 5);
    expect(stats.indexed, 2);
    expect(stats.processing, 2);
    expect(stats.failed, 1);

    expect(
      matchesRagAdminFilters(
        sources.first,
        subjectId: 'pol',
        chapterId: 'fr',
        topicId: 'a14',
        contentType: kNotesPdfContentType,
        status: RagAdminStatusFilter.indexed,
      ),
      isTrue,
    );
    expect(
      matchesRagAdminFilters(
        sources.first,
        contentType: kFlashcardContentType,
      ),
      isFalse,
    );
    expect(
      matchesRagAdminFilters(
        sources[2],
        status: RagAdminStatusFilter.processing,
      ),
      isTrue,
    );
  });

  test('new job alerts stay unpublished until admin publishes', () async {
    final db = FakeFirebaseFirestore();
    final repo = JobAlertsRepository(firestore: db);
    await repo.add(
      const JobAlert(
        id: '',
        examName: 'Draft PSI',
        organization: 'MPSC',
        post: 'PSI',
        eligibility: 'Graduate',
        description: 'Not live yet',
        applicationUrl: '',
        published: false,
      ),
    );
    expect(await repo.getPublished(), isEmpty);
    final admin = await repo.watchAll().first;
    expect(admin.single.published, isFalse);
    await repo.update(admin.single.copyWith(published: true));
    expect((await repo.getPublished()).single.examName, 'Draft PSI');
  });

  test('firestore.rules keep student progress owner-write; admin cannot write attempts',
      () {
    final rules = File('firestore.rules').readAsStringSync();
    for (final path in [
      'match /testAttempts/{attemptId}',
      'match /studyPlans/{planId}',
      'match /syllabusProgress/{topicId}',
      'match /classroomProgress/{chapterId}',
    ]) {
      final block = _ruleBlock(rules, path);
      expect(
        block,
        contains('allow read: if isOwner(uid) || isAdmin();'),
        reason: path,
      );
      expect(
        block,
        contains('allow write: if isOwner(uid);'),
        reason: path,
      );
      expect(
        block,
        isNot(contains('allow write: if isOwner(uid) || isAdmin()')),
        reason: '$path must not let admins write student progress',
      );
    }
    expect(rules, contains('function isOwner(uid)'));
    expect(rules, contains('function isAdmin()'));
  });
}
