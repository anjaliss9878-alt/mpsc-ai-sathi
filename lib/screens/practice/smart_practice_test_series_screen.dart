import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/mcq_practice_screen.dart';
import 'package:mpsc_combine_ai/screens/mock_tests_screen.dart';
import 'package:mpsc_combine_ai/screens/tests/tests_tab_screen.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/feature_screen_scaffold.dart';

/// Hub for Smart Practice (MCQs) and Test Series (mock / full tests).
/// Routes into the existing practice and test screens — does not reimplement them.
class SmartPracticeTestSeriesScreen extends StatelessWidget {
  const SmartPracticeTestSeriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FeatureScreenScaffold(
      title: 'Smart Practice + Test Series',
      icon: Icons.assignment_rounded,
      description:
          'Practice topic MCQs and attempt full-length mock tests that follow MPSC Combine exam conditions.',
      sectionTitle: 'Open a mode',
      emptyMessage: 'Choose practice questions or a timed test series.',
      items: [
        PlaceholderListItem(
          title: 'Smart Practice',
          subtitle: 'Topic-wise MCQ sets for daily practice.',
          icon: Icons.quiz_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const McqPracticeScreen()),
          ),
        ),
        PlaceholderListItem(
          title: 'Test Series',
          subtitle: 'Full-length mock tests with a timer.',
          icon: Icons.assignment_turned_in_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MockTestsScreen()),
          ),
        ),
        PlaceholderListItem(
          title: 'All Tests',
          subtitle: 'Upcoming tests, attempts, and analytics.',
          icon: Icons.fact_check_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const TestsTabScreen(embeddedInTab: false),
            ),
          ),
        ),
      ],
      headerAction: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.navy.withValues(alpha: 0.1)),
        ),
        child: const Text(
          'Use Smart Practice for quick sets. Use Test Series for exam-like papers.',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
