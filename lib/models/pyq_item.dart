import 'package:mpsc_combine_ai/utils/json_list.dart';

/// A Previous Year Question entry, stored in Firestore at `pyqs/{id}`.
///
/// Supports two authoring styles, chosen from the Admin Panel:
/// - **Paper link** (legacy/default): [title] + [subtitle] + a link to the
///   full paper/solutions ([fileUrl]).
/// - **Structured question**: an individual [year]/[examName] question with
///   its own [answer]/[explanation], enabling the "filter by year" list.
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

  bool get isStructuredQuestion => question.isNotEmpty;

  factory PyqItem.fromMap(Map<String, dynamic> map, String id) {
    return PyqItem(
      id: id,
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      fileUrl: map['fileUrl'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      year: (map['year'] as num?)?.toInt(),
      examName: map['examName'] as String? ?? '',
      question: map['question'] as String? ?? '',
      answer: map['answer'] as String? ?? '',
      explanation: map['explanation'] as String? ?? '',
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      tags: asStringList(map['tags']),
      published: map['published'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
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
      'published': published,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}
