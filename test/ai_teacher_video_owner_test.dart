import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/ai_lesson_player.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/classroom_avatar.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/full_lesson_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/classroom_video/classroom_lecture.dart';
import 'package:mpsc_combine_ai/services/classroom_video/classroom_video_client.dart';

void main() {
  test('slideSecondsFromSpans follows the shared audio timeline', () {
    const spans = [
      BeatAudioSpan(
        beatIndex: 0,
        slideIndex: 0,
        text: 'पहिली',
        start: Duration.zero,
        end: Duration(seconds: 4),
      ),
      BeatAudioSpan(
        beatIndex: 1,
        slideIndex: 0,
        text: 'दुसरी',
        start: Duration(seconds: 4),
        end: Duration(seconds: 6),
      ),
      BeatAudioSpan(
        beatIndex: 2,
        slideIndex: 1,
        text: 'तिसरी',
        start: Duration(seconds: 6),
        end: Duration(seconds: 10),
      ),
    ];
    final seconds = slideSecondsFromSpans(spans: spans, slideCount: 2);
    expect(seconds, hasLength(2));
    expect(seconds[0], closeTo(6, 0.01));
    expect(seconds[1], closeTo(4, 0.01));
  });

  test('lecture uses TTS slide holds when durationSeconds is present', () {
    const lecture = ClassroomLecture(
      title: 'चाचणी',
      narration: 'एक दोन',
      slides: [
        ClassroomSlide(
          heading: 'अ',
          points: ['अ'],
          spoken: 'लहान',
          durationSeconds: 7,
        ),
        ClassroomSlide(
          heading: 'ब',
          points: ['ब'],
          spoken: 'खूप मोठा बोललेला मजकूर येथे आहे',
          durationSeconds: 3,
        ),
      ],
    );
    final d = lecture.slideDurations(const Duration(seconds: 10));
    expect(d, hasLength(2));
    expect(d[0].inMilliseconds, greaterThan(d[1].inMilliseconds));
    expect(
      d.fold<int>(0, (a, b) => a + b.inMilliseconds),
      10000,
    );
  });

  test('slidesPayload writes durationSeconds from audio spans', () {
    final lesson = GeneratedLesson(
      question: 'मूलभूत अधिकार',
      topicName: 'मूलभूत अधिकार',
      subjectName: 'Polity',
      summary: 'सारांश',
      notes: const ['नोट'],
      script: const ['पहिली', 'दुसरी'],
      mcqs: const [],
      createdAt: DateTime.utc(2026, 1, 1),
      slides: [
        GeneratedSlide(
          title: 'पहिली',
          narration: 'पहिली स्लाइड',
          bullets: const ['अ'],
        ),
        GeneratedSlide(
          title: 'दुसरी',
          narration: 'दुसरी स्लाइड',
          bullets: const ['ब'],
        ),
      ],
    );
    final audio = LessonAudioBundle(
      bytes: Uint8List(0),
      mimeType: 'audio/mpeg',
      duration: Duration(seconds: 10),
      script: 'पहिली दुसरी',
      spans: [
        BeatAudioSpan(
          beatIndex: 0,
          slideIndex: 0,
          text: 'पहिली',
          start: Duration.zero,
          end: Duration(seconds: 6),
        ),
        BeatAudioSpan(
          beatIndex: 1,
          slideIndex: 1,
          text: 'दुसरी',
          start: Duration(seconds: 6),
          end: Duration(seconds: 10),
        ),
      ],
    );
    final payload = classroomSlidesPayload(lesson, audio: audio);
    expect(payload, hasLength(2));
    expect(payload[0]['durationSeconds'], closeTo(6, 0.01));
    expect(payload[1]['durationSeconds'], closeTo(4, 0.01));
  });

  test('isEngineRunning rejects HTML health and missing ffmpeg', () {
    expect(classroomEngineHealthOk(200, '<html>ok</html>'), isFalse);
    expect(
      classroomEngineHealthOk(
        200,
        jsonEncode({'ok': true, 'canRender': false, 'ffmpeg': false}),
      ),
      isFalse,
    );
    expect(
      classroomEngineHealthOk(
        200,
        jsonEncode({'ok': true, 'canRender': true, 'ffmpeg': true}),
      ),
      isTrue,
    );
  });

  test('startRender requires accepted JSON, not a 200 HTML page', () {
    expect(
      classroomRenderResponseAccepted(200, '<!doctype html>'),
      isFalse,
    );
    expect(
      classroomRenderResponseAccepted(202, jsonEncode({'accepted': true})),
      isTrue,
    );
    expect(
      classroomRenderResponseAccepted(200, jsonEncode({'ok': true})),
      isFalse,
    );
  });

  testWidgets('seek bar follows overall lesson progress, not caption karaoke',
      (tester) async {
    double? seekAt;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AiLessonPlayer(
              slides: welcomeLesson.slides,
              slideIndex: 0,
              revealCount: 1,
              state: TeacherAvatarState.speaking,
              isPlaying: true,
              progress: 0.8,
              subtitle: 'कराओके ओळ',
              subtitleHighlight: 0.1,
              speed: 1,
              muted: false,
              onPlayPause: () {},
              onReplay: () {},
              onStop: () {},
              onSpeedChanged: (_) {},
              onMuteChanged: (_) {},
              onSeek: (v) => seekAt = v,
              topicName: 'Timeline',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.8, 0.01));

    final box = tester.getRect(find.byType(LinearProgressIndicator));
    await tester.tapAt(Offset(box.left + box.width * 0.5, box.center.dy));
    await tester.pump();
    expect(seekAt, isNotNull);
    expect(seekAt!, closeTo(0.5, 0.12));
  });

  testWidgets('muxed-style transport still exposes Stop Replay Mute',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AiLessonPlayer(
              slides: welcomeLesson.slides,
              slideIndex: 0,
              revealCount: 1,
              state: TeacherAvatarState.idle,
              isPlaying: false,
              progress: 0,
              subtitle: null,
              speed: 1,
              muted: false,
              onPlayPause: () {},
              onReplay: () {},
              onStop: () {},
              onSpeedChanged: (_) {},
              onMuteChanged: (_) {},
              topicName: 'Muxed chrome',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Stop'), findsOneWidget);
    expect(find.byTooltip('Replay'), findsOneWidget);
    expect(find.byTooltip('Volume'), findsOneWidget);
    expect(find.byTooltip('Play / Resume'), findsOneWidget);
  });
}
