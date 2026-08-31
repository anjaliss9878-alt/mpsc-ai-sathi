import 'dart:math' as math;

/// Cosine similarity in [0, 1] after clamping negatives to 0.
/// Returns 0 when either vector is empty or dimension-mismatched.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.isEmpty || b.isEmpty || a.length != b.length) return 0;
  var dot = 0.0;
  var na = 0.0;
  var nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    dot += x * y;
    na += x * x;
    nb += y * y;
  }
  if (na <= 0 || nb <= 0) return 0;
  final sim = dot / (math.sqrt(na) * math.sqrt(nb));
  if (sim.isNaN) return 0;
  return sim < 0 ? 0 : (sim > 1 ? 1 : sim);
}

/// Reciprocal-rank fusion of two ranked id lists.
Map<String, double> reciprocalRankFusion(
  List<String> vectorRanks,
  List<String> keywordRanks, {
  int k = 60,
}) {
  final scores = <String, double>{};
  void add(List<String> ranks, double weight) {
    for (var i = 0; i < ranks.length; i++) {
      final id = ranks[i];
      scores[id] = (scores[id] ?? 0) + weight / (k + i + 1);
    }
  }

  add(vectorRanks, 1);
  add(keywordRanks, 1);
  return scores;
}

/// Keyword overlap in [0, 1] using query tokens vs chunk search text.
double keywordScore(List<String> queryTokens, String haystack) {
  if (queryTokens.isEmpty) return 0;
  final h = haystack.toLowerCase();
  if (h.isEmpty) return 0;
  var hits = 0;
  for (final t in queryTokens) {
    if (t.length < 2) continue;
    if (h.contains(t)) hits++;
  }
  final usable = queryTokens.where((t) => t.length >= 2).length;
  if (usable == 0) return 0;
  return hits / usable;
}
