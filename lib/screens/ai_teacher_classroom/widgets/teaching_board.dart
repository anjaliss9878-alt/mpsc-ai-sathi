import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/classroom_theme.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/fullscreen_slide_view.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/slide_visuals.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Small badge shown on a slide when it has a [SlideHighlightType] other
/// than [SlideHighlightType.none].
class SlideHighlightBadge extends StatelessWidget {
  const SlideHighlightBadge({super.key, required this.slide, this.dense = false});

  final GeneratedSlide slide;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (slide.highlightType == SlideHighlightType.none) return const SizedBox.shrink();
    final (icon, label) = switch (slide.highlightType) {
      SlideHighlightType.diagram => (Icons.account_tree_rounded, 'Diagram'),
      SlideHighlightType.map => (Icons.map_rounded, 'Map'),
      SlideHighlightType.timeline => (Icons.timeline_rounded, 'Timeline'),
      SlideHighlightType.none => (Icons.circle, ''),
    };
    final text = slide.highlightLabel.trim().isNotEmpty ? slide.highlightLabel : label;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 4 : 6),
      decoration: BoxDecoration(
        color: AppColors.orangeLight.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orangeLight.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dense ? 13 : 15, color: AppColors.orangeLight),
          SizedBox(width: dense ? 4 : 6),
          Text(
            text,
            style: TextStyle(
              color: AppColors.orangeLight,
              fontSize: dense ? 10.5 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The large "teaching board" — layout unchanged; slide body now renders
/// animated educational graphics synchronized with narration via [revealCount].
class TeachingBoard extends StatelessWidget {
  const TeachingBoard({
    super.key,
    required this.slides,
    required this.index,
    required this.onIndexChanged,
    this.revealCount = 999,
    this.zoom = false,
    this.activeBulletIndex,
    this.speechProgress = 0,
    this.isSpeaking = false,
    this.narratedKeywords = const [],
    this.activeKeyword = '',
  });

  final List<GeneratedSlide> slides;
  final int index;
  final ValueChanged<int> onIndexChanged;
  final int revealCount;
  final bool zoom;
  final int? activeBulletIndex;
  final double speechProgress;
  final bool isSpeaking;
  final List<String> narratedKeywords;
  final String activeKeyword;

  Future<void> _openFullscreen(BuildContext context) async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FullscreenSlideView(
          slides: slides,
          initialIndex: index,
          revealCount: revealCount,
        ),
      ),
    );
    if (result != null) onIndexChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    if (slides.isEmpty) {
      return const Card(
        child: SizedBox(
          height: 260,
          child: Center(child: Text('No slides yet')),
        ),
      );
    }
    final safeIndex = index.clamp(0, slides.length - 1);
    final slide = slides[safeIndex];
    return Container(
      decoration: ClassroomTheme.glassCard(),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dashboard_customize_rounded, color: ClassroomTheme.navy, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Teaching Board',
                  style: ClassroomTheme.display(context).copyWith(fontSize: 15),
                ),
                const Spacer(),
                Text(
                  '${safeIndex + 1} / ${slides.length}',
                  style: const TextStyle(color: ClassroomTheme.navyMid, fontSize: 12.5),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _openFullscreen(context),
                  tooltip: 'Full-screen slide mode',
                  icon: const Icon(Icons.fullscreen_rounded, color: ClassroomTheme.navy),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 480),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: Container(
                key: ValueKey('${safeIndex}_${revealCount}_$activeBulletIndex'),
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 280),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: ClassroomTheme.softCard,
                  borderRadius: ClassroomTheme.radiusLg,
                  border: Border.all(color: ClassroomTheme.sky.withValues(alpha: 0.22)),
                  boxShadow: ClassroomTheme.softShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            slide.title,
                            style: const TextStyle(
                              color: ClassroomTheme.navy,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              letterSpacing: -0.2,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (slide.highlightType != SlideHighlightType.none) ...[
                          const SizedBox(width: 8),
                          SlideHighlightBadge(slide: slide, dense: true),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    SlideVisualContent(
                      slide: slide,
                      revealCount: revealCount,
                      zoom: zoom,
                      activeBulletIndex: activeBulletIndex,
                      speechProgress: speechProgress,
                      isSpeaking: isSpeaking,
                      narratedKeywords: narratedKeywords,
                      activeKeyword: activeKeyword,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: safeIndex == 0 ? null : () => onIndexChanged(safeIndex - 1),
                    icon: const Icon(Icons.chevron_left_rounded, size: 18),
                    label: const Text('Prev'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: safeIndex == slides.length - 1
                        ? null
                        : () => onIndexChanged(safeIndex + 1),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    label: const Text('Next'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
