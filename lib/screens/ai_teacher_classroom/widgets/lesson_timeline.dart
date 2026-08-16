import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// "Lesson Timeline" — a horizontally scrollable row of lesson segments,
/// one per slide/script segment of the current [GeneratedLesson]. [activeIndex]
/// is owned by the parent screen so it can stay in sync with whichever
/// segment is currently being narrated during real playback.
class LessonTimeline extends StatelessWidget {
  const LessonTimeline({
    super.key,
    required this.steps,
    this.activeIndex = 0,
    this.onStepTap,
  });

  final List<LessonTimelineStep> steps;
  final int activeIndex;
  final ValueChanged<int>? onStepTap;

  int get _activeIndex => activeIndex;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lesson Timeline',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(steps.length, (i) {
                  final step = steps[i];
                  final isActive = i == _activeIndex;
                  final isDone = i < _activeIndex;
                  return Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: onStepTap == null ? null : () => onStepTap!(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isActive
                                      ? AppColors.orange
                                      : isDone
                                          ? AppColors.navy.withValues(alpha: 0.12)
                                          : AppColors.background,
                                  border: Border.all(
                                    color: isActive
                                        ? AppColors.orange
                                        : AppColors.navy.withValues(alpha: 0.2),
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  isDone && !isActive ? Icons.check_rounded : step.icon,
                                  color: isActive ? Colors.white : AppColors.navy,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: 76,
                                child: Text(
                                  step.label,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                    color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (i != steps.length - 1)
                        Container(
                          width: 32,
                          height: 2,
                          margin: const EdgeInsets.only(bottom: 22),
                          color: isDone ? AppColors.navy.withValues(alpha: 0.3) : AppColors.background,
                        ),
                    ],
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
