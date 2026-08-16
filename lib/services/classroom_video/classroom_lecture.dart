import 'package:mpsc_combine_ai/services/ai_teacher_system/speakable_marathi.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// One teaching slide in the classroom video pipeline.
class ClassroomSlide {
  const ClassroomSlide({
    required this.heading,
    required this.points,
    required this.spoken,
  });

  final String heading;
  final List<String> points;
  final String spoken;

  factory ClassroomSlide.fromMap(Map<String, dynamic> map) {
    final spoken = speakableMarathi(
      (map['spoken'] as String?) ??
          (map['narration'] as String?) ??
          '',
    );
    final heading = cleanBoardText(
      (map['heading'] as String?) ?? (map['title'] as String?) ?? '',
    );
    final points = asStringList(map['points'] ?? map['bullets'])
        .map(cleanBoardText)
        .where((s) => s.isNotEmpty)
        .take(5)
        .toList();
    return ClassroomSlide(
      heading: heading,
      points: points,
      spoken: spoken,
    );
  }
}

/// Topic-grounded Marathi lecture: one narration + 8–12 slides.
class ClassroomLecture {
  const ClassroomLecture({
    required this.title,
    required this.narration,
    required this.slides,
  });

  final String title;
  final String narration;
  final List<ClassroomSlide> slides;

  factory ClassroomLecture.fromMap(Map<String, dynamic> map) {
    var slides = asMapList(map['slides']).map(ClassroomSlide.fromMap).toList();
    slides = slides
        .where((s) => s.heading.isNotEmpty || s.spoken.isNotEmpty)
        .toList();
    if (slides.length > 12) {
      slides = slides.sublist(0, 12);
    }

    final fromSlides = speakableMarathi(
      slides.map((s) => s.spoken).where((s) => s.isNotEmpty).join(' '),
    );
    final top = speakableMarathi((map['narration'] as String?) ?? '');
    final narration = fromSlides.isNotEmpty ? fromSlides : top;
    final title = cleanBoardText(
      (map['title'] as String?) ?? (map['topic'] as String?) ?? '',
    );

    return ClassroomLecture(
      title: title,
      narration: narration,
      slides: slides,
    );
  }

  /// Character-weighted slide durations that sum to [total].
  List<Duration> slideDurations(Duration total) {
    if (slides.isEmpty) return const [];
    final weights = [
      for (final s in slides)
        s.spoken.trim().isEmpty ? s.heading.length.clamp(1, 80) : s.spoken.length,
    ];
    final sum = weights.fold<int>(0, (a, b) => a + b);
    final ms = total.inMilliseconds < 1000 ? 1000 : total.inMilliseconds;
    if (sum <= 0) {
      final each = (ms / slides.length).floor();
      return [for (var i = 0; i < slides.length; i++) Duration(milliseconds: each)];
    }
    final out = <Duration>[];
    var used = 0;
    for (var i = 0; i < slides.length; i++) {
      if (i == slides.length - 1) {
        out.add(Duration(milliseconds: (ms - used).clamp(400, ms)));
        break;
      }
      final part = ((ms * weights[i]) / sum).round().clamp(400, ms);
      used += part;
      out.add(Duration(milliseconds: part));
    }
    return out;
  }
}

String stripJsonFences(String text) {
  var result = text.trim();
  if (result.startsWith('```')) {
    result = result.substring(3);
    final langBreak = result.indexOf('\n');
    if (langBreak != -1 && langBreak < 12) {
      result = result.substring(langBreak + 1);
    }
  }
  if (result.endsWith('```')) {
    result = result.substring(0, result.length - 3);
  }
  final start = result.indexOf('{');
  final end = result.lastIndexOf('}');
  if (start >= 0 && end > start) {
    result = result.substring(start, end + 1);
  }
  return result.trim();
}
