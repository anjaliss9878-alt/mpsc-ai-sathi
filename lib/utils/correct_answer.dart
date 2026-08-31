/// Parses a spreadsheet / form "Correct Answer" into a 0-based option index.
///
/// Accepts `A`–`D`, 1-based `1`–`4`, legacy 0-based `correctIndex`, or the
/// option text itself. Returns `null` when the value cannot be resolved.
int? parseCorrectAnswer(String raw, List<String> options) {
  final t = raw.trim();
  if (t.isEmpty || options.isEmpty) return null;

  final letter = t.toUpperCase();
  if (letter.length == 1) {
    final code = letter.codeUnitAt(0);
    if (code >= 65 && code <= 68) {
      final i = code - 65;
      return i < options.length ? i : null;
    }
  }

  final n = int.tryParse(t);
  if (n != null) {
    if (n >= 1 && n <= options.length) return n - 1;
    if (n >= 0 && n < options.length) return n;
  }

  final needle = t.toLowerCase();
  for (var i = 0; i < options.length; i++) {
    if (options[i].trim().toLowerCase() == needle) return i;
  }
  return null;
}

String correctAnswerLetter(int index) {
  if (index < 0 || index > 3) return '';
  return String.fromCharCode(65 + index);
}
