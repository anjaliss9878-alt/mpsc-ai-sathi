import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// A single MCQ practice question, stored in Firestore at `mcqs/{id}`.
///
/// Questions are grouped into practice "sets" purely by [setTitle] — the
/// student MCQ Practice screen groups documents client-side by this field,
/// so the Admin Panel doesn't need a separate "sets" collection.
class McqItem {
  const McqItem({
    required this.id,
    required this.setTitle,
    required this.subject,
    required this.difficulty,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.order,
    this.tags = const [],
    this.subjectId = '',
    this.chapterId = '',
    this.published = true,
    this.examId = kDefaultExamId,
    this.targetGroup = 'groupB',
    this.topicId = '',
    this.status = NoteWorkflowStatus.published,
  });

  final String id;
  final String setTitle;

  /// Free-text subject label (legacy). Prefer [subjectId] when linking.
  final String subject;
  final String difficulty;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final int order;

  /// Free-form labels (e.g. topic, exam year) used for search/filtering in
  /// both the Admin Panel and Bulk Upload de-duplication.
  final List<String> tags;

  /// Firestore `subjects/{id}` link (optional; empty for legacy rows).
  final String subjectId;

  /// Firestore `chapters/{id}` link (optional).
  final String chapterId;

  final bool published;

  final String examId;
  final String targetGroup;
  final String topicId;
  final NoteWorkflowStatus status;

  String get groupId => targetGroup;

  bool get isStudentVisible =>
      published && contentWorkflowIsStudentVisible(status);

  factory McqItem.fromMap(Map<String, dynamic> map, String id) {
    final published = asBool(map['published'], defaultValue: true);
    final status = contentWorkflowStatusFromString(
      map['status'] as String?,
      published: published,
    );
    final target = (map['targetGroup'] as String?)?.trim().isNotEmpty == true
        ? (map['targetGroup'] as String).trim()
        : ((map['groupId'] as String?)?.trim() ?? '');
    return McqItem(
      id: id,
      setTitle: map['setTitle'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      difficulty: map['difficulty'] as String? ?? 'Medium',
      question: map['question'] as String? ?? '',
      options: asStringList(map['options']),
      correctIndex: asInt(map['correctIndex']),
      explanation: map['explanation'] as String? ?? '',
      order: asInt(map['order']),
      tags: asStringList(map['tags']),
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      published: published && contentWorkflowPublishedFlag(status),
      examId: (map['examId'] as String?)?.trim().isNotEmpty == true
          ? (map['examId'] as String).trim()
          : kDefaultExamId,
      targetGroup: targetGroupToString(targetGroupFromString(target)),
      topicId: map['topicId'] as String? ?? '',
      status: status,
    );
  }

  Map<String, dynamic> toMap() {
    final group = targetGroupToString(targetGroupFromString(targetGroup));
    return {
      'setTitle': setTitle,
      'subject': subject,
      'difficulty': difficulty,
      'question': question,
      'options': options,
      'correctIndex': correctIndex,
      'explanation': explanation,
      'order': order,
      'tags': tags,
      'subjectId': subjectId,
      'chapterId': chapterId,
      'published': published && contentWorkflowPublishedFlag(status),
      'examId': examId.isEmpty ? kDefaultExamId : examId,
      'targetGroup': group,
      'groupId': group,
      'topicId': topicId,
      'status': contentWorkflowStatusToString(status),
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  McqItem copyWith({
    String? setTitle,
    String? subject,
    String? difficulty,
    String? question,
    List<String>? options,
    int? correctIndex,
    String? explanation,
    int? order,
    List<String>? tags,
    String? subjectId,
    String? chapterId,
    bool? published,
    String? examId,
    String? targetGroup,
    String? topicId,
    NoteWorkflowStatus? status,
  }) {
    final nextStatus = status ?? this.status;
    return McqItem(
      id: id,
      setTitle: setTitle ?? this.setTitle,
      subject: subject ?? this.subject,
      difficulty: difficulty ?? this.difficulty,
      question: question ?? this.question,
      options: options ?? this.options,
      correctIndex: correctIndex ?? this.correctIndex,
      explanation: explanation ?? this.explanation,
      order: order ?? this.order,
      tags: tags ?? this.tags,
      subjectId: subjectId ?? this.subjectId,
      chapterId: chapterId ?? this.chapterId,
      published: published ?? contentWorkflowPublishedFlag(nextStatus),
      examId: examId ?? this.examId,
      targetGroup: targetGroup ?? this.targetGroup,
      topicId: topicId ?? this.topicId,
      status: nextStatus,
    );
  }
}
