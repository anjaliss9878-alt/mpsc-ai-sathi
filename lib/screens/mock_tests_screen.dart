import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/test_item.dart';
import 'package:mpsc_combine_ai/screens/cbt_test_screen.dart';
import 'package:mpsc_combine_ai/services/test_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/feature_screen_scaffold.dart';

class MockTestsScreen extends StatelessWidget {
  const MockTestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TestItem>>(
      stream: testRepository.watchPublished(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <TestItem>[];
        return FeatureScreenScaffold(
          title: 'Mock Tests',
          icon: Icons.assignment_rounded,
          description:
              'Attempt full-length mock tests simulating real MPSC Combine exam conditions with timed sessions.',
          headerAction: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.navy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.navy.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_rounded, color: AppColors.navy, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${items.length} test${items.length == 1 ? '' : 's'} available',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          isLoading: !snapshot.hasData && !snapshot.hasError,
          emptyMessage: snapshot.hasError
              ? 'चाचणी लोड करता आली नाही. (Could not load tests.)'
              : 'Tap a test to start your timed attempt.',
          items: snapshot.hasError
              ? const [
                  PlaceholderListItem(
                    title: 'Could not load mock tests',
                    subtitle: 'Please check your connection and try again.',
                    icon: Icons.cloud_off_rounded,
                  ),
                ]
              : items.isEmpty
                  ? const [
                      PlaceholderListItem(
                        title: 'No mock tests yet',
                        subtitle: 'Check back soon for new tests.',
                        icon: Icons.inbox_rounded,
                      ),
                    ]
                  : items
                      .map(
                        (test) => PlaceholderListItem(
                          title: test.title,
                          subtitle: test.subtitle.isNotEmpty
                              ? test.subtitle
                              : '${test.questions.length} Q • ${test.durationSeconds ~/ 60} min',
                          icon: Icons.assignment_turned_in_rounded,
                          onTap: test.questions.isEmpty
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => CbtTestScreen(test: test),
                                    ),
                                  );
                                },
                        ),
                      )
                      .toList(),
        );
      },
    );
  }
}
