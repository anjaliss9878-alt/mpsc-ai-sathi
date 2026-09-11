import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Content kinds produced by Admin → AI Content Generator.
enum AiGeneratedContentType {
  notes,
  mcq,
  flashcard,
  revisionSummary,
  importantPoints,
  smartTrick,
  aiTeacherLesson,
}

String aiGeneratedContentTypeToString(AiGeneratedContentType type) {
  switch (type) {
    case AiGeneratedContentType.notes:
      return 'notes';
    case AiGeneratedContentType.mcq:
      return 'mcq';
    case AiGeneratedContentType.flashcard:
      return 'flashcard';
    case AiGeneratedContentType.revisionSummary:
      return 'revisionSummary';
    case AiGeneratedContentType.importantPoints:
      return 'importantPoints';
    case AiGeneratedContentType.smartTrick:
      return 'smartTrick';
    case AiGeneratedContentType.aiTeacherLesson:
      return 'aiTeacherLesson';
  }
}

AiGeneratedContentType? aiGeneratedContentTypeFromString(String? raw) {
  switch ((raw ?? '').trim()) {
    case 'notes':
      return AiGeneratedContentType.notes;
    case 'mcq':
      return AiGeneratedContentType.mcq;
    case 'flashcard':
      return AiGeneratedContentType.flashcard;
    case 'revisionSummary':
      return AiGeneratedContentType.revisionSummary;
    case 'importantPoints':
      return AiGeneratedContentType.importantPoints;
    case 'smartTrick':
      return AiGeneratedContentType.smartTrick;
    case 'aiTeacherLesson':
      return AiGeneratedContentType.aiTeacherLesson;
    default:
      return null;
  }
}

String aiGeneratedContentTypeLabel(AiGeneratedContentType type) {
  switch (type) {
    case AiGeneratedContentType.notes:
      return 'Notes';
    case AiGeneratedContentType.mcq:
      return 'MCQs (AI Practice)';
    case AiGeneratedContentType.flashcard:
      return 'Flashcards';
    case AiGeneratedContentType.revisionSummary:
      return 'Revision Summary';
    case AiGeneratedContentType.importantPoints:
      return 'Important Points';
    case AiGeneratedContentType.smartTrick:
      return 'Smart Tricks';
    case AiGeneratedContentType.aiTeacherLesson:
      return 'AI Teacher Lesson';
  }
}

/// Request from the Admin AI Content Generator form.
class AiContentGenerationRequest {
  const AiContentGenerationRequest({
    required this.examId,
    required this.subjectId,
    required this.chapterId,
    required this.sourceId,
    required this.types,
    this.topicId = '',
    this.examTitle = '',
    this.subjectTitle = '',
    this.chapterTitle = '',
    this.topicTitle = '',
    this.sourceTitle = '',
    this.mcqCount = 10,
    this.flashcardCount = 10,
    this.difficulty = 'Medium',
    this.generationBatchId = '',
  });

  final String examId;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final String sourceId;
  final String examTitle;
  final String subjectTitle;
  final String chapterTitle;
  final String topicTitle;
  final String sourceTitle;
  final Set<AiGeneratedContentType> types;
  final int mcqCount;
  final int flashcardCount;
  final String difficulty;
  final String generationBatchId;

  String get topicLabel {
    final parts = <String>[
      if (subjectTitle.isNotEmpty) subjectTitle,
      if (chapterTitle.isNotEmpty) chapterTitle,
      if (topicTitle.isNotEmpty) topicTitle,
    ];
    return parts.join(' / ');
  }
}

/// One draft document in Firestore `aiGeneratedContent/{id}`.
class AiGeneratedContentItem {
  const AiGeneratedContentItem({
    required this.id,
    required this.examId,
    required this.subjectId,
    required this.chapterId,
    required this.sourceId,
    required this.contentType,
    required this.content,
    required this.status,
    this.topicId = '',
    this.sourceCitation = '',
    this.generationBatchId = '',
    this.promotedCollection = '',
    this.promotedDocId = '',
    this.error = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String examId;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final String sourceId;
  final AiGeneratedContentType contentType;
  final Map<String, dynamic> content;
  final String sourceCitation;
  final NoteWorkflowStatus status;
  final String generationBatchId;
  final String promotedCollection;
  final String promotedDocId;
  final String error;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isDraft => status == NoteWorkflowStatus.draft;
  bool get isPublished =>
      status == NoteWorkflowStatus.published && promotedDocId.isNotEmpty;

  factory AiGeneratedContentItem.fromMap(Map<String, dynamic> map, String id) {
    final type = aiGeneratedContentTypeFromString('${map['contentType']}') ??
        AiGeneratedContentType.notes;
    final contentRaw = map['content'];
    return AiGeneratedContentItem(
      id: id,
      examId: '${map['examId'] ?? kDefaultExamId}'.trim().isEmpty
          ? kDefaultExamId
          : '${map['examId']}'.trim(),
      subjectId: '${map['subjectId'] ?? ''}'.trim(),
      chapterId: '${map['chapterId'] ?? ''}'.trim(),
      topicId: '${map['topicId'] ?? ''}'.trim(),
      sourceId: '${map['sourceId'] ?? ''}'.trim(),
      contentType: type,
      content: contentRaw is Map
          ? Map<String, dynamic>.from(contentRaw)
          : <String, dynamic>{},
      sourceCitation: '${map['sourceCitation'] ?? ''}'.trim(),
      status: contentWorkflowStatusFromString(
        map['status'] as String?,
        published: asBool(map['published'], defaultValue: false),
      ),
      generationBatchId: '${map['generationBatchId'] ?? ''}'.trim(),
      promotedCollection: '${map['promotedCollection'] ?? ''}'.trim(),
      promotedDocId: '${map['promotedDocId'] ?? ''}'.trim(),
      error: '${map['error'] ?? ''}'.trim(),
      createdAt: _parseDate(map['createdAt']),
      updatedAt: _parseDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    final now = DateTime.now().toIso8601String();
    return {
      'examId': examId,
      'subjectId': subjectId,
      'chapterId': chapterId,
      'topicId': topicId,
      'sourceId': sourceId,
      'contentType': aiGeneratedContentTypeToString(contentType),
      'content': content,
      'sourceCitation': sourceCitation,
      'status': noteWorkflowStatusToString(status),
      'published': noteWorkflowPublishedFlag(status),
      'generationBatchId': generationBatchId,
      'promotedCollection': promotedCollection,
      'promotedDocId': promotedDocId,
      'error': error,
      'label': 'AI Practice / AI Generated',
      'createdAt': createdAt?.toIso8601String() ?? now,
      'updatedAt': now,
    };
  }

  AiGeneratedContentItem copyWith({
    NoteWorkflowStatus? status,
    Map<String, dynamic>? content,
    String? sourceCitation,
    String? promotedCollection,
    String? promotedDocId,
    String? error,
  }) {
    return AiGeneratedContentItem(
      id: id,
      examId: examId,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      sourceId: sourceId,
      contentType: contentType,
      content: content ?? this.content,
      sourceCitation: sourceCitation ?? this.sourceCitation,
      status: status ?? this.status,
      generationBatchId: generationBatchId,
      promotedCollection: promotedCollection ?? this.promotedCollection,
      promotedDocId: promotedDocId ?? this.promotedDocId,
      error: error ?? this.error,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }
}

/// MCQ validation for AI output (never silently save bad rows).
class AiGeneratedMcqValidation {
  const AiGeneratedMcqValidation._(this.ok, this.error);

  final bool ok;
  final String error;

  static const AiGeneratedMcqValidation valid = AiGeneratedMcqValidation._(true, '');

  factory AiGeneratedMcqValidation.check(Map<String, dynamic> row) {
    final question = '${row['question'] ?? ''}'.trim();
    if (question.isEmpty) {
      return const AiGeneratedMcqValidation._(false, 'Empty question');
    }
    var options = asStringList(row['options']);
    if (options.length != 4) {
      options = [
        '${row['optionA'] ?? ''}'.trim(),
        '${row['optionB'] ?? ''}'.trim(),
        '${row['optionC'] ?? ''}'.trim(),
        '${row['optionD'] ?? ''}'.trim(),
      ];
    }
    if (options.length != 4 || options.any((o) => o.isEmpty)) {
      return const AiGeneratedMcqValidation._(
        false,
        'Need exactly 4 non-empty options',
      );
    }
    final correctRaw = '${row['correctAnswer'] ?? row['correctIndex'] ?? ''}'
        .trim()
        .toUpperCase();
    final correctIndex = _correctIndex(correctRaw, row['correctIndex']);
    if (correctIndex < 0 || correctIndex > 3) {
      return const AiGeneratedMcqValidation._(
        false,
        'correctAnswer must be A/B/C/D (or correctIndex 0-3)',
      );
    }
    if ('${row['explanation'] ?? ''}'.trim().isEmpty) {
      return const AiGeneratedMcqValidation._(false, 'Empty explanation');
    }
    final difficulty = '${row['difficulty'] ?? 'Medium'}'.trim();
    if (!_validDifficulty(difficulty)) {
      return AiGeneratedMcqValidation._(false, 'Invalid difficulty: $difficulty');
    }
    return valid;
  }

  static int _correctIndex(String letterOrIndex, dynamic correctIndexRaw) {
    switch (letterOrIndex) {
      case 'A':
        return 0;
      case 'B':
        return 1;
      case 'C':
        return 2;
      case 'D':
        return 3;
    }
    if (correctIndexRaw is int) return correctIndexRaw;
    return int.tryParse(letterOrIndex) ?? -1;
  }

  static bool _validDifficulty(String value) {
    const allowed = {'Easy', 'Medium', 'Hard', 'Mixed'};
    return allowed.contains(value);
  }
}

/// Normalized MCQ payload after validation.
class AiGeneratedMcqDraft {
  const AiGeneratedMcqDraft({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.difficulty,
    required this.sourceId,
    required this.sourceCitation,
    required this.examId,
    required this.subjectId,
    required this.chapterId,
    this.topicId = '',
  });

  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String difficulty;
  final String sourceId;
  final String sourceCitation;
  final String examId;
  final String subjectId;
  final String chapterId;
  final String topicId;

  /// Never label as MPSC Previous Year Question.
  String get practiceLabel => 'AI Practice Question';

  Map<String, dynamic> toContentMap() => {
        'question': question,
        'optionA': options[0],
        'optionB': options[1],
        'optionC': options[2],
        'optionD': options[3],
        'options': options,
        'correctAnswer': String.fromCharCode(65 + correctIndex),
        'correctIndex': correctIndex,
        'explanation': explanation,
        'difficulty': difficulty,
        'sourceId': sourceId,
        'sourceCitation': sourceCitation,
        'examId': examId,
        'subjectId': subjectId,
        'chapterId': chapterId,
        'topicId': topicId,
        'status': 'draft',
        'label': practiceLabel,
        'isActualPyq': false,
      };

  static AiGeneratedMcqDraft? tryParse(
    Map<String, dynamic> row, {
    required AiContentGenerationRequest request,
    required String sourceCitation,
  }) {
    final check = AiGeneratedMcqValidation.check(row);
    if (!check.ok) return null;
    var options = asStringList(row['options']);
    if (options.length != 4) {
      options = [
        '${row['optionA'] ?? ''}'.trim(),
        '${row['optionB'] ?? ''}'.trim(),
        '${row['optionC'] ?? ''}'.trim(),
        '${row['optionD'] ?? ''}'.trim(),
      ];
    }
    final correctRaw = '${row['correctAnswer'] ?? ''}'.trim().toUpperCase();
    var correctIndex = AiGeneratedMcqValidation._correctIndex(
      correctRaw,
      row['correctIndex'],
    );
    if (correctIndex < 0) correctIndex = 0;
    return AiGeneratedMcqDraft(
      question: '${row['question']}'.trim(),
      options: options,
      correctIndex: correctIndex,
      explanation: '${row['explanation']}'.trim(),
      difficulty: '${row['difficulty'] ?? request.difficulty}'.trim().isEmpty
          ? request.difficulty
          : '${row['difficulty'] ?? request.difficulty}'.trim(),
      sourceId: request.sourceId,
      sourceCitation: () {
        final fromRow = '${row['sourceCitation'] ?? ''}'.trim();
        if (fromRow.isNotEmpty) return fromRow;
        return sourceCitation.trim();
      }(),
      examId: request.examId,
      subjectId: request.subjectId,
      chapterId: request.chapterId,
      topicId: request.topicId,
    );
  }
}

class AiGeneratedFlashcardValidation {
  static String? errorFor(Map<String, dynamic> row) {
    if ('${row['front'] ?? ''}'.trim().isEmpty) return 'Empty flashcard front';
    if ('${row['back'] ?? ''}'.trim().isEmpty) return 'Empty flashcard back';
    return null;
  }
}

/// Progress stages shown in the Admin UI.
enum AiGenerationStage {
  retrieving,
  generatingMcqs,
  generatingFlashcards,
  generatingNotes,
  generatingRevision,
  generatingImportantPoints,
  generatingSmartTricks,
  generatingLesson,
  validating,
  saving,
  done,
  failed,
}

String aiGenerationStageLabel(AiGenerationStage stage) {
  switch (stage) {
    case AiGenerationStage.retrieving:
      return 'Retrieving source…';
    case AiGenerationStage.generatingMcqs:
      return 'Generating MCQs…';
    case AiGenerationStage.generatingFlashcards:
      return 'Generating flashcards…';
    case AiGenerationStage.generatingNotes:
      return 'Generating notes…';
    case AiGenerationStage.generatingRevision:
      return 'Creating revision summary…';
    case AiGenerationStage.generatingImportantPoints:
      return 'Creating important points…';
    case AiGenerationStage.generatingSmartTricks:
      return 'Generating smart tricks…';
    case AiGenerationStage.generatingLesson:
      return 'Generating AI Teacher lesson…';
    case AiGenerationStage.validating:
      return 'Validating…';
    case AiGenerationStage.saving:
      return 'Saving drafts…';
    case AiGenerationStage.done:
      return 'Done';
    case AiGenerationStage.failed:
      return 'Failed';
  }
}
