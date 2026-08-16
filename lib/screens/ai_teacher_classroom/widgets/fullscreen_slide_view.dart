import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/slide_visuals.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/teaching_board.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Full-screen slide mode — opened from the Teaching Board's expand button.
class FullscreenSlideView extends StatefulWidget {
  const FullscreenSlideView({
    super.key,
    required this.slides,
    required this.initialIndex,
    this.revealCount = 999,
  });

  final List<GeneratedSlide> slides;
  final int initialIndex;
  final int revealCount;

  @override
  State<FullscreenSlideView> createState() => _FullscreenSlideViewState();
}

class _FullscreenSlideViewState extends State<FullscreenSlideView> {
  late int _index = widget.initialIndex;

  void _go(int delta) {
    setState(() {
      _index = (_index + delta).clamp(0, widget.slides.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slides[_index];
    return Scaffold(
      backgroundColor: AppColors.navyDark,
      appBar: AppBar(
        backgroundColor: AppColors.navyDark,
        foregroundColor: Colors.white,
        title: Text('Slide ${_index + 1} of ${widget.slides.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.fullscreen_exit_rounded),
            tooltip: 'Exit full screen',
            onPressed: () => Navigator.of(context).pop(_index),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Column(
                        key: ValueKey(_index),
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  slide.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 28,
                                  ),
                                ),
                              ),
                              if (slide.highlightType != SlideHighlightType.none) ...[
                                const SizedBox(width: 12),
                                SlideHighlightBadge(slide: slide),
                              ],
                            ],
                          ),
                          const SizedBox(height: 24),
                          SlideVisualContent(
                            slide: slide,
                            revealCount: widget.revealCount,
                            zoom: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _index == 0 ? null : () => _go(-1),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                      icon: const Icon(Icons.chevron_left_rounded),
                      label: const Text('Prev'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _index == widget.slides.length - 1 ? null : () => _go(1),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
                      icon: const Icon(Icons.chevron_right_rounded),
                      label: const Text('Next'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
