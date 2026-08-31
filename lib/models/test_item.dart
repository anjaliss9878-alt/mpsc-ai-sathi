import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// One question embedded inside a [TestItem].
class TestQuestion {
  const TestQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  factory TestQuestion.fromMap(Map<String, dynamic> map) {
    return TestQuestion(
      question: map['question'] as String? ?? '',
      options: asStringList(map['options']),
      correctIndex: asInt(map['correctIndex']),
      explanation: map['explanation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'question': question,
      'options': options,
      'correctIndex': correctIndex,
      'explanation': explanation,
    };
  }
}

/// A Mock Test / CBT paper, stored in Firestore at `tests/{id}` with its
/// questions embedded directly (well within Firestore's 1MB document limit
/// for typical MCQ counts, and much simpler to author from the Admin Panel).
///
/// Reuses the existing student CBT engine. New fields (exam / group / topic /
/// publish status) are additive — missing `published` is treated as true so
/// legacy papers stay visible.
class TestItem {
  const TestItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.durationSeconds,
    required this.correctMarks,
    required this.negativeMarks,
    required this.questions,
    required this.order,
    this.examId = kDefaultExamId,
    this.targetGroup = 'groupB',
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
    this.topicIds = const [],
    this.difficulty = 'Medium',
    this.instructions = '',
    this.published = true,
    this.status = NoteWorkflowStatus.published,
  });

  final String id;
  final String title;
  final String subtitle;
  final int durationSeconds;
  final double correctMarks;
  final double negativeMarks;
  final List<TestQuestion> questions;
  final int order;

  final String examId;
  final String targetGroup;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final List<String> topicIds;
  final String difficulty;
  final String instructions;
  final bool published;
  final NoteWorkflowStatus status;

  String get groupId => targetGroup;

  int get questionCount => questions.length;

  bool get isStudentVisible =>
      published && contentWorkflowIsStudentVisible(status);

  factory TestItem.fromMap(Map<String, dynamic> map, String id) {
    final published = asBool(map['published'], defaultValue: true);
    final status = contentWorkflowStatusFromString(
      map['status'] as String?,
      published: published,
    );
    final target = (map['targetGroup'] as String?)?.trim().isNotEmpty == true
        ? (map['targetGroup'] as String).trim()
        : ((map['groupId'] as String?)?.trim() ?? '');
    final topicIds = asStringList(map['topicIds']);
    final topicId = (map['topicId'] as String?)?.trim() ?? '';
    return TestItem(
      id: id,
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      durationSeconds: asInt(map['durationSeconds'], defaultValue: 600),
      correctMarks: (map['correctMarks'] as num?)?.toDouble() ?? 2.0,
      negativeMarks: (map['negativeMarks'] as num?)?.toDouble() ?? 0.5,
      questions: asMapList(map['questions']).map(TestQuestion.fromMap).toList(),
      order: asInt(map['order']),
      examId: (map['examId'] as String?)?.trim().isNotEmpty == true
          ? (map['examId'] as String).trim()
          : kDefaultExamId,
      targetGroup: targetGroupToString(targetGroupFromString(target)),
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      topicId: topicId.isNotEmpty
          ? topicId
          : (topicIds.isNotEmpty ? topicIds.first : ''),
      topicIds: topicIds,
      difficulty: map['difficulty'] as String? ?? 'Medium',
      instructions: map['instructions'] as String? ?? '',
      published: published && contentWorkflowPublishedFlag(status),
      status: status,
    );
  }

  Map<String, dynamic> toMap() {
    final group = targetGroupToString(targetGroupFromString(targetGroup));
    final ids = topicIds.isNotEmpty
        ? topicIds
        : (topicId.isNotEmpty ? [topicId] : const <String>[]);
    return {
      'title': title,
      'subtitle': subtitle,
      'durationSeconds': durationSeconds,
      'correctMarks': correctMarks,
      'negativeMarks': negativeMarks,
      'questions': questions.map((q) => q.toMap()).toList(),
      'order': order,
      'examId': examId.isEmpty ? kDefaultExamId : examId,
      'targetGroup': group,
      'groupId': group,
      'subjectId': subjectId,
      'chapterId': chapterId,
      'topicId': topicId,
      'topicIds': ids,
      'difficulty': difficulty,
      'instructions': instructions,
      'published': published && contentWorkflowPublishedFlag(status),
      'status': contentWorkflowStatusToString(status),
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  TestItem copyWith({
    String? title,
    String? subtitle,
    int? durationSeconds,
    double? correctMarks,
    double? negativeMarks,
    List<TestQuestion>? questions,
    int? order,
    String? examId,
    String? targetGroup,
    String? subjectId,
    String? chapterId,
    String? topicId,
    List<String>? topicIds,
    String? difficulty,
    String? instructions,
    bool? published,
    NoteWorkflowStatus? status,
  }) {
    final nextStatus = status ?? this.status;
    return TestItem(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      correctMarks: correctMarks ?? this.correctMarks,
      negativeMarks: negativeMarks ?? this.negativeMarks,
      questions: questions ?? this.questions,
      order: order ?? this.order,
      examId: examId ?? this.examId,
      targetGroup: targetGroup ?? this.targetGroup,
      subjectId: subjectId ?? this.subjectId,
      chapterId: chapterId ?? this.chapterId,
      topicId: topicId ?? this.topicId,
      topicIds: topicIds ?? this.topicIds,
      difficulty: difficulty ?? this.difficulty,
      instructions: instructions ?? this.instructions,
      published: published ?? contentWorkflowPublishedFlag(nextStatus),
      status: nextStatus,
    );
  }
}
