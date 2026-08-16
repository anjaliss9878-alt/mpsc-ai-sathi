import 'package:flutter/foundation.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/faculty_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/speakable_marathi.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/teaching_sequence.dart';
import 'package:mpsc_combine_ai/services/elevenlabs_tts_service.dart';

/// One continuous lesson narration plus slide/beat timeline.
class LessonAudioBundle {
  const LessonAudioBundle({
    required this.bytes,
    required this.mimeType,
    required this.duration,
    required this.script,
    required this.spans,
  });

  final Uint8List bytes;
  final String mimeType;
  final Duration duration;
  final String script;
  final List<BeatAudioSpan> spans;

  LessonAudioBundle withDuration(Duration actual) {
    if (actual <= Duration.zero) return this;
    final spans = beatSpansFor(
      texts: this.spans.map((s) => s.text).toList(),
      total: actual,
    );
    return LessonAudioBundle(
      bytes: bytes,
      mimeType: mimeType,
      duration: actual,
      script: script,
      spans: spans,
    );
  }
}

class BeatAudioSpan {
  const BeatAudioSpan({
    required this.beatIndex,
    required this.text,
    required this.start,
    required this.end,
  });

  final int beatIndex;
  final String text;
  final Duration start;
  final Duration end;
}

/// Full-lesson Marathi TTS via ElevenLabs — one continuous file, never
/// sentence-by-sentence Google/Gemini clips.
class FullLessonNarrationService {
  FullLessonNarrationService({ElevenLabsTtsService? elevenLabs})
      : _eleven = elevenLabs ?? elevenLabsTtsService;

  final ElevenLabsTtsService _eleven;

  String buildLectureScript({
    List<TeachingBeat> beats = const [],
    List<String> scriptLines = const [],
  }) {
    final parts = <String>[];
    if (beats.isNotEmpty) {
      for (final beat in beats) {
        final t = facultyNarration(beat.speakText);
        if (t.isNotEmpty) parts.add(t);
      }
    }
    if (parts.isEmpty) {
      for (final line in scriptLines) {
        final t = facultyNarration(line);
        if (t.isNotEmpty) parts.add(t);
      }
    }
    return speakableMarathi(parts.join(' '));
  }

  List<String> beatTexts(List<TeachingBeat> beats) {
    return [
      for (final beat in beats) facultyNarration(beat.speakText),
    ];
  }

  Future<LessonAudioBundle> synthesize({
    List<TeachingBeat> beats = const [],
    List<String> scriptLines = const [],
    MpscTeachingSubject? subject,
    String? topic,
  }) async {
    final texts = beats.isNotEmpty
        ? beatTexts(beats)
        : [
            for (final line in scriptLines) facultyNarration(line),
          ].where((s) => s.trim().isNotEmpty).toList();
    final script = speakableMarathi(
      texts.where((s) => s.trim().isNotEmpty).join(' '),
    );
    if (script.trim().isEmpty) {
      throw const ElevenLabsTtsException('Empty lesson script');
    }

    final style = subject ??
        detectMpscTeachingSubject(topic ?? script, hint: topic);

    debugPrint(
      '[FullLessonTTS] ElevenLabs subject=${style.id} chars=${script.length}',
    );

    final clip = await _eleven.synthesizeLesson(
      text: script,
      subject: style,
    );

    final spans = clip.hasAlignment
        ? beatSpansFromAlignment(
            texts: texts,
            script: script,
            characters: clip.characters,
            starts: clip.charStartSeconds,
            ends: clip.charEndSeconds,
            total: clip.duration,
          )
        : beatSpansFor(texts: texts, total: clip.duration);

    return LessonAudioBundle(
      bytes: clip.bytes,
      mimeType: clip.mimeType,
      duration: clip.duration,
      script: script,
      spans: spans,
    );
  }
}

List<BeatAudioSpan> beatSpansFor({
  required List<String> texts,
  required Duration total,
}) {
  final weights = [
    for (final t in texts) t.trim().isEmpty ? 0 : t.trim().length,
  ];
  final sum = weights.fold<int>(0, (a, b) => a + b);
  if (sum <= 0 || total <= Duration.zero) {
    return [
      for (var i = 0; i < texts.length; i++)
        BeatAudioSpan(
          beatIndex: i,
          text: texts[i],
          start: Duration.zero,
          end: total,
        ),
    ];
  }
  final spans = <BeatAudioSpan>[];
  var cursor = 0.0;
  final ms = total.inMilliseconds.toDouble();
  for (var i = 0; i < texts.length; i++) {
    final start = Duration(milliseconds: cursor.round());
    cursor += ms * (weights[i] / sum);
    var end = Duration(milliseconds: cursor.round());
    if (i == texts.length - 1) end = total;
    if (end < start) end = start;
    spans.add(
      BeatAudioSpan(
        beatIndex: i,
        text: texts[i],
        start: start,
        end: end,
      ),
    );
  }
  return spans;
}

List<BeatAudioSpan> beatSpansFromAlignment({
  required List<String> texts,
  required String script,
  required List<String> characters,
  required List<double> starts,
  required List<double> ends,
  required Duration total,
}) {
  if (characters.isEmpty || characters.length != starts.length) {
    return beatSpansFor(texts: texts, total: total);
  }
  final aligned = characters.join();
  var searchFrom = 0;
  final spans = <BeatAudioSpan>[];
  for (var i = 0; i < texts.length; i++) {
    final piece = texts[i].trim();
    var startIdx = aligned.indexOf(piece, searchFrom);
    if (startIdx < 0) {
      startIdx = script.indexOf(piece, searchFrom);
    }
    if (startIdx < 0) startIdx = searchFrom;
    final endIdx = (startIdx + (piece.isEmpty ? 1 : piece.length) - 1)
        .clamp(0, characters.length - 1);
    final safeStart = startIdx.clamp(0, characters.length - 1);
    searchFrom = (endIdx + 1).clamp(0, aligned.length);

    final startMs = (starts[safeStart] * 1000).round();
    final endMs = (ends[endIdx] * 1000).round();
    var start = Duration(milliseconds: startMs.clamp(0, total.inMilliseconds));
    var end = Duration(milliseconds: endMs.clamp(0, total.inMilliseconds));
    if (end < start) end = start;
    if (i == texts.length - 1) end = total;
    spans.add(
      BeatAudioSpan(
        beatIndex: i,
        text: texts[i],
        start: start,
        end: end,
      ),
    );
  }
  if (spans.isNotEmpty) {
    spans[0] = BeatAudioSpan(
      beatIndex: 0,
      text: spans[0].text,
      start: Duration.zero,
      end: spans[0].end,
    );
  }
  return spans;
}

final FullLessonNarrationService fullLessonNarrationService =
    FullLessonNarrationService();
