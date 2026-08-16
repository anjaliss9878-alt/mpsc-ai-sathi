import 'package:mpsc_combine_ai/utils/json_list.dart';

/// A current affairs entry, stored in Firestore at `currentAffairs/{id}`.
class CurrentAffairItem {
  const CurrentAffairItem({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.date,
    this.pdfUrl = '',
    this.monthlyPdfUrl = '',
    this.quizQuestion = '',
    this.quizOptions = const [],
    this.quizCorrectIndex = 0,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final DateTime date;

  /// Optional daily CA PDF (Storage / external).
  final String pdfUrl;

  /// Optional monthly digest PDF.
  final String monthlyPdfUrl;

  /// Optional quick quiz tied to this CA entry.
  final String quizQuestion;
  final List<String> quizOptions;
  final int quizCorrectIndex;

  bool get hasQuiz =>
      quizQuestion.isNotEmpty && quizOptions.length >= 2;

  factory CurrentAffairItem.fromMap(Map<String, dynamic> map, String id) {
    return CurrentAffairItem(
      id: id,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      category: map['category'] as String? ?? 'General',
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      pdfUrl: map['pdfUrl'] as String? ?? '',
      monthlyPdfUrl: map['monthlyPdfUrl'] as String? ?? '',
      quizQuestion: map['quizQuestion'] as String? ?? '',
      quizOptions: asStringList(map['quizOptions']),
      quizCorrectIndex: (map['quizCorrectIndex'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'category': category,
      'date': date.toIso8601String(),
      'pdfUrl': pdfUrl,
      'monthlyPdfUrl': monthlyPdfUrl,
      'quizQuestion': quizQuestion,
      'quizOptions': quizOptions,
      'quizCorrectIndex': quizCorrectIndex,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}
