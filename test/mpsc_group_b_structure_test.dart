import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/data/mpsc_group_b_chapters.dart';
import 'package:mpsc_combine_ai/data/mpsc_group_b_structure.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';

void main() {
  test('Group B catalog is exam → stage → paper → subject only', () {
    final exam = ExamItem.groupBCombined();
    expect(exam.id, kGroupBCombinedExamId);
    expect(exam.title, 'MPSC Group B Combined Examination');
    expect(exam.stages.map((s) => s.id), [kExamStagePrelims, kExamStageMains]);
    expect(exam.papers.map((p) => p.id), [
      kGroupBPaperGat,
      kGroupBPaper1,
      kGroupBPaper2,
    ]);
    expect(exam.posts.map((p) => p.id), ['aso', 'sti', 'deputy_registrar', 'psi']);
    expect(
      exam.posts.firstWhere((p) => p.id == 'psi').extraStages,
      ['written_examination', 'physical_test', 'interview'],
    );

    final gat = exam.papers.firstWhere((p) => p.id == kGroupBPaperGat);
    expect(gat.questionCount, 100);
    expect(gat.marks, 100);
    expect(gat.durationMinutes, 60);
    expect(gat.medium, 'Marathi and English');
    expect(gat.questionType, 'objective_mcq');

    final subjects = mpscGroupBCombinedSubjects();
    expect(subjects, hasLength(4));
    expect(subjects.map((s) => s.id).toSet(), {
      kGroupBSubjectPrelimsGatId,
      kGroupBSubjectMainsMarathiId,
      kGroupBSubjectMainsEnglishId,
      kGroupBSubjectMainsGsId,
    });
    expect(subjects.every((s) => s.examId == kGroupBCombinedExamId), isTrue);
    expect(subjects.every((s) => s.active), isTrue);
    expect(
      subjects.where((s) => s.stageId == kExamStagePrelims).single.nameEn,
      'General Ability Test',
    );
    expect(
      subjects
          .where((s) => s.stageId == kExamStageMains && s.paperId == kGroupBPaper1)
          .map((s) => s.nameEn),
      ['Marathi', 'English'],
    );
    expect(
      subjects.where((s) => s.paperId == kGroupBPaper2).single.nameEn,
      'General Studies / General Ability & Intelligence',
    );
  });

  test('ensureMpscGroupBCombinedStructure writes grouping chapters, no topics',
      () async {
    final firestore = FakeFirebaseFirestore();
    final repo = NotesRepository(firestore: firestore);

    final first = await repo.ensureMpscGroupBCombinedStructure();
    final second = await repo.ensureMpscGroupBCombinedStructure();
    expect(first.id, second.id);
    expect(first.id, kGroupBCombinedExamId);

    final exams = await repo.getExamsOnce();
    expect(exams.any((e) => e.id == kGroupBCombinedExamId), isTrue);

    final subjects = await repo.getSubjectsOnce();
    final groupB =
        subjects.where((s) => s.examId == kGroupBCombinedExamId).toList();
    expect(groupB, hasLength(4));
    expect(groupB.map((s) => s.id).toSet(), {
      kGroupBSubjectPrelimsGatId,
      kGroupBSubjectMainsMarathiId,
      kGroupBSubjectMainsEnglishId,
      kGroupBSubjectMainsGsId,
    });

    final catalog = mpscGroupBCombinedChapters();
    expect(catalog.length, catalog.map((c) => c.id).toSet().length);
    expect(catalog.length, catalog.map((c) => c.slug).toSet().length);
    for (final area in [
      'current_affairs',
      'history',
      'geography',
      'economy',
      'polity',
      'general_science',
      'intelligence_arithmetic',
      'marathi',
      'english',
      'general_studies',
    ]) {
      expect(
        catalog.where((c) => c.tags.contains(area)).length,
        greaterThanOrEqualTo(15),
        reason: area,
      );
    }

    for (final s in groupB) {
      final chapters = await repo.getChaptersOnce(s.id);
      expect(chapters.length, greaterThanOrEqualTo(15), reason: s.nameEn);
      expect(chapters.every((c) => c.subjectId == s.id), isTrue);
      expect(chapters.every((c) => c.parentChapterId.isEmpty), isTrue);
      expect(
        chapters.every((c) => c.nodeType == 'chapter'),
        isTrue,
      );
      expect(chapters.every((c) => c.slug.isNotEmpty && c.id.isNotEmpty), isTrue);
    }

    final topics = await firestore.collection('topics').get();
    expect(topics.docs, isEmpty);
    final childTopics = await firestore
        .collection('chapters')
        .where('nodeType', isEqualTo: 'topic')
        .get();
    expect(childTopics.docs, isEmpty);
  });
}
