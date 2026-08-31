import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

class RagGeneratedMcq {
  const RagGeneratedMcq({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.difficulty,
    required this.topic,
    this.citations = const [],
  });

  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final String difficulty;
  final String topic;
  final List<RagCitation> citations;
}

class RagFlashcard {
  const RagFlashcard({
    required this.front,
    required this.back,
    this.explanation = '',
    this.citations = const [],
  });

  final String front;
  final String back;
  final String explanation;
  final List<RagCitation> citations;
}

class RagSourceSummary {
  const RagSourceSummary({
    required this.detailed,
    required this.shortNotes,
    required this.fiveMinuteRevision,
    this.importantFacts = const [],
    this.examPoints = const [],
    this.commonMistakes = const [],
    this.citations = const [],
  });

  final String detailed;
  final String shortNotes;
  final String fiveMinuteRevision;
  final List<String> importantFacts;
  final List<String> examPoints;
  final List<String> commonMistakes;
  final List<RagCitation> citations;
}

class RagQuickRevision {
  const RagQuickRevision({
    this.keyFacts = const [],
    this.terms = const [],
    this.dates = const [],
    this.articles = const [],
    this.committees = const [],
    this.personalities = const [],
    this.examTraps = const [],
    this.citations = const [],
  });

  final List<String> keyFacts;
  final List<String> terms;
  final List<String> dates;
  final List<String> articles;
  final List<String> committees;
  final List<String> personalities;
  final List<String> examTraps;
  final List<RagCitation> citations;
}

class RagMemoryTrick {
  const RagMemoryTrick({
    required this.trick,
    this.citations = const [],
  });

  final String trick;
  final List<RagCitation> citations;
}

class RagVerifiedPyq {
  const RagVerifiedPyq({
    required this.question,
    required this.answer,
    this.year,
    this.explanation = '',
    this.examName = '',
    this.citations = const [],
  });

  final String question;
  final String answer;
  final int? year;
  final String explanation;
  final String examName;
  final List<RagCitation> citations;
}

class RagTeacherAnswer {
  const RagTeacherAnswer({
    required this.markdown,
    required this.citations,
    required this.insufficient,
    this.confidence = 0,
  });

  final String markdown;
  final List<RagCitation> citations;
  final bool insufficient;
  final double confidence;
}

List<String> stringListField(Map<String, dynamic> map, String key) {
  return asStringList(map[key]);
}
