import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/classroom_theme.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/classroom_motion.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/classroom_svg_art.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subtitle_timing.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Data-driven AI Lesson Studio scene engine.
///
/// Renders whatever [GeneratedSlide.visualType] + payload Gemini returned —
/// no subject-specific hardcoded layouts. Animation progress is driven by
/// [revealCount] so voice narration stays synchronized with visuals.
class SceneEngine extends StatelessWidget {
  const SceneEngine({
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

  /// 0–1 karaoke progress through the current narration beat.
  final double speechProgress;

  /// Whether audio narration is actively playing.
  final bool isSpeaking;

  /// Keywords emphasized by the current teaching beat (karaoke sync).
  final List<String> narratedKeywords;

  /// Exact keyword currently spoken — chip zooms when matched.
  final String activeKeyword;

  @override
  Widget build(BuildContext context) {
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (slide.keywords.isNotEmpty) ...[
          _KeywordHighlights(
            keywords: slide.keywords,
            revealCount: revealCount,
            dense: dense,
            speechProgress: speechProgress,
            isSpeaking: isSpeaking,
            narratedKeywords: narratedKeywords.isNotEmpty
                ? narratedKeywords
                : slide.keywords,
            activeKeyword: activeKeyword,
          ),
          SizedBox(height: dense ? 10 : 14),
        ],
        AnimatedScale(
          scale: zoom ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          child: AnimatedSlide(
            offset: zoom ? const Offset(0, -0.012) : Offset.zero,
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            child: _dispatch(),
          ),
        ),
        if (slide.handwriting.isNotEmpty) ...[
          SizedBox(height: dense ? 10 : 14),
          _HandwritingLayer(
            lines: slide.handwriting,
            revealCount: revealCount,
            dense: dense,
          ),
        ],
      ],
    );

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              child,
              if (slide.pointerPath.isNotEmpty)
                IgnorePointer(
                  child: _PointerOverlay(
                    slide: slide,
                    revealCount: revealCount,
                    isSpeaking: isSpeaking,
                    speechProgress: speechProgress,
                    boardWidth: constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : 320,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _dispatch() {
    // Prefer explicit visualType from Gemini; fall back by payload richness.
    final type = slide.resolvedVisualType;
    switch (type) {
      case SlideVisualType.whiteboard:
        return _WhiteboardScene(slide: slide, revealCount: revealCount, dense: dense);
      case SlideVisualType.flowchart:
        return _FlowchartScene(slide: slide, revealCount: revealCount, dense: dense);
      case SlideVisualType.mindmap:
        return _MindMapScene(slide: slide, revealCount: revealCount, dense: dense);
      case SlideVisualType.timeline:
        return _TimelineScene(slide: slide, revealCount: revealCount, dense: dense);
      case SlideVisualType.map:
        return _MapScene(slide: slide, revealCount: revealCount, dense: dense);
      case SlideVisualType.table:
        return _TableScene(slide: slide, revealCount: revealCount, dense: dense);
      case SlideVisualType.graph:
        return _GraphScene(slide: slide, revealCount: revealCount, dense: dense);
      case SlideVisualType.icons:
        return _IconsScene(slide: slide, revealCount: revealCount, dense: dense);
      case SlideVisualType.image:
        return _ImageScene(slide: slide, dense: dense);
      case SlideVisualType.bullets:
        return _BulletsScene(
          slide: slide,
          revealCount: revealCount,
          dense: dense,
          activeBulletIndex: activeBulletIndex,
          speechProgress: speechProgress,
          isSpeaking: isSpeaking,
        );
    }
  }
}

/// How many animation steps this scene has (for narration sync).
int sceneAnimationSteps(GeneratedSlide slide) => slide.animationSteps;

// ─── Shared chrome ───────────────────────────────────────────────────────────

class _KeywordHighlights extends StatelessWidget {
  const _KeywordHighlights({
    required this.keywords,
    required this.revealCount,
    required this.dense,
    this.speechProgress = 0,
    this.isSpeaking = false,
    this.narratedKeywords = const [],
    this.activeKeyword = '',
  });

  final List<String> keywords;
  final int revealCount;
  final bool dense;
  final double speechProgress;
  final bool isSpeaking;
  final List<String> narratedKeywords;
  final String activeKeyword;

  bool _isSpokenNow(int i) {
    if (!isSpeaking || keywords.isEmpty) return false;
    final kw = keywords[i].trim().toLowerCase();
    final spoken = activeKeyword.trim().toLowerCase();
    if (spoken.isNotEmpty && (kw.contains(spoken) || spoken.contains(kw))) {
      return true;
    }
    final hot = (speechProgress.clamp(0.0, 0.999) * keywords.length).floor();
    if (i == hot) return true;
    for (final n in narratedKeywords) {
      final t = n.trim().toLowerCase();
      if (t.isEmpty) continue;
      if (kw.contains(t) || t.contains(kw)) return i == hot;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < keywords.length; i++)
          Builder(
            builder: (context) {
              final revealed = i < revealCount || revealCount >= keywords.length;
              final hot = _isSpokenNow(i);
              return ClassroomReveal(
                visible: revealed || hot,
                highlight: hot && isSpeaking,
                delayMs: i * 40,
                child: AnimatedScale(
                  scale: hot && isSpeaking ? 1.14 : 1.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    padding: EdgeInsets.symmetric(
                      horizontal: dense ? 8 : 10,
                      vertical: dense ? 4 : 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.orangeLight.withValues(
                        alpha: hot ? 0.55 : (revealed ? 0.26 : 0.1),
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: hot ? AppColors.orangeLight : ClassroomTheme.sky.withValues(alpha: 0.28),
                        width: hot ? 2 : 1,
                      ),
                      boxShadow: hot && isSpeaking
                          ? [
                              BoxShadow(
                                color: AppColors.orangeLight.withValues(alpha: 0.45),
                                blurRadius: 14,
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      keywords[i],
                      style: TextStyle(
                        color: ClassroomTheme.navy,
                        fontSize: dense ? 11 : 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _HandwritingLayer extends StatelessWidget {
  const _HandwritingLayer({
    required this.lines,
    required this.revealCount,
    required this.dense,
  });

  final List<String> lines;
  final int revealCount;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          ClassroomReveal(
            visible: i < revealCount,
            highlight: i == revealCount - 1,
            delayMs: i * 50,
            slideFrom: const Offset(0.02, 0.08),
            child: Padding(
              padding: EdgeInsets.only(bottom: dense ? 6 : 8),
              child: _BoardWriteLine(
                text: lines[i],
                active: i == revealCount - 1,
                dense: dense,
              ),
            ),
          ),
      ],
    );
  }
}

/// Chalk-style board writing — words paint in left-to-right.
class _BoardWriteLine extends StatelessWidget {
  const _BoardWriteLine({
    required this.text,
    required this.active,
    required this.dense,
  });

  final String text;
  final bool active;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final words =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return TweenAnimationBuilder<double>(
      key: ValueKey('write_${text.hashCode}_$active'),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: active ? 900 : 520),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        final show = words.isEmpty
            ? 0
            : (t * words.length).ceil().clamp(0, words.length);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.edit_rounded,
              size: dense ? 14 : 16,
              color: const Color(0xFFFFE8A3).withValues(alpha: 0.85),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Wrap(
                spacing: 4,
                runSpacing: 2,
                children: [
                  for (var i = 0; i < words.length; i++)
                    Opacity(
                      opacity: i < show ? 1 : 0.12,
                      child: Text(
                        words[i],
                        style: TextStyle(
                          color: const Color(0xFFFFE8A3),
                          fontSize: dense ? 13 : 15,
                          fontStyle: FontStyle.italic,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Segoe Print',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PointerOverlay extends StatefulWidget {
  const _PointerOverlay({
    required this.slide,
    required this.revealCount,
    this.isSpeaking = false,
    this.speechProgress = 0,
    this.boardWidth = 320,
  });

  final GeneratedSlide slide;
  final int revealCount;
  final bool isSpeaking;
  final double speechProgress;
  final double boardWidth;

  @override
  State<_PointerOverlay> createState() => _PointerOverlayState();
}

class _PointerOverlayState extends State<_PointerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isSpeaking || widget.revealCount >= 1) {
      _bob.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _PointerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final want = widget.isSpeaking || widget.revealCount >= 1;
    if (want && !_bob.isAnimating) {
      _bob.repeat(reverse: true);
    } else if (!want && _bob.isAnimating) {
      _bob
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  int get _pathIndex {
    final path = widget.slide.pointerPath;
    if (path.isEmpty) return 0;
    if (widget.isSpeaking) {
      return (widget.speechProgress.clamp(0.0, 0.999) * path.length)
          .floor()
          .clamp(0, path.length - 1);
    }
    return (widget.revealCount - 1).clamp(0, path.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slide.pointerPath.isEmpty || widget.revealCount < 1) {
      return const SizedBox.shrink();
    }
    final idx = _pathIndex;
    final t = widget.isSpeaking
        ? widget.speechProgress.clamp(0.0, 1.0)
        : idx / widget.slide.pointerPath.length;
    return AnimatedBuilder(
      animation: _bob,
      builder: (context, child) {
        final bob = 6 * (_bob.value - 0.5);
        return Positioned(
          left: 12 + (widget.boardWidth * 0.55) * t,
          top: 8 + 28 * t + bob,
          child: child!,
        );
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.8, end: 1),
        duration: const Duration(milliseconds: 420),
        key: ValueKey('ptr_$idx'),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Column(
          children: [
            Icon(
              Icons.near_me_rounded,
              color: AppColors.orangeLight,
              size: 28,
              shadows: [
                Shadow(
                  color: AppColors.orangeLight.withValues(alpha: 0.55),
                  blurRadius: 12,
                ),
              ],
            ),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.orangeLight.withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                widget.slide.pointerPath[idx],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Word-by-word karaoke text driven by [speechProgress] (0–1).
class WordByWordText extends StatelessWidget {
  const WordByWordText({
    super.key,
    required this.text,
    required this.speechProgress,
    this.style,
    this.activeStyle,
    this.cues = const [],
    this.isSpeaking = false,
  });

  final String text;
  final double speechProgress;
  final TextStyle? style;
  final TextStyle? activeStyle;
  final List<SubtitleCue> cues;
  final bool isSpeaking;

  @override
  Widget build(BuildContext context) {
    final words = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const SizedBox.shrink();
    final base = style ??
        TextStyle(
          color: Colors.white.withValues(alpha: 0.92),
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w500,
        );
    final hot = activeStyle ??
        base.copyWith(
          color: AppColors.orangeLight,
          fontWeight: FontWeight.w800,
        );
    final revealed = isSpeaking
        ? revealedWordCount(
            progress: speechProgress,
            text: text,
            cues: cues,
          )
        : words.length;
    final active = isSpeaking
        ? activeSubtitleIndex(
            progress: speechProgress,
            cues: cues,
            fallbackText: text,
          )
        : -1;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < words.length; i++)
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: i < revealed ? 1 : 0.22,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 160),
              style: i == active ? hot : base,
              child: Text(words[i]),
            ),
          ),
      ],
    );
  }
}

// ─── Scene renderers (payload-driven) ────────────────────────────────────────

class _BulletsScene extends StatelessWidget {
  const _BulletsScene({
    required this.slide,
    required this.revealCount,
    required this.dense,
    this.activeBulletIndex,
    this.speechProgress = 0,
    this.isSpeaking = false,
  });

  final GeneratedSlide slide;
  final int revealCount;
  final bool dense;
  final int? activeBulletIndex;
  final double speechProgress;
  final bool isSpeaking;

  @override
  Widget build(BuildContext context) {
    final bullets = slide.bullets;
    if (bullets.isEmpty) {
      return Text('…', style: TextStyle(color: ClassroomTheme.navyMid.withValues(alpha: 0.7)));
    }
    return Column(
      children: [
        for (var i = 0; i < bullets.length; i++)
          ClassroomReveal(
            visible: i < revealCount,
            highlight: activeBulletIndex == i || i == revealCount - 1,
            delayMs: i * 35,
            child: Padding(
              padding: EdgeInsets.only(bottom: dense ? 8 : 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(
                  horizontal: dense ? 8 : 10,
                  vertical: dense ? 6 : 8,
                ),
                decoration: BoxDecoration(
                  color: (activeBulletIndex == i || i == revealCount - 1)
                      ? AppColors.orangeLight.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (activeBulletIndex == i || i == revealCount - 1)
                        ? AppColors.orangeLight.withValues(alpha: 0.65)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        width: (activeBulletIndex == i) ? 9 : 7,
                        height: (activeBulletIndex == i) ? 9 : 7,
                        decoration: BoxDecoration(
                          color: i < revealCount ? AppColors.orangeLight : ClassroomTheme.sky.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                          boxShadow: activeBulletIndex == i
                              ? [
                                  BoxShadow(
                                    color: AppColors.orangeLight.withValues(alpha: 0.55),
                                    blurRadius: 10,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: (activeBulletIndex == i || i == revealCount - 1)
                          ? WordByWordText(
                              text: bullets[i],
                              speechProgress: speechProgress,
                              isSpeaking: isSpeaking &&
                                  (activeBulletIndex == i ||
                                      i == revealCount - 1),
                              cues: slide.resolvedSubtitleTiming(bullets[i]),
                              style: TextStyle(
                                color: ClassroomTheme.navy,
                                fontSize: dense
                                    ? 13
                                    : (activeBulletIndex == i ? 15.5 : 14),
                                height: 1.45,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          : Text(
                              bullets[i],
                              style: TextStyle(
                                color: ClassroomTheme.navy,
                                fontSize: dense ? 13 : 14,
                                height: 1.45,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WhiteboardScene extends StatelessWidget {
  const _WhiteboardScene({required this.slide, required this.revealCount, required this.dense});

  final GeneratedSlide slide;
  final int revealCount;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final steps = slide.drawSteps.isNotEmpty
        ? slide.drawSteps
        : slide.bullets
            .asMap()
            .entries
            .map(
              (e) => DrawStep(
                kind: e.key == 0 ? 'box' : 'text',
                label: e.value,
                x: 0.1,
                y: 0.15 + e.key * 0.18,
              ),
            )
            .toList();

    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF4F1E8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                // Faint ruled lines.
                CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _BoardLinesPainter(),
                ),
                for (var i = 0; i < steps.length; i++)
                  if (i < revealCount)
                    _BoardStroke(
                      step: steps[i],
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      highlight: i == revealCount - 1,
                      dense: dense,
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BoardStroke extends StatelessWidget {
  const _BoardStroke({
    required this.step,
    required this.width,
    required this.height,
    required this.highlight,
    required this.dense,
  });

  final DrawStep step;
  final double width;
  final double height;
  final bool highlight;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final left = (step.x.clamp(0.0, 0.85)) * width;
    final top = (step.y.clamp(0.0, 0.85)) * height;
    final ink = highlight ? const Color(0xFF1A4B8C) : const Color(0xFF243B55);

    Widget body;
    switch (step.kind) {
      case 'circle':
        body = Container(
          width: dense ? 64 : 80,
          height: dense ? 64 : 80,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ink, width: 2),
          ),
          child: Text(
            step.label,
            textAlign: TextAlign.center,
            style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: dense ? 11 : 12),
          ),
        );
      case 'arrow':
        body = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(step.label, style: TextStyle(color: ink, fontWeight: FontWeight.w600, fontSize: dense ? 12 : 13)),
            Icon(Icons.arrow_forward_rounded, color: ink, size: dense ? 16 : 18),
          ],
        );
      case 'box':
        body = Container(
          padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 6 : 8),
          decoration: BoxDecoration(
            border: Border.all(color: ink, width: 1.6),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white.withValues(alpha: 0.35),
          ),
          child: Text(
            step.label,
            style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: dense ? 12 : 13),
          ),
        );
      default:
        body = Text(
          step.label,
          style: TextStyle(
            color: ink,
            fontWeight: FontWeight.w600,
            fontSize: dense ? 13 : 14.5,
            fontFamily: 'Segoe Print',
            height: 1.3,
          ),
        );
    }

    return Positioned(
      left: left,
      top: top,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 450),
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
        ),
        child: body,
      ),
    );
  }
}

class _BoardLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A4B8C).withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (double y = 28; y < size.height; y += 22) {
      canvas.drawLine(Offset(12, y), Offset(size.width - 12, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FlowchartScene extends StatelessWidget {
  const _FlowchartScene({required this.slide, required this.revealCount, required this.dense});

  final GeneratedSlide slide;
  final int revealCount;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final items = slide.flowchart.isNotEmpty
        ? slide.flowchart
        : slide.bullets
            .asMap()
            .entries
            .map(
              (e) => FlowNode(
                id: '${e.key}',
                label: e.value,
                nextIds: e.key < slide.bullets.length - 1 ? ['${e.key + 1}'] : const [],
              ),
            )
            .toList();

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          ClassroomReveal(
            visible: i < revealCount,
            highlight: i == revealCount - 1,
            delayMs: i * 45,
            child: KeywordGlow(
              active: i == revealCount - 1,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: dense ? 12 : 14,
                  vertical: dense ? 10 : 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: i == revealCount - 1 ? 0.16 : 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: i == revealCount - 1 ? AppColors.orangeLight : Colors.white24,
                    width: i == revealCount - 1 ? 1.8 : 1,
                  ),
                ),
                child: Text(
                  items[i].label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: dense ? 13 : 14,
                  ),
                ),
              ),
            ),
          ),
          if (i != items.length - 1)
            SizedBox(
              height: dense ? 22 : 28,
              child: TweenAnimationBuilder<double>(
                key: ValueKey('flow_edge_${i}_$revealCount'),
                tween: Tween(begin: 0, end: i < revealCount - 1 ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, p, _) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: Size(dense ? 18 : 22, dense ? 22 : 28),
                        painter: PathDrawPainter(
                          progress: p,
                          color: p > 0.5 ? AppColors.orangeLight : Colors.white38,
                        ),
                      ),
                      Opacity(
                        opacity: p,
                        child: ClassroomSvgArt.flowchartChevron(
                          size: dense ? 18 : 22,
                          color: AppColors.orangeLight,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ],
    );
  }
}

class _MindMapScene extends StatelessWidget {
  const _MindMapScene({required this.slide, required this.revealCount, required this.dense});

  final GeneratedSlide slide;
  final int revealCount;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final center = slide.mindMap?.center.isNotEmpty == true
        ? slide.mindMap!.center
        : slide.title;
    final branches = slide.mindMap?.branches.isNotEmpty == true
        ? slide.mindMap!.branches
        : slide.bullets.map((b) => MindMapBranch(label: b)).toList();

    return Column(
      children: [
        ClassroomReveal(
          visible: revealCount >= 1,
          highlight: revealCount == 1,
          child: KeywordGlow(
            active: revealCount == 1,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: dense ? 14 : 18,
                vertical: dense ? 10 : 12,
              ),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.orangeLight),
              ),
              child: Text(
                center,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: dense ? 14 : 16,
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: dense ? 12 : 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < branches.length; i++)
              ClassroomReveal(
                visible: i < revealCount - 1 ||
                    revealCount > branches.length ||
                    (revealCount > 1 && i < revealCount),
                highlight: i == revealCount - 2 ||
                    (revealCount > 1 && i == revealCount - 1),
                delayMs: i * 55,
                child: KeywordGlow(
                  active: i == revealCount - 2 ||
                      (revealCount > 1 && i == revealCount - 1),
                  child: Container(
                    width: dense ? 130 : 150,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (i == revealCount - 2 || i == revealCount - 1)
                            ? AppColors.orangeLight
                            : Colors.white24,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          branches[i].label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: dense ? 12 : 13,
                          ),
                        ),
                        if (branches[i].children.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          ...branches[i].children.take(3).map(
                                (c) => Text(
                                  '• $c',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: dense ? 10.5 : 11.5,
                                  ),
                                ),
                              ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TimelineScene extends StatelessWidget {
  const _TimelineScene({required this.slide, required this.revealCount, required this.dense});

  final GeneratedSlide slide;
  final int revealCount;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final items = slide.timeline.isNotEmpty
        ? slide.timeline
        : slide.bullets
            .asMap()
            .entries
            .map((e) => TimelineEvent(year: '${e.key + 1}', label: e.value))
            .toList();

    // Left-to-right progressive timeline (smart-board style).
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              ClassroomReveal(
                visible: i < revealCount,
                highlight: i == revealCount - 1,
                delayMs: i * 60,
                slideFrom: const Offset(0.08, 0),
                child: SizedBox(
                  width: dense ? 132 : 156,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          KeywordGlow(
                            active: i == revealCount - 1,
                            child: ClassroomSvgArt.timelineDot(
                              size: dense ? 12 : 14,
                              active: i == revealCount - 1,
                            ),
                          ),
                          if (i != items.length - 1)
                            Expanded(
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey('tl_h_$i$revealCount'),
                                tween: Tween(
                                  begin: 0,
                                  end: i < revealCount - 1 ? 1.0 : 0.0,
                                ),
                                duration: const Duration(milliseconds: 480),
                                curve: Curves.easeOutCubic,
                                builder: (context, p, _) {
                                  return Container(
                                    height: 2,
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: p.clamp(0.0, 1.0),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: AppColors.orangeLight
                                              .withValues(alpha: 0.9),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.orange.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          items[i].year,
                          style: TextStyle(
                            color: AppColors.orangeLight,
                            fontWeight: FontWeight.w800,
                            fontSize: dense ? 11 : 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        items[i].label,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: dense ? 12.5 : 13.5,
                          height: 1.35,
                          fontWeight: i == revealCount - 1
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (i != items.length - 1) SizedBox(width: dense ? 6 : 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _MapScene extends StatelessWidget {
  const _MapScene({required this.slide, required this.revealCount, required this.dense});

  final GeneratedSlide slide;
  final int revealCount;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final regions = slide.mapRegions.isNotEmpty ? slide.mapRegions : slide.bullets;
    final activeIdx = revealCount >= 1
        ? (revealCount - 1).clamp(0, regions.isEmpty ? 0 : regions.length - 1)
        : -1;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(dense ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          MapLocationPulse(
            active: revealCount >= 1,
            child: ClassroomSvgArt.mapPin(size: dense ? 32 : 40),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < regions.length; i++)
                ClassroomReveal(
                  visible: i < revealCount,
                  highlight: i == activeIdx,
                  delayMs: i * 50,
                  child: MapLocationPulse(
                    active: i == activeIdx,
                    child: Chip(
                      backgroundColor: i == activeIdx
                          ? AppColors.orange.withValues(alpha: 0.45)
                          : Colors.white.withValues(alpha: 0.12),
                      side: BorderSide(
                        color: i == activeIdx
                            ? AppColors.orangeLight
                            : Colors.transparent,
                        width: i == activeIdx ? 1.6 : 0,
                      ),
                      label: Text(
                        regions[i],
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: dense ? 11 : 12,
                          fontWeight: i == activeIdx
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TableScene extends StatelessWidget {
  const _TableScene({required this.slide, required this.revealCount, required this.dense});

  final GeneratedSlide slide;
  final int revealCount;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final headers = slide.tableHeaders;
    final rows = slide.tableRows;
    if (headers.isEmpty && rows.isEmpty) {
      return _BulletsScene(slide: slide, revealCount: revealCount, dense: dense);
    }
    final cols = headers.isNotEmpty
        ? headers.length
        : (rows.isNotEmpty ? rows.first.length : 1);

    return Column(
      children: [
        if (headers.isNotEmpty)
          ClassroomReveal(
            visible: true,
            highlight: false,
            child: Table(
              border: TableBorder.all(color: Colors.white24, width: 1),
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  children: [
                    for (final h in headers)
                      Padding(
                        padding: EdgeInsets.all(dense ? 6 : 8),
                        child: Text(
                          h,
                          style: TextStyle(
                            color: AppColors.orangeLight,
                            fontWeight: FontWeight.w800,
                            fontSize: dense ? 11 : 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        for (var r = 0; r < rows.length; r++)
          ClassroomReveal(
            visible: r < revealCount,
            highlight: r == revealCount - 1,
            delayMs: r * 55,
            slideFrom: const Offset(0, 0.12),
            child: KeywordGlow(
              active: r == revealCount - 1,
              child: Table(
                border: TableBorder.all(color: Colors.white24, width: 1),
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: r == revealCount - 1
                          ? AppColors.orangeLight.withValues(alpha: 0.22)
                          : Colors.white.withValues(alpha: 0.04),
                    ),
                    children: [
                      for (var c = 0; c < cols; c++)
                        Padding(
                          padding: EdgeInsets.all(dense ? 6 : 8),
                          child: Text(
                            c < rows[r].length ? rows[r][c] : '',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: dense ? 11.5 : 12.5,
                              fontWeight: r == revealCount - 1
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _GraphScene extends StatelessWidget {
  const _GraphScene({required this.slide, required this.revealCount, required this.dense});

  final GeneratedSlide slide;
  final int revealCount;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final labels = slide.graph?.labels.isNotEmpty == true
        ? slide.graph!.labels
        : slide.bullets;
    final values = slide.graph?.values.isNotEmpty == true
        ? slide.graph!.values
        : List<double>.generate(labels.length, (i) => (i + 1) * 10.0);
    final maxV = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: dense ? 140 : 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < labels.length && i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ClassroomReveal(
                  visible: i < revealCount,
                  highlight: i == revealCount - 1,
                  delayMs: i * 40,
                  slideFrom: const Offset(0, 0.15),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        values[i].toStringAsFixed(values[i] % 1 == 0 ? 0 : 1),
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: dense ? 9 : 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      KeywordGlow(
                        active: i == revealCount - 1,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 450),
                          height: i < revealCount
                              ? ((values[i] / maxV).clamp(0.08, 1.0) * (dense ? 90 : 120))
                              : 8,
                          decoration: BoxDecoration(
                            color: i == revealCount - 1
                                ? AppColors.orangeLight
                                : AppColors.orange.withValues(alpha: 0.55),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        labels[i],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: dense ? 9.5 : 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IconsScene extends StatelessWidget {
  const _IconsScene({required this.slide, required this.revealCount, required this.dense});

  final GeneratedSlide slide;
  final int revealCount;
  final bool dense;

  static const _icons = [
    Icons.auto_stories_rounded,
    Icons.account_balance_rounded,
    Icons.public_rounded,
    Icons.science_rounded,
    Icons.history_edu_rounded,
    Icons.payments_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final labels = slide.iconLabels.isNotEmpty ? slide.iconLabels : slide.bullets;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < labels.length; i++)
          TweenAnimationBuilder<double>(
            key: ValueKey('icon_${i}_$revealCount'),
            tween: Tween(begin: 0.0, end: i < revealCount ? 1.0 : 0.0),
            duration: Duration(milliseconds: 320 + (i * 40).clamp(0, 200)),
            curve: Curves.easeOutBack,
            builder: (context, t, child) => Opacity(
              opacity: i < revealCount ? t.clamp(0.0, 1.0) : 0.22,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - t)),
                child: Transform.scale(
                  scale: 0.86 + 0.14 * t,
                  child: child,
                ),
              ),
            ),
            child: Container(
              width: dense ? 96 : 110,
              padding: EdgeInsets.all(dense ? 10 : 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: i == revealCount - 1 ? AppColors.orangeLight : Colors.white24,
                ),
                boxShadow: i == revealCount - 1
                    ? [
                        BoxShadow(
                          color: AppColors.orangeLight.withValues(alpha: 0.35),
                          blurRadius: 14,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                children: [
                  Icon(_icons[i % _icons.length], color: AppColors.orangeLight, size: dense ? 22 : 26),
                  const SizedBox(height: 8),
                  Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: dense ? 11 : 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ImageScene extends StatelessWidget {
  const _ImageScene({required this.slide, required this.dense});

  final GeneratedSlide slide;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (slide.imageUrl.trim().isEmpty) {
      return _BulletsScene(slide: slide, revealCount: 999, dense: dense);
    }
    return ClassroomReveal(
      visible: true,
      highlight: true,
      slideFrom: const Offset(0, 0.05),
      duration: const Duration(milliseconds: 520),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Image.network(
            slide.imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, error, stackTrace) => Container(
              color: Colors.white.withValues(alpha: 0.08),
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined, color: Colors.white54),
            ),
          ),
        ),
      ),
    );
  }
}
