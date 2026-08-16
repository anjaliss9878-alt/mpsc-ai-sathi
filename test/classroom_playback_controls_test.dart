import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/ai_lesson_player.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/classroom_avatar.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/faculty_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/lesson_audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LessonAudioPlayer stop resets playing/loading state and bumps session',
      () async {
    final player = LessonAudioPlayer();
    final genBefore = player.speakGeneration;

    await player.stop();

    expect(player.speakGeneration, greaterThan(genBefore));
    expect(player.state, LessonAudioState.idle);
    expect(player.isPlaying, isFalse);
    expect(player.isLoading, isFalse);
    expect(player.isPaused, isFalse);

    final genAfterStop = player.speakGeneration;
    await player.stop(emitIdle: true);
    expect(player.speakGeneration, greaterThan(genAfterStop));
    expect(player.state, LessonAudioState.idle);
    expect(player.isLoading, isFalse);

    await player.dispose();
    // Safe double-dispose.
    await player.dispose();
  });

  test('Stop clears loading without double-invalidating the next speak session',
      () async {
    final player = LessonAudioPlayer();

    // Simulate a loading-like sticky state by stopping mid-flight then playing
    // a new session — speakAndWait must claim a fresh generation after halt.
    final genAtStop = player.speakGeneration;
    await player.stop(emitIdle: false);
    expect(player.speakGeneration, greaterThan(genAtStop));
    expect(player.isLoading, isFalse);
    expect(player.isPlaying, isFalse);
    // emitIdle: false lands on stopped, never loading.
    expect(
      player.state == LessonAudioState.stopped ||
          player.state == LessonAudioState.idle,
      isTrue,
    );

    final genBeforeSpeak = player.speakGeneration;
    // Empty text is a no-op and must not leave loading stuck.
    await player.speakAndWait('   ');
    expect(player.isLoading, isFalse);
    expect(player.speakGeneration, genBeforeSpeak);

    await player.stop();
    expect(player.state, LessonAudioState.idle);
    expect(player.isLoading, isFalse);
    expect(player.isPlaying, isFalse);

    await player.dispose();
  });

  test('Play → Stop → Play session tokens stay coherent', () async {
    final player = LessonAudioPlayer();

    final g0 = player.speakGeneration;
    // "Play" path: stop prior session without consuming the next speak token.
    await player.stop(emitIdle: false);
    expect(player.speakGeneration, greaterThan(g0));
    expect(player.isLoading, isFalse);

    final afterPlayPrep = player.speakGeneration;
    await player.stop(); // user hits Stop
    expect(player.speakGeneration, greaterThan(afterPlayPrep));
    expect(player.state, LessonAudioState.idle);
    expect(player.isPlaying, isFalse);
    expect(player.isLoading, isFalse);

    final afterStop = player.speakGeneration;
    await player.stop(emitIdle: false); // second Play prep
    expect(player.speakGeneration, greaterThan(afterStop));
    expect(player.isLoading, isFalse);

    await player.dispose();
  });

  test('Pause → Resume toggles paused/playing flags without stuck loading',
      () async {
    final player = LessonAudioPlayer();

    await player.pause();
    expect(player.isPaused, isTrue);
    expect(player.isLoading, isFalse);
    expect(player.isPlaying, isFalse);

    await player.resume();
    // No active backend clip — resume clears soft-pause; state may stay paused
    // or move on; never loading.
    expect(player.isLoading, isFalse);

    await player.stop();
    expect(player.state, LessonAudioState.idle);
    expect(player.isPaused, isFalse);
    expect(player.isLoading, isFalse);

    await player.dispose();
  });

  test('setSpeed updates player speed for subsequent narration', () async {
    final player = LessonAudioPlayer();
    await player.setSpeed(1.25);
    expect(player.speed, 1.25);
    await player.setSpeed(0.75);
    expect(player.speed, 0.75);
    await player.setSpeed(0.9);
    expect(player.speed, closeTo(0.9, 0.001));
    // Clamp range
    await player.setSpeed(3.0);
    expect(player.speed, 1.5);
    await player.setSpeed(0.1);
    expect(player.speed, 0.5);
    await player.dispose();
  });

  test('waitWhileSessionActive cancels when stop bumps generation', () async {
    final player = LessonAudioPlayer();
    final started = DateTime.now();
    final wait = player.waitWhileSessionActive(const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await player.stop();
    await wait;
    final elapsed = DateTime.now().difference(started);
    expect(elapsed.inMilliseconds, lessThan(1500));
    expect(kTeachingParagraphPause.inMilliseconds, greaterThan(500));
    await player.dispose();
  });

  testWidgets('Stop stays tappable while isPlaying', (tester) async {
    var stopCount = 0;
    var playPauseCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AiLessonPlayer(
              slides: welcomeLesson.slides,
              slideIndex: 0,
              revealCount: 2,
              state: TeacherAvatarState.speaking,
              isPlaying: true,
              progress: 0.25,
              subtitle: 'Test narration line for karaoke overlay',
              subtitleHighlight: 0.4,
              speed: 0.9,
              muted: false,
              onPlayPause: () => playPauseCount++,
              onReplay: () {},
              onStop: () => stopCount++,
              onSpeedChanged: (_) {},
              onMuteChanged: (_) {},
              topicName: 'Playback Guard',
            ),
          ),
        ),
      ),
    );
    // Avatar / scene layers use repeating AnimationControllers — do not
    // pumpAndSettle (never reaches idle). A few frames is enough to layout.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
    expect(stopCount, 1);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(playPauseCount, 1);
  });

  testWidgets('Next / Previous / Replay / Speed controls are tappable',
      (tester) async {
    var nextCount = 0;
    var prevCount = 0;
    var replayCount = 0;
    var speed = 0.9;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AiLessonPlayer(
              slides: welcomeLesson.slides,
              slideIndex: 1,
              revealCount: 1,
              state: TeacherAvatarState.idle,
              isPlaying: false,
              progress: 0.1,
              subtitle: 'Controls smoke',
              speed: speed,
              muted: false,
              onPlayPause: () {},
              onReplay: () => replayCount++,
              onStop: () {},
              onNext: () => nextCount++,
              onPrevious: () => prevCount++,
              onSpeedChanged: (s) => speed = s,
              onMuteChanged: (_) {},
              onSeek: (_) {},
              topicName: 'Controls',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Next'));
    await tester.pump();
    expect(nextCount, 1);

    await tester.tap(find.byTooltip('Previous'));
    await tester.pump();
    expect(prevCount, 1);

    await tester.tap(find.byTooltip('Replay'));
    await tester.pump();
    expect(replayCount, 1);

    await tester.tap(find.text('0.9x'));
    await tester.pump();
    expect(speed, 1.0);
  });

  testWidgets('Fullscreen control is present and tappable', (tester) async {
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
              speed: 1.0,
              muted: false,
              onPlayPause: () {},
              onReplay: () {},
              onStop: () {},
              onSpeedChanged: (_) {},
              onMuteChanged: (_) {},
              topicName: 'FS',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byTooltip('Fullscreen'), findsOneWidget);
    await tester.tap(find.byTooltip('Fullscreen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Embedded clone shows exit control.
    expect(find.byTooltip('Exit fullscreen'), findsOneWidget);
  });

  testWidgets('Empty slides never white-screen — fallback canvas renders',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AiLessonPlayer(
              slides: const [],
              slideIndex: 0,
              revealCount: 0,
              state: TeacherAvatarState.idle,
              isPlaying: false,
              progress: 0,
              subtitle: null,
              speed: 0.9,
              muted: false,
              onPlayPause: () {},
              onReplay: () {},
              onStop: () {},
              onSpeedChanged: (_) {},
              onMuteChanged: (_) {},
              topicName: 'Empty Lesson',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Empty Lesson'), findsWidgets);
    expect(find.byTooltip('Stop'), findsOneWidget);
    expect(find.byTooltip('Play / Resume'), findsOneWidget);
  });
}
