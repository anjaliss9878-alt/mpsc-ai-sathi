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

  factory McqItem.fromMap(Map<String, dynamic> map, String id) {
    return McqItem(
      id: id,
      setTitle: map['setTitle'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      difficulty: map['difficulty'] as String? ?? 'Medium',
      question: map['question'] as String? ?? '',
      options: asStringList(map['options']),
      correctIndex: (map['correctIndex'] as num?)?.toInt() ?? 0,
      explanation: map['explanation'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      tags: asStringList(map['tags']),
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      published: map['published'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
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
      'published': published,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}
