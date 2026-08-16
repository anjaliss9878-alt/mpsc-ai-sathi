/// Word / phrase cues for karaoke-style subtitle sync.
///
/// Times are normalized 0.0–1.0 across the current spoken beat so the same
/// cues work for any clip duration and playback speed.
class SubtitleCue {
  const SubtitleCue({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;

  /// Inclusive start in [0, 1].
  final double start;

  /// Exclusive end in [0, 1].
  final double end;

  bool contains(double progress) {
    final p = progress.clamp(0.0, 1.0);
    return p >= start && p < end;
  }

  factory SubtitleCue.fromMap(Map<String, dynamic> map) {
    final start = (map['start'] as num?)?.toDouble() ?? 0;
    final end = (map['end'] as num?)?.toDouble() ?? 1;
    return SubtitleCue(
      text: (map['text'] as String?) ?? '',
      start: start.clamp(0.0, 1.0),
      end: end.clamp(0.0, 1.0),
    );
  }

  Map<String, dynamic> toMap() => {
        'text': text,
        'start': start,
        'end': end,
      };
}

/// Builds evenly spaced cues from [text] when Gemini omitted timings.
List<SubtitleCue> buildSubtitleTimingFromText(String text) {
  final words = text
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return const [];
  final n = words.length;
  return List<SubtitleCue>.generate(n, (i) {
    final start = i / n;
    final end = (i + 1) / n;
    return SubtitleCue(text: words[i], start: start, end: end);
  });
}

/// Active word index for [progress] against [cues] (or synthetic from [fallbackText]).
int activeSubtitleIndex({
  required double progress,
  List<SubtitleCue> cues = const [],
  String fallbackText = '',
}) {
  final list = cues.isNotEmpty
      ? cues
      : buildSubtitleTimingFromText(fallbackText);
  if (list.isEmpty) return 0;
  final p = progress.clamp(0.0, 0.999);
  for (var i = 0; i < list.length; i++) {
    if (list[i].contains(p)) return i;
  }
  return (p * list.length).floor().clamp(0, list.length - 1);
}

/// How many words to reveal for word-by-word board animation.
int revealedWordCount({
  required double progress,
  required String text,
  List<SubtitleCue> cues = const [],
}) {
  final list = cues.isNotEmpty
      ? cues
      : buildSubtitleTimingFromText(text);
  if (list.isEmpty) return 0;
  return activeSubtitleIndex(
        progress: progress,
        cues: list,
      ) +
      1;
}
