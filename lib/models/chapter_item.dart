/// A chapter within a subject, stored in Firestore at `chapters/{id}`.
class ChapterItem {
  const ChapterItem({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.order,
  });

  final String id;
  final String subjectId;
  final String title;
  final int order;

  factory ChapterItem.fromMap(Map<String, dynamic> map, String id) {
    return ChapterItem(
      id: id,
      subjectId: map['subjectId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'subjectId': subjectId,
      'title': title,
      'order': order,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  ChapterItem copyWith({String? title, int? order}) {
    return ChapterItem(
      id: id,
      subjectId: subjectId,
      title: title ?? this.title,
      order: order ?? this.order,
    );
  }
}
