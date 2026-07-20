/// Result of a single question inside a completed test attempt.
class QuestionResult {
  const QuestionResult({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.selectedIndex,
    this.explanation,
  });

  final String question;
  final List<String> options;
  final int correctIndex;
  final int? selectedIndex;
  final String? explanation;

  bool get isAttempted => selectedIndex != null;
  bool get isCorrect => selectedIndex != null && selectedIndex == correctIndex;
}

/// Summary + full breakdown of a completed CBT/mock test attempt.
class TestResult {
  const TestResult({
    required this.testTitle,
    required this.dateTime,
    required this.totalQuestions,
    required this.attempted,
    required this.correct,
    required this.wrong,
    required this.score,
    required this.maxScore,
    required this.percentage,
    required this.timeTakenSeconds,
    required this.questionResults,
  });

  final String testTitle;
  final DateTime dateTime;
  final int totalQuestions;
  final int attempted;
  final int correct;
  final int wrong;
  final double score;
  final double maxScore;
  final double percentage;
  final int timeTakenSeconds;
  final List<QuestionResult> questionResults;

  int get unattempted => totalQuestions - attempted;
}
