/// A student bookmark stored at `students/{uid}/bookmarks/{id}`.
class BookmarkItem {
  const BookmarkItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.refId,
    this.meta = const {},
    this.createdAt,
  });

  /// One of: `note`, `mcq`, `chapter`, `topic`.
  final String id;
  final String type;
  final String title;
  final String subtitle;
  final String refId;
  final Map<String, dynamic> meta;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
        'type': type,
        'title': title,
        'subtitle': subtitle,
        'refId': refId,
        'meta': meta,
        'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
      };

  factory BookmarkItem.fromMap(Map<String, dynamic> map, String id) {
    return BookmarkItem(
      id: id,
      type: map['type'] as String? ?? '',
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      refId: map['refId'] as String? ?? '',
      meta: Map<String, dynamic>.from(map['meta'] as Map? ?? const {}),
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? ''),
    );
  }
}
