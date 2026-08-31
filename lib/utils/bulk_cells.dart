/// Lower-cases keys and strips spaces / punctuation so CSV headers like
/// "Target Group" and "Option A" match `targetgroup` / `optiona`.
Map<String, String> normalizeBulkCells(Map<String, String> cells) {
  final out = <String, String>{};
  for (final e in cells.entries) {
    final key = e.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (key.isEmpty) continue;
    out[key] = e.value;
  }
  return out;
}

String bulkCell(Map<String, String> cells, String key) {
  return (cells[key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')] ?? '')
      .trim();
}
