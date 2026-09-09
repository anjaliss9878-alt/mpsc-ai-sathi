import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/data/mpsc_group_b_chapters.dart';
import 'package:mpsc_combine_ai/data/mpsc_group_b_structure.dart';
import 'package:mpsc_combine_ai/data/student_curriculum.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late NotesRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = NotesRepository(firestore: firestore);
  });

  test('Group B subjects load once with exam/stage/paper ids', () async {
    await repo.ensureMpscGroupBCombinedStructure();
    final subjects = (await repo.watchPublishedSubjects().first)
        .where((s) => s.examId == kGroupBCombinedExamId)
        .toList();
    expect(subjects, hasLength(4));
    expect(subjects.map((s) => s.id).toSet(), {
      kGroupBSubjectPrelimsGatId,
      kGroupBSubjectMainsMarathiId,
      kGroupBSubjectMainsEnglishId,
      kGroupBSubjectMainsGsId,
    });

    final gat = subjects.singleWhere((s) => s.id == kGroupBSubjectPrelimsGatId);
    expect(gat.stageId, kExamStagePrelims);
    expect(gat.paperId, kGroupBPaperGat);

    final paper1 = subjectsForPaper(
      subjects: subjects,
      examId: kGroupBCombinedExamId,
      stageId: kExamStageMains,
      paperId: kGroupBPaper1,
    );
    expect(paper1.map((s) => s.id), [
      kGroupBSubjectMainsMarathiId,
      kGroupBSubjectMainsEnglishId,
    ]);

    final paper2 = subjectsForPaper(
      subjects: subjects,
      examId: kGroupBCombinedExamId,
      stageId: kExamStageMains,
      paperId: kGroupBPaper2,
    );
    expect(paper2.map((s) => s.id), [kGroupBSubjectMainsGsId]);
  });

  test('student chapter list uses subjectId and grouping chapters', () async {
    await repo.ensureMpscGroupBCombinedStructure();
    for (final subjectId in [
      kGroupBSubjectPrelimsGatId,
      kGroupBSubjectMainsMarathiId,
      kGroupBSubjectMainsEnglishId,
      kGroupBSubjectMainsGsId,
    ]) {
      final chapters = await repo.watchPublishedChapters(subjectId).first;
      expect(chapters.length, greaterThanOrEqualTo(15), reason: subjectId);
      expect(chapters.every((c) => c.subjectId == subjectId), isTrue);
      expect(chapters.every((c) => c.nodeType == 'chapter'), isTrue);
      expect(chapters.every((c) => c.parentChapterId.isEmpty), isTrue);
    }

    final gat = await repo.watchPublishedChapters(kGroupBSubjectPrelimsGatId).first;
    final groups = groupChaptersBySyllabusArea(gat);
    expect(groups.map((g) => g.key), [
      'current_affairs',
      'history',
      'geography',
      'economy',
      'polity',
      'general_science',
      'intelligence_arithmetic',
    ]);
    expect(groups.first.value, hasLength(15));
    expect(gat.length, mpscGroupBCombinedChapters()
        .where((c) => c.subjectId == kGroupBSubjectPrelimsGatId)
        .length);
  });

  test('ensureDefaultExam does not duplicate Group B subjects', () async {
    await repo.ensureDefaultExam();
    await repo.ensureDefaultExam();
    final all = await repo.getSubjectsOnce();
    final groupB = all.where((s) => s.examId == kGroupBCombinedExamId).toList();
    expect(groupB, hasLength(4));
    expect(groupB.map((s) => s.id).toSet(), hasLength(4));
  });

  test('legacy topic leaves still hide grouping chapters', () async {
    final subjectId = await repo.addSubject(
      const SubjectItem(
        id: '',
        title: 'Polity',
        subtitle: '',
        iconName: 'account_balance',
        order: 0,
        examId: kDefaultExamId,
        published: true,
      ),
    );
    await repo.addChapter(
      ChapterItem(
        id: '',
        subjectId: subjectId,
        title: 'Constitution',
        order: 0,
        examId: kDefaultExamId,
        nodeType: contentNodeTypeToString(ContentNodeType.chapter),
        published: true,
      ),
    );
    await repo.addChapter(
      ChapterItem(
        id: '',
        subjectId: subjectId,
        title: 'Preamble',
        order: 1,
        examId: kDefaultExamId,
        parentChapterId: 'x',
        nodeType: contentNodeTypeToString(ContentNodeType.topic),
        published: true,
      ),
    );
    final student = await repo.watchPublishedChapters(subjectId).first;
    expect(student.map((c) => c.title), ['Preamble']);
  });

  test('Group B chapters stay visible without notes and ignore leftover leaves',
      () async {
    await repo.ensureMpscGroupBCombinedStructure();
    await repo.addChapter(
      ChapterItem(
        id: '',
        subjectId: kGroupBSubjectPrelimsGatId,
        title: 'Legacy leftover topic',
        order: 999,
        examId: kGroupBCombinedExamId,
        nodeType: contentNodeTypeToString(ContentNodeType.topic),
        published: true,
      ),
    );

    final gat = await repo.watchPublishedChapters(kGroupBSubjectPrelimsGatId).first;
    expect(gat.every((c) => c.nodeType == 'chapter'), isTrue);
    expect(gat.every((c) => c.parentChapterId.isEmpty), isTrue);
    expect(gat.map((c) => c.title), isNot(contains('Legacy leftover topic')));
    expect(
      gat.length,
      mpscGroupBCombinedChapters()
          .where((c) => c.subjectId == kGroupBSubjectPrelimsGatId)
          .length,
    );

    final groups = groupChaptersBySyllabusArea(gat);
    expect(groups.map((g) => g.key).toList(), [
      'current_affairs',
      'history',
      'geography',
      'economy',
      'polity',
      'general_science',
      'intelligence_arithmetic',
    ]);
    expect(groups[0].value, hasLength(15));
    expect(groups[1].value, hasLength(16));
    expect(groups[2].value, hasLength(18));
    expect(groups[3].value, hasLength(19));
    expect(groups[4].value, hasLength(19));
    expect(groups[5].value, hasLength(18));
    expect(groups[6].value, hasLength(20));

    final marathi =
        await repo.watchPublishedChapters(kGroupBSubjectMainsMarathiId).first;
    final english =
        await repo.watchPublishedChapters(kGroupBSubjectMainsEnglishId).first;
    final gs = await repo.watchPublishedChapters(kGroupBSubjectMainsGsId).first;
    expect(marathi, hasLength(16));
    expect(english, hasLength(16));
    expect(gs, hasLength(18));
  });

  test('Group B student view excludes old Combine subjects', () async {
    await repo.ensureMpscGroupBCombinedStructure();
    await repo.addSubject(
      const SubjectItem(
        id: '',
        title: 'राज्यशास्त्र',
        subtitle: 'Old Group B subject',
        iconName: 'account_balance',
        order: 0,
        slug: 'rajyashastra',
        examId: kGroupBCombinedExamId,
        published: true,
      ),
    );
    await repo.addSubject(
      const SubjectItem(
        id: '',
        title: 'भूगोल',
        subtitle: 'Legacy Combine',
        iconName: 'public',
        order: 1,
        slug: 'bhugol',
        examId: kDefaultExamId,
        published: true,
      ),
    );

    final groupB = await repo
        .watchPublishedSubjects(examId: kGroupBCombinedExamId)
        .first;
    expect(groupB.map((s) => s.id).toList(), kGroupBCombinedSubjectIds);
    expect(groupB.map((s) => s.title), isNot(contains('राज्यशास्त्र')));
    expect(groupB.map((s) => s.title), isNot(contains('भूगोल')));

    final combine = subjectsForExam(
      await repo.getSubjectsOnce(),
      kDefaultExamId,
    );
    expect(combine.map((s) => s.slug), contains('bhugol'));
    expect(combine.map((s) => s.id), isNot(contains(kGroupBSubjectPrelimsGatId)));
  });

  test('Prelims student UI uses seven GAT area groups, not extra subjects', () {
    expect(mpscGroupBCombinedSubjects().where((s) => s.stageId == kExamStagePrelims),
        hasLength(1));
    expect(kGroupBPrelimsAreaIds, [
      'current_affairs',
      'history',
      'geography',
      'economy',
      'polity',
      'general_science',
      'intelligence_arithmetic',
    ]);
    expect(kGroupBCombinedSubjectIds, hasLength(4));
    expect(groupBStageShowsPrelimsAreas(kGroupBCombinedExamId, kExamStagePrelims),
        isTrue);
    expect(groupBStageShowsPrelimsAreas(kGroupBCombinedExamId, kExamStageMains),
        isFalse);

    final gat = mpscGroupBCombinedChapters()
        .where((c) => c.subjectId == kGroupBSubjectPrelimsGatId)
        .toList();
    expect(gat, hasLength(125));
    final polity = chaptersForSyllabusArea(gat, 'polity');
    expect(polity.map((c) => c.titleEn), containsAll(['Constitution of India', 'Fundamental Rights']));
    expect(
      shouldShowGroupBPrelimsAreaPicker(
        subject: mpscGroupBCombinedSubjects().first,
      ),
      isTrue,
    );
    expect(
      shouldShowGroupBPrelimsAreaPicker(
        subject: mpscGroupBCombinedSubjects().first,
        syllabusAreaId: 'polity',
      ),
      isFalse,
    );
  });

  test('Mains student navigation is Paper 1 Marathi/English and Paper 2 GS', () {
    final subjects = mpscGroupBCombinedSubjects();
    expect(
      subjectsForPaper(
        subjects: subjects,
        examId: kGroupBCombinedExamId,
        stageId: kExamStageMains,
        paperId: kGroupBPaper1,
      ).map((s) => s.nameEn),
      ['Marathi', 'English'],
    );
    expect(
      subjectsForPaper(
        subjects: subjects,
        examId: kGroupBCombinedExamId,
        stageId: kExamStageMains,
        paperId: kGroupBPaper2,
      ).single.nameEn,
      'General Studies / General Ability & Intelligence',
    );
    expect(
      mpscGroupBCombinedChapters()
          .where((c) => c.subjectId == kGroupBSubjectMainsMarathiId),
      hasLength(16),
    );
    expect(
      mpscGroupBCombinedChapters()
          .where((c) => c.subjectId == kGroupBSubjectMainsEnglishId),
      hasLength(16),
    );
    expect(
      mpscGroupBCombinedChapters()
          .where((c) => c.subjectId == kGroupBSubjectMainsGsId),
      hasLength(18),
    );
  });
}
