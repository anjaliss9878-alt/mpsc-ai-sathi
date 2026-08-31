import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/ai_lesson_player.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/classroom_avatar.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_classroom_engine.dart';

/// Fullscreen classroom lecture using the existing [VideoClassroomEngine].
///
/// Does not create a second engine or [LessonAudioPlayer].
class AiTeacherLecturePage extends StatelessWidget {
  const AiTeacherLecturePage({
    super.key,
    required this.engine,
  });

  final VideoClassroomEngine engine;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: engine,
            builder: (context, _) {
              return AiLessonPlayer(
                slides: engine.lesson.slides,
                slideIndex: engine.slideIndex,
                revealCount: engine.revealCount,
                state: engine.isPlaying
                    ? TeacherAvatarState.speaking
                    : TeacherAvatarState.idle,
                isPlaying: engine.isPlaying,
                progress: engine.progress,
                subtitle: engine.caption,
                subtitleHighlight: engine.speechProgress,
                keywords: engine.currentKeywords,
                activeBulletIndex: engine.activeBulletIndex,
                speed: engine.playbackSpeed,
                muted: engine.muted,
                onPlayPause: engine.togglePlayPause,
                onReplay: engine.replay,
                onStop: () {
                  engine.stop();
                  Navigator.of(context).maybePop();
                },
                onSpeedChanged: (s) {
                  unawaited(engine.setSpeed(s));
                },
                onMuteChanged: (m) {
                  unawaited(engine.setMuted(m));
                },
                onSeek: engine.seekFraction,
                onNext: engine.next,
                onPrevious: engine.previous,
                onSkipBack: () => engine.skipSeconds(-10),
                onSkipForward: () => engine.skipSeconds(10),
                zoom: engine.zoomPulse,
                topicName: engine.lesson.topicName,
                activeKeyword: engine.activeKeyword,
                memoryTrickText: engine.premiumSpotlightText,
                showMemoryTrick: engine.showMemoryTrick,
                conceptTransition: engine.conceptTransition,
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
