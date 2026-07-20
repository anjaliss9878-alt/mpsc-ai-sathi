/// A Previous Year Question paper entry, stored in Firestore at `pyqs/{id}`.
///
/// Kept as metadata (+ optional external link to the paper/solutions) rather
/// than embedding full question sets, matching the existing student UI.
class PyqItem {
  const PyqItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.fileUrl,
    required this.order,
  });

  final String id;
  final String title;
  final String subtitle;
  final String fileUrl;
  final int order;

  factory PyqItem.fromMap(Map<String, dynamic> map, String id) {
    return PyqItem(
      id: id,
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      fileUrl: map['fileUrl'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subtitle': subtitle,
      'fileUrl': fileUrl,
      'order': order,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}
