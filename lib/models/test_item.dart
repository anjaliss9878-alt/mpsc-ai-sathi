/// One question embedded inside a [TestItem].
class TestQuestion {
  const TestQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  factory TestQuestion.fromMap(Map<String, dynamic> map) {
    return TestQuestion(
      question: map['question'] as String? ?? '',
      options: List<String>.from(map['options'] as List? ?? const []),
      correctIndex: (map['correctIndex'] as num?)?.toInt() ?? 0,
      explanation: map['explanation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'question': question,
      'options': options,
      'correctIndex': correctIndex,
      'explanation': explanation,
    };
  }
}

/// A Mock Test / CBT paper, stored in Firestore at `tests/{id}` with its
/// questions embedded directly (well within Firestore's 1MB document limit
/// for typical MCQ counts, and much simpler to author from the Admin Panel).
class TestItem {
  const TestItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.durationSeconds,
    required this.correctMarks,
    required this.negativeMarks,
    required this.questions,
    required this.order,
  });

  final String id;
  final String title;
  final String subtitle;
  final int durationSeconds;
  final double correctMarks;
  final double negativeMarks;
  final List<TestQuestion> questions;
  final int order;

  factory TestItem.fromMap(Map<String, dynamic> map, String id) {
    final rawQuestions = map['questions'] as List? ?? const [];
    return TestItem(
      id: id,
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 600,
      correctMarks: (map['correctMarks'] as num?)?.toDouble() ?? 2.0,
      negativeMarks: (map['negativeMarks'] as num?)?.toDouble() ?? 0.5,
      questions: rawQuestions
          .map((q) => TestQuestion.fromMap(Map<String, dynamic>.from(q as Map)))
          .toList(),
      order: (map['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subtitle': subtitle,
      'durationSeconds': durationSeconds,
      'correctMarks': correctMarks,
      'negativeMarks': negativeMarks,
      'questions': questions.map((q) => q.toMap()).toList(),
      'order': order,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}
