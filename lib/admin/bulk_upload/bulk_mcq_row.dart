import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/services/content_index_resolver.dart';
import 'package:mpsc_combine_ai/utils/bulk_cells.dart';
import 'package:mpsc_combine_ai/utils/correct_answer.dart';

/// One parsed (and validated) row from an admin-uploaded CSV/XLSX file,
/// destined to become an `McqItem` once it passes validation and isn't a
/// duplicate of an existing question.
class BulkMcqRow {
  BulkMcqRow({
    required this.rowNumber,
    required this.setTitle,
    required this.subject,
    required this.difficulty,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.tags,
    this.exam = '',
    this.targetGroup = '',
    this.chapter = '',
    this.topic = '',
    this.examId = kDefaultExamId,
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
    this.errors = const [],
    this.isDuplicate = false,
  });

  final int rowNumber;
  final String setTitle;
  final String subject;
  final String difficulty;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final List<String> tags;
  final String exam;
  final String targetGroup;
  final String chapter;
  final String topic;
  final String examId;
  final String subjectId;
  final String chapterId;
  final String topicId;

  /// Human-readable validation problems. Empty means the row is structurally
  /// valid (duplicate-checking is tracked separately via [isDuplicate]).
  final List<String> errors;

  bool isDuplicate;

  bool get isValid => errors.isEmpty;
  bool get willUpload => isValid && !isDuplicate;

  /// Parses and validates one row of raw string cells, keyed by lower-cased
  /// header name. Never throws — problems are recorded in [errors] instead,
  /// so the whole preview table can render even for very messy files.
  factory BulkMcqRow.parse(
    int rowNumber,
    Map<String, String> cells, {
    ContentIndexResolver? index,
  }) {
    final n = normalizeBulkCells(cells);
    String cell(String key) => bulkCell(n, key);

    final setTitle = cell('settitle').isEmpty ? 'Imported MCQs' : cell('settitle');
    final subject = cell('subject');
    final chapter = cell('chapter');
    final topic = cell('topic');
    final exam = cell('exam');
    final targetRaw = cell('targetgroup');
    var difficulty = cell('difficulty');
    if (!['Easy', 'Medium', 'Hard'].contains(difficulty)) {
      difficulty = 'Medium';
    }
    final question = cell('question');
    final options = [
      cell('optiona'),
      cell('optionb'),
      cell('optionc'),
      cell('optiond'),
    ];
    final explanation = cell('explanation');
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
    if (options.any((o) => o.isEmpty)) {
      errors.add('Needs four options (A–D)');
    }
    if (subject.isEmpty) errors.add('Missing subject');
    if (chapter.isEmpty) errors.add('Missing chapter');
    if (topic.isEmpty) errors.add('Missing topic');
    if (!isValidTargetGroupLabel(targetRaw)) {
      errors.add('Invalid target group');
    }

    final filledOptions = options.where((o) => o.isNotEmpty).toList();
    int correctIndex = -1;
    final correctRaw = cell('correctanswer').isNotEmpty
        ? cell('correctanswer')
        : cell('correctindex');
    if (correctRaw.isEmpty) {
      errors.add('Missing answer');
    } else {
      correctIndex = parseCorrectAnswer(correctRaw, filledOptions) ?? -1;
      if (correctIndex < 0) {
        errors.add('Missing answer');
      }
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

    return BulkMcqRow(
      rowNumber: rowNumber,
      setTitle: setTitle,
      subject: subject,
      difficulty: difficulty,
      question: question,
      options: options,
      correctIndex: correctIndex < 0 ? 0 : correctIndex,
      explanation: explanation,
      tags: tags,
      exam: exam,
      targetGroup: isValidTargetGroupLabel(targetRaw)
          ? targetGroupToString(targetGroupFromString(targetRaw))
          : targetRaw,
      chapter: chapter,
      topic: topic,
      examId: examId,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      errors: errors,
    );
  }
}

/// Expected header names (case-insensitive). Shown to the admin as a
/// template hint above the file picker.
const List<String> bulkMcqExpectedHeaders = [
  'Exam',
  'Target Group',
  'Subject',
  'Chapter',
  'Topic',
  'setTitle',
  'difficulty',
  'question',
  'optionA',
  'optionB',
  'optionC',
  'optionD',
  'Correct Answer',
  'explanation',
  'tags',
];
