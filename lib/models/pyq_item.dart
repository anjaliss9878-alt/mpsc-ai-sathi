import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// A Previous Year Question entry, stored in Firestore at `pyqs/{id}`.
///
/// Supports two authoring styles, chosen from the Admin Panel:
/// - **Paper link** (legacy/default): [title] + [subtitle] + a link to the
///   full paper/solutions ([fileUrl]).
/// - **Structured question**: an individual [year]/[examName] question with
///   its own [answer]/[explanation], enabling the "filter by year" list.
///
/// Content-index ids reuse Part 1 (`examId`, `subjectId`, `chapterId`,
/// `topicId`) plus [targetGroup]. There is no parallel subject tree.
class PyqItem {
  const PyqItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.fileUrl,
    required this.order,
    this.year,
    this.examName = '',
    this.question = '',
    this.answer = '',
    this.explanation = '',
    this.subjectId = '',
    this.chapterId = '',
    this.subject = '',
    this.tags = const [],
    this.published = true,
    this.examId = kDefaultExamId,
    this.targetGroup = 'groupB',
    this.topicId = '',
    this.options = const [],
    this.correctIndex = 0,
    this.difficulty = 'Medium',
    this.source = '',
    this.status = NoteWorkflowStatus.published,
  });

  final String id;
  final String title;
  final String subtitle;
  final String fileUrl;
  final int order;

  final int? year;
  final String examName;
  final String question;
  final String answer;
  final String explanation;

  final String subjectId;
  final String chapterId;
  final String subject;
  final List<String> tags;
  final bool published;

  final String examId;
  final String targetGroup;
  final String topicId;
  final List<String> options;
  final int correctIndex;
  final String difficulty;
  final String source;
  final NoteWorkflowStatus status;

  String get groupId => targetGroup;

  bool get isStructuredQuestion => question.isNotEmpty;

  bool get isStudentVisible =>
      published && contentWorkflowIsStudentVisible(status);

  /// Clean text for the existing RAG chunker (question, answer, year, index).
  String get searchableText {
    final buf = StringBuffer();
    if (year != null) buf.writeln('$year');
    if (examName.trim().isNotEmpty) buf.writeln(examName.trim());
    if (title.trim().isNotEmpty) buf.writeln(title.trim());
    if (subject.trim().isNotEmpty) buf.writeln(subject.trim());
    if (question.trim().isNotEmpty) buf.writeln(question.trim());
    for (var i = 0; i < options.length; i++) {
      final opt = options[i].trim();
      if (opt.isEmpty) continue;
      buf.writeln('${String.fromCharCode(65 + i)}) $opt');
    }
    if (answer.trim().isNotEmpty) buf.writeln(answer.trim());
    if (explanation.trim().isNotEmpty) buf.writeln(explanation.trim());
    if (subtitle.trim().isNotEmpty) buf.writeln(subtitle.trim());
    if (difficulty.trim().isNotEmpty) buf.writeln(difficulty.trim());
    if (source.trim().isNotEmpty) buf.writeln(source.trim());
    for (final tag in tags) {
      if (tag.trim().isNotEmpty) buf.writeln(tag.trim());
    }
    return buf.toString();
  }

  factory PyqItem.fromMap(Map<String, dynamic> map, String id) {
    final published = asBool(map['published'], defaultValue: true);
    final status = contentWorkflowStatusFromString(
      map['status'] as String?,
      published: published,
    );
    final target = (map['targetGroup'] as String?)?.trim().isNotEmpty == true
        ? (map['targetGroup'] as String).trim()
        : ((map['groupId'] as String?)?.trim() ?? '');
    return PyqItem(
      id: id,
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      fileUrl: map['fileUrl'] as String? ?? '',
      order: asInt(map['order']),
      year: (map['year'] as num?)?.toInt(),
      examName: map['examName'] as String? ?? '',
      question: map['question'] as String? ?? '',
      answer: map['answer'] as String? ?? '',
      explanation: map['explanation'] as String? ?? '',
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      tags: asStringList(map['tags']),
      published: published && contentWorkflowPublishedFlag(status),
      examId: (map['examId'] as String?)?.trim().isNotEmpty == true
          ? (map['examId'] as String).trim()
          : kDefaultExamId,
      targetGroup: targetGroupToString(targetGroupFromString(target)),
      topicId: map['topicId'] as String? ?? '',
      options: asStringList(map['options']),
      correctIndex: asInt(map['correctIndex']),
      difficulty: map['difficulty'] as String? ?? 'Medium',
      source: map['source'] as String? ?? '',
      status: status,
    );
  }

  Map<String, dynamic> toMap() {
    final group = targetGroupToString(targetGroupFromString(targetGroup));
    return {
      'title': title,
      'subtitle': subtitle,
      'fileUrl': fileUrl,
      'order': order,
      'year': year,
      'examName': examName,
      'question': question,
      'answer': answer,
      'explanation': explanation,
      'subjectId': subjectId,
      'chapterId': chapterId,
      'subject': subject,
      'tags': tags,
      'published': published && contentWorkflowPublishedFlag(status),
      'examId': examId.isEmpty ? kDefaultExamId : examId,
      'targetGroup': group,
      'groupId': group,
      'topicId': topicId,
      'options': options,
      'correctIndex': correctIndex,
      'difficulty': difficulty,
      'source': source,
      'status': contentWorkflowStatusToString(status),
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  PyqItem copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? fileUrl,
    int? order,
    int? year,
    String? examName,
    String? question,
    String? answer,
    String? explanation,
    String? subjectId,
    String? chapterId,
    String? subject,
    List<String>? tags,
    bool? published,
    String? examId,
    String? targetGroup,
    String? topicId,
    List<String>? options,
    int? correctIndex,
    String? difficulty,
    String? source,
    NoteWorkflowStatus? status,
  }) {
    final nextStatus = status ?? this.status;
    return PyqItem(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      fileUrl: fileUrl ?? this.fileUrl,
      order: order ?? this.order,
      year: year ?? this.year,
      examName: examName ?? this.examName,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      explanation: explanation ?? this.explanation,
      subjectId: subjectId ?? this.subjectId,
      chapterId: chapterId ?? this.chapterId,
      subject: subject ?? this.subject,
      tags: tags ?? this.tags,
      published: published ?? contentWorkflowPublishedFlag(nextStatus),
      examId: examId ?? this.examId,
      targetGroup: targetGroup ?? this.targetGroup,
      topicId: topicId ?? this.topicId,
      options: options ?? this.options,
      correctIndex: correctIndex ?? this.correctIndex,
      difficulty: difficulty ?? this.difficulty,
      source: source ?? this.source,
      status: nextStatus,
    );
  }
}
