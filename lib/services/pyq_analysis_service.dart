import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';

/// Frequency / priority row derived from uploaded PYQs only.
class PyqFrequencyRow {
  const PyqFrequencyRow({
    required this.id,
    required this.label,
    required this.count,
  });

  final String id;
  final String label;
  final int count;
}

class PyqConceptRow {
  const PyqConceptRow({required this.concept, required this.count});

  final String concept;
  final int count;
}

class PyqPriorityRow {
  const PyqPriorityRow({
    required this.id,
    required this.label,
    required this.score,
    required this.pyqCount,
  });

  final String id;
  final String label;
  final double score;
  final int pyqCount;
}

/// Analysis over **actual uploaded PYQs**. Never rewrites question/answer.
class PyqAnalysis {
  const PyqAnalysis({
    required this.analyzedCount,
    required this.topicFrequency,
    required this.chapterFrequency,
    required this.repeatedConcepts,
    required this.importantAreas,
    required this.difficultyDistribution,
    required this.preparationPriority,
  });

  final int analyzedCount;
  final List<PyqFrequencyRow> topicFrequency;
  final List<PyqFrequencyRow> chapterFrequency;
  final List<PyqConceptRow> repeatedConcepts;
  final List<PyqFrequencyRow> importantAreas;
  final Map<String, int> difficultyDistribution;
  final List<PyqPriorityRow> preparationPriority;

  bool get isEmpty => analyzedCount == 0;
}

bool pyqIsApprovedForAnalysis(PyqItem item) {
  return item.status == NoteWorkflowStatus.approved ||
      item.status == NoteWorkflowStatus.published;
}

/// Official PYQ fields that Admin must edit explicitly — analysis never
/// writes these back.
class PyqOfficialSnapshot {
  const PyqOfficialSnapshot({
    required this.question,
    required this.answer,
    required this.options,
    required this.correctIndex,
  });

  final String question;
  final String answer;
  final List<String> options;
  final int correctIndex;

  factory PyqOfficialSnapshot.of(PyqItem item) {
    return PyqOfficialSnapshot(
      question: item.question,
      answer: item.answer,
      options: List<String>.from(item.options),
      correctIndex: item.correctIndex,
    );
  }

  bool matches(PyqItem item) {
    if (item.question != question || item.answer != answer) return false;
    if (item.correctIndex != correctIndex) return false;
    if (item.options.length != options.length) return false;
    for (var i = 0; i < options.length; i++) {
      if (item.options[i] != options[i]) return false;
    }
    return true;
  }
}

double _difficultyWeight(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'hard':
    case 'difficult':
      return 3;
    case 'easy':
      return 1;
    default:
      return 2;
  }
}

String _difficultyBucket(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'hard':
    case 'difficult':
      return 'Hard';
    case 'easy':
      return 'Easy';
    default:
      return 'Medium';
  }
}

List<PyqFrequencyRow> _freq(
  Iterable<PyqItem> items,
  String Function(PyqItem) idOf,
  String Function(PyqItem) labelOf,
) {
  final counts = <String, int>{};
  final labels = <String, String>{};
  for (final item in items) {
    final id = idOf(item).trim();
    if (id.isEmpty) continue;
    counts[id] = (counts[id] ?? 0) + 1;
    labels.putIfAbsent(id, () => labelOf(item).trim().isEmpty ? id : labelOf(item).trim());
  }
  final rows = [
    for (final e in counts.entries)
      PyqFrequencyRow(id: e.key, label: labels[e.key] ?? e.key, count: e.value),
  ]..sort((a, b) => b.count.compareTo(a.count));
  return rows;
}

/// Builds PYQ analysis from the given uploaded rows. Does not call Gemini
/// and does not mutate [items].
PyqAnalysis analyzeUploadedPyqs(Iterable<PyqItem> items) {
  final approved = [
    for (final item in items)
      if (pyqIsApprovedForAnalysis(item)) item,
  ];
  final topicFrequency = _freq(
    approved,
    (p) => p.topicId.isNotEmpty ? p.topicId : p.chapterId,
    (p) => p.tags.isNotEmpty
        ? p.tags.first
        : (p.subject.isNotEmpty ? p.subject : p.title),
  );
  final chapterFrequency = _freq(
    approved,
    (p) => p.chapterId,
    (p) => p.subject.isNotEmpty ? p.subject : p.chapterId,
  );

  final conceptCounts = <String, int>{};
  for (final item in approved) {
    final tokens = ragKeywordTokens(
      '${item.question} ${item.tags.join(' ')} ${item.title}',
      limit: 16,
    );
    for (final t in tokens) {
      if (t.length < 4) continue;
      conceptCounts[t] = (conceptCounts[t] ?? 0) + 1;
    }
  }
  final repeatedConcepts = [
    for (final e in conceptCounts.entries)
      if (e.value >= 2) PyqConceptRow(concept: e.key, count: e.value),
  ]..sort((a, b) => b.count.compareTo(a.count));

  final importantAreas = [
    ...topicFrequency.take(5),
    ...chapterFrequency.take(3),
  ];
  final seen = <String>{};
  final uniqueImportant = [
    for (final row in importantAreas)
      if (seen.add(row.id)) row,
  ];

  final difficultyDistribution = <String, int>{
    'Easy': 0,
    'Medium': 0,
    'Hard': 0,
  };
  final topicScore = <String, double>{};
  final topicCount = <String, int>{};
  final topicLabel = <String, String>{};
  for (final item in approved) {
    final bucket = _difficultyBucket(item.difficulty);
    difficultyDistribution[bucket] = (difficultyDistribution[bucket] ?? 0) + 1;
    final id = item.topicId.isNotEmpty ? item.topicId : item.chapterId;
    if (id.isEmpty) continue;
    topicScore[id] = (topicScore[id] ?? 0) + _difficultyWeight(item.difficulty);
    topicCount[id] = (topicCount[id] ?? 0) + 1;
    topicLabel.putIfAbsent(
      id,
      () => item.tags.isNotEmpty ? item.tags.first : (item.subject.isNotEmpty ? item.subject : id),
    );
  }

  final preparationPriority = [
    for (final e in topicScore.entries)
      PyqPriorityRow(
        id: e.key,
        label: topicLabel[e.key] ?? e.key,
        score: e.value,
        pyqCount: topicCount[e.key] ?? 0,
      ),
  ]..sort((a, b) => b.score.compareTo(a.score));

  return PyqAnalysis(
    analyzedCount: approved.length,
    topicFrequency: topicFrequency,
    chapterFrequency: chapterFrequency,
    repeatedConcepts: repeatedConcepts.take(12).toList(growable: false),
    importantAreas: uniqueImportant.take(8).toList(growable: false),
    difficultyDistribution: difficultyDistribution,
    preparationPriority: preparationPriority.take(8).toList(growable: false),
  );
}
