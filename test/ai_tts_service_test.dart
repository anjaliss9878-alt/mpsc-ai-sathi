import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mpsc_combine_ai/services/ai_backend_base.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/ai_tts_service.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/gemini_tts_synthesizer.dart';
import 'package:mpsc_combine_ai/utils/student_copy.dart';

void main() {
  tearDown(AiTtsService.clearMemoryCache);

  final sampleWav = GeminiTtsSynthesizer.ensureWav(
    Uint8List(900),
    mimeType: 'audio/L16;rate=24000',
  );

  test('synthesize posts /ai/tts with Firebase bearer token', () async {
    http.Request? seen;
    final client = MockClient((request) async {
      seen = request;
      expect(request.method, 'POST');
      expect(request.url.path, '/ai/tts');
      expect(request.url.origin, kProductionAiBackendOrigin);
      expect(request.headers['authorization'], 'Bearer test-id-token');
      expect(request.body, contains('नमस्कार'));
      expect(request.url.toString(), isNot(contains('127.0.0.1')));
      expect(request.url.toString(), isNot(contains('localhost')));
      expect(request.url.toString(), isNot(contains('elevenlabs')));
      return http.Response(
        jsonEncode({
          'audio_base64': base64Encode(sampleWav),
          'mimeType': 'audio/wav',
          'mime_type': 'audio/wav',
          'durationMs': 1200,
          'voiceId': 'Kore',
          'modelId': kGeminiTtsModel,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final tts = AiTtsService(
      client: client,
      backendBases: const [kProductionAiBackendOrigin],
      idToken: () async => 'test-id-token',
    );
    final audio = await tts.synthesizeLesson(
      text: AiTtsService.shortMarathiTestScript,
      subject: MpscTeachingSubject.polity,
    );
    expect(seen, isNotNull);
    expect(audio.bytes.length, sampleWav.length);
    expect(GeminiTtsSynthesizer.isWavContainer(audio.bytes), isTrue);
    expect(audio.mimeType, 'audio/wav');
    expect(audio.modelId, kGeminiTtsModel);
  });

  test('Gemini TTS HTTP error is returned clearly', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': 'Gemini TTS failed HTTP 502: model unavailable',
          'status': 502,
        }),
        502,
        headers: {'content-type': 'application/json'},
      );
    });
    final tts = AiTtsService(
      client: client,
      backendBases: const [kProductionAiBackendOrigin],
      idToken: () async => 'token',
    );
    expect(
      () => tts.synthesizeLesson(
        text: 'नमस्कार',
        subject: MpscTeachingSubject.geography,
      ),
      throwsA(
        isA<AiTtsException>()
            .having((e) => e.message, 'message', kVoiceFailed)
            .having((e) => e.statusCode, 'status', 502),
      ),
    );
  });

  test('long lesson is chunked and concatenated without truncation', () async {
    var calls = 0;
    final tts = AiTtsService(
      client: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'audio_base64': base64Encode(sampleWav),
            'mimeType': 'audio/wav',
            'durationMs': 1200,
            'voiceId': 'Kore',
            'modelId': kGeminiTtsModel,
          }),
          200,
        );
      }),
      backendBases: const [kProductionAiBackendOrigin],
      idToken: () async => 'token',
    );
    final text = List.filled(
      24,
      'महाराष्ट्राच्या इतिहासातील हा महत्त्वाचा मुद्दा विद्यार्थ्यांनी समजून घ्यावा.',
    ).join(' ');
    final expectedChunks = AiTtsService.chunkForBackend(text);
    expect(expectedChunks.length, greaterThan(1));
    expect(expectedChunks.join(' ').replaceAll('  ', ' '), text.trim());

    final audio = await tts.synthesizeLesson(
      text: text,
      subject: MpscTeachingSubject.history,
    );
    expect(calls, expectedChunks.length);
    expect(GeminiTtsSynthesizer.isWavContainer(audio.bytes), isTrue);
    expect(audio.bytes.length, greaterThan(sampleWav.length));
  });

  test(
    'transient TTS response is retried without regenerating lesson',
    () async {
      var calls = 0;
      final tts = AiTtsService(
        client: MockClient((request) async {
          calls++;
          if (calls == 1) {
            return http.Response(
              jsonEncode({'error': 'temporary overload', 'status': 503}),
              503,
            );
          }
          return http.Response(
            jsonEncode({
              'audio_base64': base64Encode(sampleWav),
              'mimeType': 'audio/wav',
              'durationMs': 1200,
            }),
            200,
          );
        }),
        backendBases: const [kProductionAiBackendOrigin],
        idToken: () async => 'token',
      );
      final audio = await tts.synthesizeLesson(
        text: 'तात्पुरता अडथळा आल्यानंतर आवाज पुन्हा तयार होतो.',
        subject: MpscTeachingSubject.polity,
      );
      expect(calls, 2);
      expect(audio.bytes, isNotEmpty);
    },
  );

  test(
    'empty audio_base64 fails without throwing raw provider errors',
    () async {
      final tts = AiTtsService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({'audio_base64': '', 'mimeType': 'audio/wav'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        backendBases: const [kProductionAiBackendOrigin],
        idToken: () async => 'token',
      );
      expect(
        () => tts.synthesizeLesson(
          text: 'नमस्कार',
          subject: MpscTeachingSubject.polity,
        ),
        throwsA(
          isA<AiTtsException>().having(
            (e) => e.message,
            'message',
            kVoiceFailed,
          ),
        ),
      );
    },
  );

  test('HTTP 500 is mapped to the student voice error', () async {
    final tts = AiTtsService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'AI_API_KEY missing', 'status': 500}),
          500,
          headers: {'content-type': 'application/json'},
        );
      }),
      backendBases: const [kProductionAiBackendOrigin],
      idToken: () async => 'token',
    );
    expect(
      () => tts.synthesizeLesson(
        text: 'नमस्कार',
        subject: MpscTeachingSubject.polity,
      ),
      throwsA(
        isA<AiTtsException>()
            .having((e) => e.message, 'message', kVoiceFailed)
            .having((e) => e.statusCode, 'status', 500),
      ),
    );
  });

  test('localhost TTS candidates never fall through to production', () {
    final bases = lessonBackendBaseCandidates(
      debug: true,
      isWeb: true,
      pageHost: 'localhost',
    );
    expect(bases.first, 'http://localhost:8791');
    expect(aiTtsEndpoint(bases.first), 'http://localhost:8791/ai/tts');
    for (final base in bases) {
      expect(isLoopbackAiBackend(base), isTrue);
      expect(aiTtsEndpoint(base), isNot(contains('mpscaisathi.co.in')));
    }
  });

  test('production TTS endpoint is never loopback', () {
    expect(
      aiTtsEndpoint(kProductionAiBackendOrigin),
      'https://mpscaisathi.co.in/ai/tts',
    );
    for (final base in lessonBackendBaseCandidates(debug: false, isWeb: true)) {
      expect(isLoopbackAiBackend(base), isFalse);
      expect(aiTtsEndpoint(base), isNot(contains('localhost')));
      expect(aiTtsEndpoint(base), isNot(contains('127.0.0.1')));
    }
  });

  test('active student TTS path files do not call ElevenLabs', () {
    final files = [
      'lib/services/ai_tts_service.dart',
      'lib/services/ai_teacher_system/full_lesson_narration.dart',
      'netlify/functions/ai-tts.js',
    ];
    for (final path in files) {
      final text = File(path).readAsStringSync();
      expect(text.toLowerCase(), isNot(contains('elevenlabs.io')));
      expect(text, isNot(contains('ELEVENLABS_API_KEY')));
    }
    expect(
      File('lib/services/elevenlabs_tts_service.dart').existsSync(),
      isFalse,
    );
  });
}
