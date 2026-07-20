/// A current affairs entry, stored in Firestore at `currentAffairs/{id}`.
class CurrentAffairItem {
  const CurrentAffairItem({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.date,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final DateTime date;

  factory CurrentAffairItem.fromMap(Map<String, dynamic> map, String id) {
    return CurrentAffairItem(
      id: id,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      category: map['category'] as String? ?? 'General',
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'category': category,
      'date': date.toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}
