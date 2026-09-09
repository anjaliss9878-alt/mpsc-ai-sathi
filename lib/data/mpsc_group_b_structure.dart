import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';

/// Group B Combined subjects — Phase 1 exam/stage/paper/subject IDs.
/// Phase 2 adds grouping chapters under these IDs (see mpsc_group_b_chapters.dart).
List<SubjectItem> mpscGroupBCombinedSubjects() {
  const examId = kGroupBCombinedExamId;
  return const [
    SubjectItem(
      id: kGroupBSubjectPrelimsGatId,
      title: 'General Ability Test',
      subtitle: 'सामान्य क्षमता चाचणी',
      iconName: 'psychology',
      order: 0,
      slug: 'gb_prelims_general_ability_test',
      nameEn: 'General Ability Test',
      examId: examId,
      stageId: kExamStagePrelims,
      paperId: kGroupBPaperGat,
      published: true,
    ),
    SubjectItem(
      id: kGroupBSubjectMainsMarathiId,
      title: 'मराठी',
      subtitle: 'Paper 1 — Common',
      iconName: 'translate',
      order: 1,
      slug: 'gb_mains_paper1_marathi',
      nameEn: 'Marathi',
      examId: examId,
      stageId: kExamStageMains,
      paperId: kGroupBPaper1,
      published: true,
    ),
    SubjectItem(
      id: kGroupBSubjectMainsEnglishId,
      title: 'इंग्रजी',
      subtitle: 'Paper 1 — Common',
      iconName: 'menu_book',
      order: 2,
      slug: 'gb_mains_paper1_english',
      nameEn: 'English',
      examId: examId,
      stageId: kExamStageMains,
      paperId: kGroupBPaper1,
      published: true,
    ),
    SubjectItem(
      id: kGroupBSubjectMainsGsId,
      title: 'General Studies / General Ability & Intelligence',
      subtitle: 'Paper 2',
      iconName: 'account_balance',
      order: 3,
      slug: 'gb_mains_paper2_general_studies',
      nameEn: 'General Studies / General Ability & Intelligence',
      examId: examId,
      stageId: kExamStageMains,
      paperId: kGroupBPaper2,
      published: true,
    ),
  ];
}
