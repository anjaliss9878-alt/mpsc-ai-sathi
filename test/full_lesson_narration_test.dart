import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/full_lesson_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/teaching_sequence.dart';
import 'package:mpsc_combine_ai/services/elevenlabs_tts_service.dart';

void main() {
  final service = FullLessonNarrationService();

  test('lecture script joins beats with single spaces and no stacked ellipses', () {
    final script = service.buildLectureScript(
      beats: const [
        TeachingBeat(
          kind: TeachingBeatKind.concept,
          slideIndex: 0,
          speakText: 'पहिली वाक्य।',
        ),
        TeachingBeat(
          kind: TeachingBeatKind.example,
          slideIndex: 0,
          speakText: 'दुसरी वाक्य।',
        ),
      ],
    );
    expect(script, 'पहिली वाक्य। दुसरी वाक्य।');
    expect(script.contains('......'), isFalse);
    expect(script.contains('……'), isFalse);
    expect(RegExp(r'\s{2,}').hasMatch(script), isFalse);
  });

  test('beat spans cover 0..duration with no gaps', () {
    const total = Duration(seconds: 40);
    final spans = beatSpansFor(
      texts: const ['aaa', 'bbbbbb', 'cc'],
      total: total,
      slideIndices: const [0, 2, 4],
    );
    expect(spans, hasLength(3));
    expect(spans.first.start, Duration.zero);
    expect(spans.last.end, total);
    expect(spans[0].slideIndex, 0);
    expect(spans[1].slideIndex, 2);
    expect(spans[2].slideIndex, 4);
    for (var i = 0; i < spans.length - 1; i++) {
      expect(spans[i].end, spans[i + 1].start);
      expect(spans[i].end >= spans[i].start, isTrue);
    }
  });

  test('slideIndexForAudioSpan never treats span index as beat index', () {
    expect(
      slideIndexForAudioSpan(
        spanSlideIndex: 4,
        spanIndex: 0,
        spanCount: 3,
        slideCount: 5,
      ),
      4,
    );
    expect(
      slideIndexForAudioSpan(
        spanSlideIndex: 99,
        spanIndex: 1,
        spanCount: 4,
        slideCount: 5,
      ),
      1,
    );
  });

  test('withDuration preserves slide mapping', () {
    final bundle = LessonAudioBundle(
      bytes: Uint8List(8),
      mimeType: 'audio/wav',
      duration: const Duration(seconds: 10),
      script: 'a b',
      spans: beatSpansFor(
        texts: const ['aaaa', 'bbbb'],
        total: const Duration(seconds: 10),
        slideIndices: const [1, 3],
      ),
    );
    final scaled = bundle.withDuration(const Duration(seconds: 20));
    expect(scaled.spans.map((s) => s.slideIndex).toList(), [1, 3]);
    expect(scaled.spans.last.end, const Duration(seconds: 20));
  });

  test('alignment spans map each beat from character timings', () {
    final spans = beatSpansFromAlignment(
      texts: const ['ab', 'cd'],
      script: 'ab cd',
      characters: const ['a', 'b', ' ', 'c', 'd'],
      starts: const [0.0, 0.1, 0.2, 0.3, 0.4],
      ends: const [0.1, 0.2, 0.3, 0.4, 0.5],
      total: const Duration(milliseconds: 500),
    );
    expect(spans, hasLength(2));
    expect(spans.first.start, Duration.zero);
    expect(spans.last.end, const Duration(milliseconds: 500));
    expect(spans[0].end <= spans[1].start || spans[0].end == spans[1].start, isTrue);
  });

  test('synthesize posts one ElevenLabs request with the subject voice', () async {
    String? postedPath;
    String? postedBody;
    final client = MockClient((request) async {
      postedPath = request.url.path;
      postedBody = request.body;
      final audio = base64Encode(Uint8List(900));
      return http.Response(
        jsonEncode({
          'audio_base64': audio,
          'alignment': {
            'characters': ['न', 'म'],
            'character_start_times_seconds': [0.0, 0.2],
            'character_end_times_seconds': [0.2, 0.8],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final eleven = ElevenLabsTtsService(client: client, apiKey: 'test-key');
    final tts = FullLessonNarrationService(elevenLabs: eleven);
    final bundle = await tts.synthesize(
      scriptLines: const ['नमस्कार. आज राज्यघटना शिकूया.'],
      subject: MpscTeachingSubject.polity,
      topic: 'राज्यघटना',
    );

    expect(postedPath, contains(MpscTeachingSubject.polity.elevenLabsVoiceId));
    expect(postedPath, contains('/with-timestamps'));
    expect(postedBody, isNotNull);
    expect(postedBody, contains('नमस्कार'));
    expect(bundle.bytes.length, greaterThanOrEqualTo(800));
    expect(bundle.mimeType, 'audio/mpeg');
    expect(bundle.spans, isNotEmpty);
  });

  test('missing ElevenLabs key fails before any network call', () async {
    final tts = FullLessonNarrationService(
      elevenLabs: ElevenLabsTtsService(apiKey: ''),
    );
    expect(
      () => tts.synthesize(
        scriptLines: const ['नमस्कार'],
        subject: MpscTeachingSubject.history,
      ),
      throwsA(isA<ElevenLabsTtsException>()),
    );
  });
}
