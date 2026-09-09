import 'package:mpsc_combine_ai/data/mpsc_group_b_chapters.dart';
import 'package:mpsc_combine_ai/data/mpsc_group_b_structure.dart';
import 'package:mpsc_combine_ai/data/student_curriculum.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';

/// Onboarding target-exam labels (MVP). Group B Combined maps to the existing
/// `mpsc_group_b_combined` curriculum.
const List<String> kOnboardingTargetExamOptions = [
  'MPSC Group B Combined',
  'MPSC Rajyaseva',
  'MPSC Group C',
  'UPSC',
  'Other',
];

const String kTargetExamGroupBCombined = 'MPSC Group B Combined';

/// Target exam labels for Signup / Profile / Planner.
/// New onboarding options come first; legacy labels stay so existing
/// profiles still match the dropdown.
const List<String> targetExamOptions = [
  ...kOnboardingTargetExamOptions,
  'राज्यसेवा (Rajyaseva)',
  'संयुक्त पूर्व परीक्षा गट ब (Combine Group B)',
  'संयुक्त पूर्व परीक्षा गट क (Combine Group C)',
  'PSI / STI / ASO',
  'इतर (Other)',
];

const List<String> kDailyStudyHourOptions = [
  '1–2 hours',
  '2–4 hours',
  '4–6 hours',
  '6–8 hours',
  '8+ hours',
];

const String kStudyModePartTime = 'part_time';
const String kStudyModeFullTime = 'full_time';

const List<String> kPreparationStageOptions = [
  'Beginner',
  'Basic Preparation',
  'Intermediate',
  'Advanced',
  'Revision',
  'Exam-Oriented Preparation',
];

const List<String> kPreferredLanguageOptions = [
  'Marathi',
  'English',
  'Marathi + English',
];

const List<int> kPreparationDurationDayOptions = [30, 60, 90, 120, 180];

int resolvedPreparationDays({
  required String examDate,
  int preparationDurationDays = 0,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final parsed = DateTime.tryParse(examDate.trim());
  if (parsed != null) {
    final today = DateTime(clock.year, clock.month, clock.day);
    final exam = DateTime(parsed.year, parsed.month, parsed.day);
    final left = exam.difference(today).inDays;
    if (left > 0) return left;
  }
  if (preparationDurationDays > 0) return preparationDurationDays;
  return 90;
}

bool isGroupBCombinedTargetExam(String exam) {
  final t = exam.toLowerCase();
  return t.contains('group b') ||
      t.contains('गट ब') ||
      t.contains(kGroupBCombinedExamId);
}

/// Maps a student profile `targetExam` label to the Firestore exam document id
/// used by notes, RAG sources, and retrieval filters.
String examIdFromStudentTargetExam(String targetExam) {
  if (targetExam.trim().isEmpty) return kGroupBCombinedExamId;
  if (isGroupBCombinedTargetExam(targetExam)) return kGroupBCombinedExamId;
  return kDefaultExamId;
}

double dailyHoursFromBucket(String bucket) {
  switch (bucket.trim()) {
    case '1–2 hours':
    case '1-2 hours':
      return 1.5;
    case '2–4 hours':
    case '2-4 hours':
      return 3;
    case '4–6 hours':
    case '4-6 hours':
      return 5;
    case '6–8 hours':
    case '6-8 hours':
      return 7;
    case '8+ hours':
      return 8;
    default:
      return 4;
  }
}

String dailyHoursBucketFromHours(double hours) {
  if (hours <= 2) return kDailyStudyHourOptions[0];
  if (hours <= 4) return kDailyStudyHourOptions[1];
  if (hours <= 6) return kDailyStudyHourOptions[2];
  if (hours <= 8) return kDailyStudyHourOptions[3];
  return kDailyStudyHourOptions[4];
}

ChapterItem? groupBChapterForArea(String areaId) {
  for (final chapter in mpscGroupBCombinedChapters()) {
    if (chapterSyllabusAreaId(chapter) == areaId) return chapter;
  }
  return null;
}

/// In-memory Group B syllabus for the first personalized plan when Firestore
/// chapters are not loaded yet. Does not write syllabus progress.
SyllabusProgressSnapshot groupBFallbackSyllabus() {
  final subjects = <String, SubjectItem>{
    for (final s in mpscGroupBCombinedSubjects()) s.id: s,
  };
  return SyllabusProgressSnapshot(
    topics: [
      for (final chapter in mpscGroupBCombinedChapters())
        SyllabusTopicProgress(
          subject: subjects[chapter.subjectId] ??
              SubjectItem(
                id: chapter.subjectId,
                title: chapter.subjectId,
                subtitle: '',
                iconName: 'menu_book',
                order: 0,
              ),
          chapter: chapter,
          status: SyllabusTopicStatus.pending,
        ),
    ],
  );
}
