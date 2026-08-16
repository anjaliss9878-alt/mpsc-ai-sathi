import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/google_cloud_tts_service.dart';
import 'package:mpsc_combine_ai/services/lesson_audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Google Cloud TTS voice defaults to Marathi WaveNet female', () {
    final tts = GoogleCloudTtsService();
    final voice = tts.voiceFor('भारतीय राज्यघटना');
    expect(voice.languageCode, 'mr-IN');
    expect(voice.voiceName, 'mr-IN-Wavenet-A');
    expect(GoogleCloudTtsService.defaultSpeakingRate, closeTo(0.9, 0.001));
  });

  test('401 / 403 / quota errors are classified as free-TTS fallback', () {
    expect(GoogleCloudTtsService.isFallbackStatus(401), isTrue);
    expect(GoogleCloudTtsService.isFallbackStatus(403), isTrue);
    expect(GoogleCloudTtsService.isFallbackStatus(404), isTrue);
    expect(GoogleCloudTtsService.isFallbackStatus(200), isFalse);
    expect(GoogleCloudTtsService.isRetryableStatus(429), isTrue);
    expect(GoogleCloudTtsService.isRetryableStatus(503), isTrue);
    expect(GoogleCloudTtsService.isRetryableStatus(400), isFalse);
    expect(
      GoogleCloudTtsService.isFallbackException(
        const GoogleCloudTtsException(
          message: 'authentication failed',
          statusCode: 403,
          body: 'PERMISSION_DENIED',
        ),
      ),
      isTrue,
    );
  });

  test('chunkForApi splits long lessons at sentence boundaries', () {
    final long = List.generate(80, (i) => 'वाक्य $i आहे.').join(' ');
    final chunks = GoogleCloudTtsService.chunkForApi(long, maxChars: 120);
    expect(chunks.length, greaterThan(1));
    expect(chunks.every((c) => c.trim().isNotEmpty), isTrue);
    expect(chunks.every((c) => c.length <= 200), isTrue);
  });

  test('toTeachingSsml wraps Marathi with gentle prosody', () {
    final ssml = GoogleCloudTtsService.toTeachingSsml('नमस्कार. हा धडा आहे।');
    expect(ssml.contains('<speak>'), isTrue);
    expect(ssml.contains('<prosody'), isTrue);
    expect(ssml.contains('नमस्कार'), isTrue);
    expect(ssml.contains('&lt;'), isFalse);
  });

  test('LessonAudioPlayer speakAndWait never throws without Cloud TTS',
      () async {
    final player = LessonAudioPlayer();
    // Without dart-defines credentials in unit tests, Cloud TTS is skipped.
    // speakAndWait must not throw even when the platform TTS engine is a stub.
    await player.speakAndWait('नमस्कार. हा एक चाचणी आहे.');
    expect(player.state, anyOf(LessonAudioState.idle, LessonAudioState.error));

    await player.stop();
    expect(player.state, LessonAudioState.idle);
    expect(player.isPlaying, isFalse);

    await player.dispose();
  });

  test('Stop / Pause guards remain safe with free backend', () async {
    final player = LessonAudioPlayer();
    final gen = player.speakGeneration;
    await player.pause();
    await player.resume();
    await player.stop();
    expect(player.speakGeneration, greaterThan(gen));
    expect(player.isLoading, isFalse);
    await player.dispose();
  });
}
