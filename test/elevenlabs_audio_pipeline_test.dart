import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/elevenlabs_tts_service.dart';
import 'package:mpsc_combine_ai/utils/student_copy.dart';

void main() {
  tearDown(ElevenLabsTtsService.clearMemoryCache);

  test('empty script fails before any network call', () async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return http.Response('nope', 500);
    });
    final tts = ElevenLabsTtsService(client: client, apiKey: 'test-key');
    expect(
      () => tts.synthesizeLesson(text: '  ', subject: MpscTeachingSubject.polity),
      throwsA(
        isA<ElevenLabsTtsException>().having((e) => e.statusCode, 'status', 400),
      ),
    );
    expect(called, isFalse);
  });

  test('invalid ElevenLabs key captures HTTP 401 and does not invent audio', () async {
    final client = MockClient((request) async {
      return http.Response('{"detail":{"status":"invalid_api_key"}}', 401);
    });
    final tts = ElevenLabsTtsService(client: client, apiKey: 'bad-key');
    try {
      await tts.synthesizeLesson(
        text: ElevenLabsTtsService.shortMarathiTestScript,
        subject: MpscTeachingSubject.polity,
      );
      fail('should throw');
    } on ElevenLabsTtsException catch (e) {
      expect(e.statusCode, 401);
      expect(e.message.contains('HTTP 401'), isTrue);
      expect(e.message.toLowerCase().contains('sk_'), isFalse);
    }
  });

  test('rate limit captures HTTP 429', () async {
    final client = MockClient((request) async {
      return http.Response('rate limited', 429);
    });
    final tts = ElevenLabsTtsService(client: client, apiKey: 'test-key');
    expect(
      () => tts.synthesizeLesson(
        text: ElevenLabsTtsService.shortMarathiTestScript,
        subject: MpscTeachingSubject.polity,
      ),
      throwsA(
        isA<ElevenLabsTtsException>().having((e) => e.statusCode, 'status', 429),
      ),
    );
  });

  test('successful TTS returns real audio bytes and is cached', () async {
    var posts = 0;
    final client = MockClient((request) async {
      posts += 1;
      return http.Response(
        jsonEncode({
          'audio_base64': base64Encode(Uint8List(1200)),
          'alignment': {
            'characters': ['न'],
            'character_start_times_seconds': [0.0],
            'character_end_times_seconds': [1.2],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final tts = ElevenLabsTtsService(client: client, apiKey: 'test-key');
    final first = await tts.synthesizeLesson(
      text: ElevenLabsTtsService.shortMarathiTestScript,
      subject: MpscTeachingSubject.polity,
    );
    final second = await tts.synthesizeLesson(
      text: ElevenLabsTtsService.shortMarathiTestScript,
      subject: MpscTeachingSubject.polity,
    );
    expect(first.bytes.length, greaterThanOrEqualTo(800));
    expect(second.bytes.length, first.bytes.length);
    expect(posts, 1);
  });

  test('cache key includes script voice and model', () {
    final a = ElevenLabsTtsService.cacheKey(
      text: 'abc',
      voiceId: 'v1',
      modelId: 'm1',
    );
    final b = ElevenLabsTtsService.cacheKey(
      text: 'abc',
      voiceId: 'v2',
      modelId: 'm1',
    );
    expect(a, isNot(b));
  });

  test('audio failure copy is the required Marathi sentence', () {
    expect(
      kAudioUnavailable,
      'AI Teacher चा आवाज तयार करता आला नाही. कृपया पुन्हा प्रयत्न करा.',
    );
  });
}
