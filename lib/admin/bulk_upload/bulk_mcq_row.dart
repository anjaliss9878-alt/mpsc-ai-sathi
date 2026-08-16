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

  /// Human-readable validation problems. Empty means the row is structurally
  /// valid (duplicate-checking is tracked separately via [isDuplicate]).
  final List<String> errors;

  bool isDuplicate;

  bool get isValid => errors.isEmpty;
  bool get willUpload => isValid && !isDuplicate;

  /// Parses and validates one row of raw string cells, keyed by lower-cased
  /// header name. Never throws — problems are recorded in [errors] instead,
  /// so the whole preview table can render even for very messy files.
  factory BulkMcqRow.parse(int rowNumber, Map<String, String> cells) {
    String cell(String key) => (cells[key] ?? '').trim();

    final setTitle = cell('settitle').isEmpty ? 'Bulk Upload' : cell('settitle');
    final subject = cell('subject');
    var difficulty = cell('difficulty');
    if (!['Easy', 'Medium', 'Hard'].contains(difficulty)) {
      difficulty = 'Medium';
    }
    final question = cell('question');
    final options = [cell('optiona'), cell('optionb'), cell('optionc'), cell('optiond')]
        .where((o) => o.isNotEmpty)
        .toList();
    final explanation = cell('explanation');
    final tagsRaw = cell('tags');
    final tags = tagsRaw.isEmpty
        ? <String>[]
        : tagsRaw.split(RegExp('[|,]')).map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

    final errors = <String>[];
    if (question.isEmpty) errors.add('Question is empty');
    if (subject.isEmpty) errors.add('Subject is empty');
    if (options.length < 2) errors.add('Needs at least 2 options');

    int correctIndex = -1;
    final correctRaw = cell('correctindex');
    if (correctRaw.isEmpty) {
      errors.add('Correct index is empty');
    } else {
      correctIndex = int.tryParse(correctRaw) ?? -1;
      if (correctIndex < 0 || correctIndex >= options.length) {
        errors.add('Correct index out of range (0-${options.length - 1})');
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
      errors: errors,
    );
  }
}

/// Expected header names (case-insensitive). Shown to the admin as a
/// template hint above the file picker.
const List<String> bulkMcqExpectedHeaders = [
  'setTitle',
  'subject',
  'difficulty',
  'question',
  'optionA',
  'optionB',
  'optionC',
  'optionD',
  'correctIndex',
  'explanation',
  'tags',
];
