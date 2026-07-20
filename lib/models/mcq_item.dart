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
  });

  final String id;
  final String setTitle;
  final String subject;
  final String difficulty;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final int order;

  factory McqItem.fromMap(Map<String, dynamic> map, String id) {
    return McqItem(
      id: id,
      setTitle: map['setTitle'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      difficulty: map['difficulty'] as String? ?? 'Medium',
      question: map['question'] as String? ?? '',
      options: List<String>.from(map['options'] as List? ?? const []),
      correctIndex: (map['correctIndex'] as num?)?.toInt() ?? 0,
      explanation: map['explanation'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
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
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}
