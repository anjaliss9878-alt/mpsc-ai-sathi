import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/services/content_index_resolver.dart';
import 'package:mpsc_combine_ai/utils/bulk_cells.dart';

/// One parsed flashcard row from CSV/Excel. Always imported as Draft.
class BulkFlashcardRow {
  BulkFlashcardRow({
    required this.rowNumber,
    required this.exam,
    required this.targetGroup,
    required this.subject,
    required this.chapter,
    required this.topic,
    required this.title,
    required this.front,
    required this.back,
    required this.explanation,
    required this.difficulty,
    required this.tags,
    this.examId = kDefaultExamId,
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
    this.errors = const [],
    this.isDuplicate = false,
  });

  final int rowNumber;
  final String exam;
  final String targetGroup;
  final String subject;
  final String chapter;
  final String topic;
  final String title;
  final String front;
  final String back;
  final String explanation;
  final String difficulty;
  final List<String> tags;
  final String examId;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final List<String> errors;
  bool isDuplicate;

  bool get isValid => errors.isEmpty;
  bool get willUpload => isValid && !isDuplicate;

  factory BulkFlashcardRow.parse(
    int rowNumber,
    Map<String, String> cells, {
    ContentIndexResolver? index,
  }) {
    final n = normalizeBulkCells(cells);
    String cell(String key) => bulkCell(n, key);

    final exam = cell('exam');
    final targetRaw = cell('targetgroup');
    final subject = cell('subject');
    final chapter = cell('chapter');
    final topic = cell('topic');
    final title = cell('title');
    final front = cell('front').isNotEmpty ? cell('front') : cell('question');
    final back = cell('back').isNotEmpty ? cell('back') : cell('answer');
    final explanation = cell('explanation');
    var difficulty = cell('difficulty');
    if (!['Easy', 'Medium', 'Hard'].contains(difficulty)) {
      difficulty = 'Medium';
    }
    final tagsRaw = cell('tags');
    final tags = tagsRaw.isEmpty
        ? <String>[]
        : tagsRaw
            .split(RegExp('[|,]'))
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList();

    final errors = <String>[];
    if (front.isEmpty) errors.add('Front/question is empty');
    if (back.isEmpty) errors.add('Back/answer is empty');
    if (subject.isEmpty) errors.add('Missing subject');
    if (chapter.isEmpty) errors.add('Missing chapter');
    if (topic.isEmpty) errors.add('Missing topic');
    if (!isValidTargetGroupLabel(targetRaw)) {
      errors.add('Invalid target group');
    }
    if (exam.isNotEmpty && !ContentIndexResolver.isAllowedExamLabel(exam)) {
      errors.add('Invalid exam (MPSC Combine only)');
    }

    var examId = kDefaultExamId;
    var subjectId = '';
    var chapterId = '';
    var topicId = '';
    if (index != null) {
      final resolved = index.resolve(
        exam: exam,
        subject: subject,
        chapter: chapter,
        topic: topic,
      );
      examId = resolved.examId;
      subjectId = resolved.subjectId;
      chapterId = resolved.chapterId;
      topicId = resolved.topicId;
      for (final e in resolved.errors) {
        if (!errors.contains(e)) errors.add(e);
      }
    }

    return BulkFlashcardRow(
      rowNumber: rowNumber,
      exam: exam,
      targetGroup: isValidTargetGroupLabel(targetRaw)
          ? targetGroupToString(targetGroupFromString(targetRaw))
          : targetRaw,
      subject: subject,
      chapter: chapter,
      topic: topic,
      title: title.isNotEmpty ? title : front,
      front: front,
      back: back,
      explanation: explanation,
      difficulty: difficulty,
      tags: tags,
      examId: examId,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      errors: errors,
    );
  }
}

const List<String> bulkFlashcardExpectedHeaders = [
  'Exam',
  'Target Group',
  'Subject',
  'Chapter',
  'Topic',
  'Title',
  'Front',
  'Back',
  'Explanation',
  'Difficulty',
  'Tags',
];
