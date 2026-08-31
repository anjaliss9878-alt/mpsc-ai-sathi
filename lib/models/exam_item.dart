import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Stable id for the default MPSC Combine exam document at `exams/{id}`.
const String kDefaultExamId = 'mpsc_combine';

/// An exam at the top of the content index:
/// Exam → Subject → Chapter → Topic → Sub-topic.
///
/// Stored in Firestore at `exams/{examId}`. Subjects, chapters, notes, and
/// RAG sources reuse this id via `examId`.
class ExamItem {
  const ExamItem({
    required this.id,
    required this.title,
    this.titleEn = '',
    this.order = 0,
    this.published = true,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String titleEn;
  final int order;
  final bool published;
  final DateTime? updatedAt;

  factory ExamItem.mpscCombine() {
    return const ExamItem(
      id: kDefaultExamId,
      title: kMpscDefaultExam,
      titleEn: 'MPSC Combine',
      order: 0,
      published: true,
    );
  }

  factory ExamItem.fromMap(Map<String, dynamic> map, String id) {
    final rawTitle = map['title'] ?? map['name'] ?? map['nameEn'];
    final title = rawTitle is String ? rawTitle.trim() : '';
    return ExamItem(
      id: id,
      title: title.isNotEmpty ? title : kMpscDefaultExam,
      titleEn: map['titleEn'] as String? ?? '',
      order: asInt(map['order']),
      published: asBool(map['published'], defaultValue: true),
      updatedAt: _parseUpdatedAt(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'titleEn': titleEn,
      'order': order,
      'published': published,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  ExamItem copyWith({
    String? title,
    String? titleEn,
    int? order,
    bool? published,
    DateTime? updatedAt,
  }) {
    return ExamItem(
      id: id,
      title: title ?? this.title,
      titleEn: titleEn ?? this.titleEn,
      order: order ?? this.order,
      published: published ?? this.published,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

DateTime? _parseUpdatedAt(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
