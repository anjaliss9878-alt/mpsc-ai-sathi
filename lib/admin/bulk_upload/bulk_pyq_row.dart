import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/services/content_index_resolver.dart';
import 'package:mpsc_combine_ai/utils/bulk_cells.dart';
import 'package:mpsc_combine_ai/utils/correct_answer.dart';

/// One parsed PYQ row from CSV/Excel. Always imported as Draft.
class BulkPyqRow {
  BulkPyqRow({
    required this.rowNumber,
    required this.exam,
    required this.targetGroup,
    required this.year,
    required this.subject,
    required this.chapter,
    required this.topic,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.answer,
    required this.explanation,
    required this.difficulty,
    required this.source,
    required this.tags,
    this.examId = kDefaultExamId,
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
    this.subjectTitle = '',
    this.errors = const [],
    this.isDuplicate = false,
  });

  final int rowNumber;
  final String exam;
  final String targetGroup;
  final int? year;
  final String subject;
  final String chapter;
  final String topic;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String answer;
  final String explanation;
  final String difficulty;
  final String source;
  final List<String> tags;
  final String examId;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final String subjectTitle;
  final List<String> errors;
  bool isDuplicate;

  bool get isValid => errors.isEmpty;
  bool get willUpload => isValid && !isDuplicate;

  factory BulkPyqRow.parse(
    int rowNumber,
    Map<String, String> cells, {
    ContentIndexResolver? index,
  }) {
    final n = normalizeBulkCells(cells);
    String cell(String key) => bulkCell(n, key);

    final exam = cell('exam');
    final targetRaw = cell('targetgroup');
    final yearRaw = cell('year');
    final subject = cell('subject');
    final chapter = cell('chapter');
    final topic = cell('topic');
    final question = cell('question');
    final options = [
      cell('optiona'),
      cell('optionb'),
      cell('optionc'),
      cell('optiond'),
    ];
    final explanation = cell('explanation');
    var difficulty = cell('difficulty');
    if (!['Easy', 'Medium', 'Hard'].contains(difficulty)) {
      difficulty = 'Medium';
    }
    final source = cell('source');
    final tagsRaw = cell('tags');
    final tags = tagsRaw.isEmpty
        ? <String>[]
        : tagsRaw
            .split(RegExp('[|,]'))
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList();

    final errors = <String>[];
    if (question.isEmpty) errors.add('Question is empty');
    if (subject.isEmpty) errors.add('Missing subject');
    if (chapter.isEmpty) errors.add('Missing chapter');
    if (topic.isEmpty) errors.add('Missing topic');
    if (!isValidTargetGroupLabel(targetRaw)) {
      errors.add('Invalid target group');
    }
    if (exam.isNotEmpty && !ContentIndexResolver.isAllowedExamLabel(exam)) {
      errors.add('Invalid exam (MPSC Combine only)');
    }

    final year = int.tryParse(yearRaw);
    final filled = options.where((o) => o.isNotEmpty).toList();
    final correctRaw = cell('correctanswer');
    var correctIndex = -1;
    var answer = correctRaw;
    if (correctRaw.isEmpty) {
      errors.add('Missing answer');
    } else if (filled.length == 4) {
      correctIndex = parseCorrectAnswer(correctRaw, filled) ?? -1;
      if (correctIndex < 0) {
        errors.add('Missing answer');
      } else {
        answer = correctAnswerLetter(correctIndex);
      }
    }

    var examId = kDefaultExamId;
    var subjectId = '';
    var chapterId = '';
    var topicId = '';
    var subjectTitle = subject;
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
      subjectTitle = resolved.subjectTitle;
      for (final e in resolved.errors) {
        if (!errors.contains(e)) errors.add(e);
      }
    }

    return BulkPyqRow(
      rowNumber: rowNumber,
      exam: exam,
      targetGroup: isValidTargetGroupLabel(targetRaw)
          ? targetGroupToString(targetGroupFromString(targetRaw))
          : targetRaw,
      year: year,
      subject: subject,
      chapter: chapter,
      topic: topic,
      question: question,
      options: filled.length == 4 ? filled : options.where((o) => o.isNotEmpty).toList(),
      correctIndex: correctIndex < 0 ? 0 : correctIndex,
      answer: answer,
      explanation: explanation,
      difficulty: difficulty,
      source: source,
      tags: tags,
      examId: examId,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      subjectTitle: subjectTitle,
      errors: errors,
    );
  }
}

const List<String> bulkPyqExpectedHeaders = [
  'Exam',
  'Target Group',
  'Year',
  'Subject',
  'Chapter',
  'Topic',
  'Question',
  'Option A',
  'Option B',
  'Option C',
  'Option D',
  'Correct Answer',
  'Explanation',
  'Difficulty',
  'Source',
  'Tags',
];
