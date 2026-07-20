import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/feature_screen_scaffold.dart';

class StudyPlannerScreen extends StatelessWidget {
  const StudyPlannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FeatureScreenScaffold(
      title: 'Study Planner',
      icon: Icons.calendar_month_rounded,
      description:
          'Plan your daily study schedule, set targets, and track syllabus completion for MPSC Combine.',
      headerAction: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.navy.withValues(alpha: 0.08),
              AppColors.orange.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This Week',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8),
            Row(
              children: [
                _DayDot(label: 'M', active: true, done: true),
                _DayDot(label: 'T', active: true, done: true),
                _DayDot(label: 'W', active: true, done: false),
                _DayDot(label: 'T', active: false, done: false),
                _DayDot(label: 'F', active: false, done: false),
                _DayDot(label: 'S', active: false, done: false),
                _DayDot(label: 'S', active: false, done: false),
              ],
            ),
          ],
        ),
      ),
      items: const [
        PlaceholderListItem(
          title: "Today's Plan",
          subtitle: 'Polity Ch.5 + 30 MCQs + CA revision',
          icon: Icons.today_rounded,
        ),
        PlaceholderListItem(
          title: 'Weekly Schedule',
          subtitle: 'Mon–Sun study timetable',
          icon: Icons.view_week_rounded,
        ),
        PlaceholderListItem(
          title: 'Syllabus Tracker',
          subtitle: 'Track completed vs pending topics',
          icon: Icons.checklist_rounded,
        ),
        PlaceholderListItem(
          title: 'Set Reminders',
          subtitle: 'Daily study alerts and goals',
          icon: Icons.alarm_rounded,
        ),
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.label,
    required this.active,
    required this.done,
  });

  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: done
                  ? AppColors.orange
                  : active
                      ? AppColors.navy.withValues(alpha: 0.12)
                      : AppColors.navy.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: done
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                : Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: active ? AppColors.navy : AppColors.textSecondary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
