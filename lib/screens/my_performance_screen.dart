import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/feature_screen_scaffold.dart';

class MyPerformanceScreen extends StatelessWidget {
  const MyPerformanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FeatureScreenScaffold(
      title: 'My Performance',
      icon: Icons.insights_rounded,
      description:
          'Analyse your scores, accuracy trends, weak areas, and overall exam readiness at a glance.',
      headerAction: Row(
        children: [
          _PerformanceStat(
            label: 'Overall Score',
            value: '68%',
            icon: Icons.grade_rounded,
          ),
          const SizedBox(width: 10),
          _PerformanceStat(
            label: 'Tests Taken',
            value: '14',
            icon: Icons.fact_check_rounded,
          ),
          const SizedBox(width: 10),
          _PerformanceStat(
            label: 'Rank',
            value: '#42',
            icon: Icons.emoji_events_rounded,
          ),
        ],
      ),
      items: const [
        PlaceholderListItem(
          title: 'Subject-wise Analysis',
          subtitle: 'Strengths and weak areas by subject',
          icon: Icons.bar_chart_rounded,
        ),
        PlaceholderListItem(
          title: 'Accuracy Trends',
          subtitle: 'Weekly accuracy over last 4 weeks',
          icon: Icons.show_chart_rounded,
        ),
        PlaceholderListItem(
          title: 'Time Management',
          subtitle: 'Average time per question analysis',
          icon: Icons.speed_rounded,
        ),
        PlaceholderListItem(
          title: 'Mock Test History',
          subtitle: 'All past mock test scorecards',
          icon: Icons.history_rounded,
        ),
        PlaceholderListItem(
          title: 'Improvement Tips',
          subtitle: 'AI-suggested areas to focus on',
          icon: Icons.tips_and_updates_rounded,
        ),
      ],
    );
  }
}

class _PerformanceStat extends StatelessWidget {
  const _PerformanceStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.orange, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
                fontSize: 18,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
