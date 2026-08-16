import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/ai_lesson_player.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/classroom_avatar.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/full_lesson_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_classroom_engine.dart';

/// Fullscreen classroom lecture: slides synchronized with Marathi teacher voice.
class AiTeacherLecturePage extends StatefulWidget {
  const AiTeacherLecturePage({
    super.key,
    required this.lesson,
    required this.audio,
  });

  final GeneratedLesson lesson;
  final LessonAudioBundle audio;

  @override
  State<AiTeacherLecturePage> createState() => _AiTeacherLecturePageState();
}

class _AiTeacherLecturePageState extends State<AiTeacherLecturePage> {
  late final VideoClassroomEngine _engine;

  @override
  void initState() {
    super.initState();
    _engine = VideoClassroomEngine();
    _engine.setLesson(widget.lesson);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_start());
    });
  }

  Future<void> _start() async {
    try {
      await _engine.attachContinuousAudio(widget.audio);
    } catch (e) {
      if (mounted) {
        _engine.setCaption(
          'आवाज सध्या उपलब्ध नाही. स्लाइड्स पहा किंवा पुन्हा प्रयत्न करा.',
        );
      }
      return;
    }
    if (mounted) _engine.play();
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: _engine,
            builder: (context, _) {
              return AiLessonPlayer(
                slides: _engine.lesson.slides,
                slideIndex: _engine.slideIndex,
                revealCount: _engine.revealCount,
                state: _engine.isPlaying
                    ? TeacherAvatarState.speaking
                    : TeacherAvatarState.idle,
                isPlaying: _engine.isPlaying,
                progress: _engine.progress,
                subtitle: _engine.caption,
                subtitleHighlight: _engine.speechProgress,
                keywords: _engine.currentKeywords,
                activeBulletIndex: _engine.activeBulletIndex,
                speed: _engine.playbackSpeed,
                muted: _engine.muted,
                onPlayPause: _engine.togglePlayPause,
                onReplay: _engine.replay,
                onStop: () {
                  _engine.stop();
                  Navigator.of(context).maybePop();
                },
                onSpeedChanged: (s) {
                  unawaited(_engine.setSpeed(s));
                },
                onMuteChanged: (m) {
                  unawaited(_engine.setMuted(m));
                },
                onSeek: _engine.seekFraction,
                onNext: _engine.next,
                onPrevious: _engine.previous,
                onSkipBack: () => _engine.skipSeconds(-10),
                onSkipForward: () => _engine.skipSeconds(10),
                zoom: _engine.zoomPulse,
                topicName: _engine.lesson.topicName,
                activeKeyword: _engine.activeKeyword,
                memoryTrickText: _engine.premiumSpotlightText,
                showMemoryTrick: _engine.showMemoryTrick,
                conceptTransition: _engine.conceptTransition,
                showAvatar: false,
                embedded: true,
              );
            },
          ),
        ),
      ),
    );
  }
}
