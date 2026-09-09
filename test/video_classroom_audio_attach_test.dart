import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/ai_lesson_studio.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/full_lesson_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_classroom_engine.dart';
import 'package:mpsc_combine_ai/services/lesson_audio_player.dart';

class _AttachAudioPlayer extends LessonAudioPlayer {
  _AttachAudioPlayer({required this.ready});

  final bool ready;

  @override
  bool get hasContinuousSource => ready;

  @override
  Future<Duration> preloadContinuous(
    Uint8List bytes, {
    String mimeType = 'audio/wav',
  }) async => ready ? const Duration(seconds: 2) : Duration.zero;

  @override
  Future<void> dispose() async {}
}

LessonAudioBundle _bundle() => LessonAudioBundle(
  bytes: Uint8List.fromList(List<int>.filled(512, 1)),
  mimeType: 'audio/wav',
  duration: const Duration(seconds: 2),
  script: 'नमस्कार',
  spans: const [
    BeatAudioSpan(
      beatIndex: 0,
      text: 'नमस्कार',
      start: Duration.zero,
      end: Duration(seconds: 2),
    ),
  ],
);

void main() {
  test('classroom rejects audio that could not become playable', () async {
    final engine = VideoClassroomEngine(
      audio: _AttachAudioPlayer(ready: false),
    );
    await expectLater(
      engine.attachContinuousAudio(_bundle()),
      throwsA(isA<StateError>()),
    );
    expect(engine.hasContinuousAudio, isFalse);
    engine.dispose();
  });

  test('classroom accepts a playable continuous audio source', () async {
    final engine = VideoClassroomEngine(audio: _AttachAudioPlayer(ready: true));
    await engine.attachContinuousAudio(_bundle());
    expect(engine.hasContinuousAudio, isTrue);
    engine.dispose();
  });

  testWidgets('failed voice exposes a voice-only retry action', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiLessonStudio(
            lesson: welcomeLesson,
            audioFailed: true,
            onRetryAudio: () => retries++,
          ),
        ),
      ),
    );
    expect(find.text('Retry Voice'), findsOneWidget);
    await tester.tap(find.text('Retry Voice'));
    expect(retries, 1);
  });
}
