import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/scene_engine/scene_engine.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';

/// Back-compat wrapper — Teaching Board / Player / Fullscreen all render
/// through the data-driven [SceneEngine].
class SlideVisualContent extends StatelessWidget {
  const SlideVisualContent({
    super.key,
    required this.slide,
    this.revealCount = 999,
    this.zoom = false,
    this.dense = false,
    this.activeBulletIndex,
    this.speechProgress = 0,
    this.isSpeaking = false,
    this.narratedKeywords = const [],
    this.activeKeyword = '',
  });

  final GeneratedSlide slide;
  final int revealCount;
  final bool zoom;
  final bool dense;
  final int? activeBulletIndex;
  final double speechProgress;
  final bool isSpeaking;
  final List<String> narratedKeywords;
  final String activeKeyword;

  @override
  Widget build(BuildContext context) {
    return SceneEngine(
      slide: slide,
      revealCount: revealCount,
      zoom: zoom,
      dense: dense,
      activeBulletIndex: activeBulletIndex,
      speechProgress: speechProgress,
      isSpeaking: isSpeaking,
      narratedKeywords: narratedKeywords,
      activeKeyword: activeKeyword,
    );
  }
}
