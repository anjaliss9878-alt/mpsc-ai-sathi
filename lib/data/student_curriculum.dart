import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';

/// Student notes list for one subject.
///
/// Group B Combined curriculum rows are `nodeType=chapter`. They must stay
/// visible even with zero published notes, and must not be replaced by leftover
/// legacy topic leaves on the same subject.
///
/// Legacy `mpsc_combine` subjects still prefer topic leaves when those exist.
List<ChapterItem> selectStudentCurriculumChapters(List<ChapterItem> all) {
  final published = all.where((c) => c.published).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  if (published.isEmpty) return published;

  final groupB = published.any(
    (c) =>
        c.examId == kGroupBCombinedExamId ||
        isGroupBCombinedSubjectId(c.subjectId),
  );
  if (groupB) {
    return published
        .where((c) => c.isGroupingChapter && c.parentChapterId.isEmpty)
        .toList();
  }

  final leaves = published.where((c) => !c.isGroupingChapter).toList();
  if (leaves.isNotEmpty) return leaves;
  return published
      .where((c) => c.isGroupingChapter && c.parentChapterId.isEmpty)
      .toList();
}

String chapterSyllabusAreaId(ChapterItem chapter) {
  for (final raw in chapter.tags) {
    final tag = raw.trim().toLowerCase();
    if (tag.isEmpty || tag == 'chapter' || tag == 'topic' || tag == 'subtopic') {
      continue;
    }
    return tag;
  }
  return '';
}

/// Student UI only — not Firestore subject IDs. Official Prelims paper stays GAT.
const List<String> kGroupBPrelimsAreaIds = [
  'current_affairs',
  'history',
  'geography',
  'economy',
  'polity',
  'general_science',
  'intelligence_arithmetic',
];

String syllabusAreaTitle(String areaId) {
  switch (areaId) {
    case 'current_affairs':
      return 'Current Affairs';
    case 'history':
      return 'History';
    case 'geography':
      return 'Geography';
    case 'economy':
      return 'Economy';
    case 'polity':
      return 'Polity';
    case 'general_science':
      return 'General Science';
    case 'intelligence_arithmetic':
      return 'Intelligence Test & Arithmetic';
    case 'environment':
      return 'Environment';
    case 'marathi':
      return 'Marathi';
    case 'english':
      return 'English';
    case 'general_studies':
      return 'General Studies / General Ability & Intelligence';
    default:
      return areaId;
  }
}

/// Planner/diagnostic display area. Official Prelims paper stays GAT in
/// Firestore; students see History/Economy/… from existing chapter tags.
String plannerAreaIdForChapter(ChapterItem chapter) {
  final title = '${chapter.title} ${chapter.titleEn}'.toLowerCase();
  if (title.contains('environment') ||
      title.contains('ecology') ||
      title.contains('climate')) {
    return 'environment';
  }
  final tag = chapterSyllabusAreaId(chapter);
  if (tag.isNotEmpty) return tag;
  return chapter.subjectId;
}

/// Subject label for the Personalized Study Plan and diagnostic notes.
String plannerSubjectTitleForChapter(ChapterItem chapter) {
  return syllabusAreaTitle(plannerAreaIdForChapter(chapter));
}

bool groupBStageShowsPrelimsAreas(String examId, String stageId) =>
    examId == kGroupBCombinedExamId && stageId == kExamStagePrelims;

bool shouldShowGroupBPrelimsAreaPicker({
  required SubjectItem subject,
  String syllabusAreaId = '',
  String parentChapterId = '',
}) {
  return subject.id == kGroupBSubjectPrelimsGatId &&
      syllabusAreaId.isEmpty &&
      parentChapterId.isEmpty;
}

List<ChapterItem> chaptersForSyllabusArea(
  List<ChapterItem> chapters,
  String areaId,
) {
  final key = areaId.trim();
  if (key.isEmpty) return chapters;
  return [
    for (final chapter in chapters)
      if (chapterSyllabusAreaId(chapter) == key) chapter,
  ];
}

/// Ordered groups. A single empty key means "no area tags — keep a flat list".
List<MapEntry<String, List<ChapterItem>>> groupChaptersBySyllabusArea(
  List<ChapterItem> chapters,
) {
  final order = <String>[];
  final map = <String, List<ChapterItem>>{};
  for (final chapter in chapters) {
    final key = chapterSyllabusAreaId(chapter);
    if (!map.containsKey(key)) {
      order.add(key);
      map[key] = <ChapterItem>[];
    }
    map[key]!.add(chapter);
  }
  return [for (final key in order) MapEntry(key, map[key]!)];
}

bool subjectBelongsToExam(SubjectItem subject, String examId) {
  if (examId.isEmpty) return true;
  if (examId == kGroupBCombinedExamId) {
    return isGroupBCombinedSubjectId(subject.id);
  }
  if (isGroupBCombinedSubjectId(subject.id)) return false;
  if (subject.examId == examId) return true;
  return examId == kDefaultExamId &&
      (subject.examId.isEmpty || subject.examId == kDefaultExamId);
}

List<SubjectItem> subjectsForExam(List<SubjectItem> subjects, String examId) {
  final matched = subjects.where((s) => subjectBelongsToExam(s, examId)).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  if (examId != kGroupBCombinedExamId) return matched;
  final byId = {for (final s in matched) s.id: s};
  return [
    for (final id in kGroupBCombinedSubjectIds)
      if (byId[id] != null) byId[id]!,
  ];
}

List<SubjectItem> subjectsForPaper({
  required List<SubjectItem> subjects,
  required String examId,
  required String stageId,
  required String paperId,
}) {
  return subjectsForExam(subjects, examId).where((s) {
    if (stageId.isNotEmpty && s.stageId != stageId) return false;
    if (paperId.isNotEmpty && s.paperId != paperId) return false;
    return true;
  }).toList();
}
