import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/test_item.dart';
import 'package:mpsc_combine_ai/screens/answer_analysis_screen.dart';
import 'package:mpsc_combine_ai/screens/cbt_test_screen.dart';
import 'package:mpsc_combine_ai/screens/mock_tests_screen.dart';
import 'package:mpsc_combine_ai/screens/my_performance_screen.dart';
import 'package:mpsc_combine_ai/screens/pyq_screen.dart';
import 'package:mpsc_combine_ai/screens/result_screen.dart';
import 'package:mpsc_combine_ai/screens/weakness/ai_weakness_tracker_screen.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/test_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Tests bottom-nav tab: upcoming tests, attempt history, rank/analytics.
class TestsTabScreen extends StatelessWidget {
  const TestsTabScreen({super.key, this.embeddedInTab = true});

  /// When true (bottom-nav tab), the back button is hidden.
  /// When false (pushed from Home), the AppBar shows a back button.
  final bool embeddedInTab;

  @override
  Widget build(BuildContext context) {
    final uid = authService.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tests'),
        automaticallyImplyLeading: !embeddedInTab,
        actions: [
          IconButton(
            tooltip: 'Analytics',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AiWeaknessTrackerScreen(),
              ),
            ),
            icon: const Icon(Icons.insights_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _QuickLink(
                  label: 'Mock Tests',
                  icon: Icons.assignment_rounded,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MockTestsScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickLink(
                  label: 'PYQ',
                  icon: Icons.history_edu_rounded,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const PyqScreen()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Upcoming / Available',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<TestItem>>(
            stream: testRepository.watchPublished(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ErrorState(
                  message: 'Could not load tests.\n${snapshot.error}',
                );
              }
              if (!snapshot.hasData) return const LoadingState();
              final tests = snapshot.data!;
              if (tests.isEmpty) {
                return const EmptyState(
                  message: 'No tests published yet.',
                  icon: Icons.fact_check_outlined,
                );
              }
              return Column(
                children: tests.take(10).map((test) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.assignment_turned_in_rounded,
                        color: AppColors.navy,
                      ),
                      title: Text(
                        test.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        test.subtitle.isNotEmpty
                            ? test.subtitle
                            : '${test.questions.length} Q · ${test.durationSeconds ~/ 60} min',
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.orange,
                      ),
                      onTap: test.questions.isEmpty
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CbtTestScreen(test: test),
                              ),
                            ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Attempt history',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (uid == null)
            const Text('Sign in to sync attempt history.')
          else
            StreamBuilder<List<PersistedTestAttempt>>(
              stream: studentProgressRepository.watchTestAttempts(uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Could not load history.\n${snapshot.error}');
                }
                if (!snapshot.hasData) return const LoadingState();
                final attempts = snapshot.data!;
                if (attempts.isEmpty) {
                  return const EmptyState(
                    message:
                        'No attempts yet. Take a mock test to see history & rank.',
                    icon: Icons.history_rounded,
                  );
                }
                final avg =
                    attempts
                        .map((a) => a.percentage)
                        .fold<double>(0, (s, v) => s + v) /
                    attempts.length;
                // Simple cohort-free rank estimate from personal average.
                final rankEstimate = avg >= 85
                    ? 5
                    : avg >= 70
                    ? 25
                    : avg >= 55
                    ? 60
                    : 120;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            _MiniStat(
                              label: 'Attempts',
                              value: '${attempts.length}',
                            ),
                            _MiniStat(
                              label: 'Avg %',
                              value: '${avg.toStringAsFixed(0)}%',
                            ),
                            _MiniStat(
                              label: 'Est. Rank',
                              value: '#$rankEstimate',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...attempts.take(20).map((a) {
                      return Card(
                        child: ListTile(
                          title: Text(a.testTitle),
                          subtitle: Text(
                            '${a.percentage.toStringAsFixed(0)}% · '
                                    '${a.correct}/${a.totalQuestions} · '
                                    '${a.dateTime.toLocal()}'
                                .split('.')
                                .first,
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            final result = a.toTestResult();
                            if (a.questionResults.isEmpty) {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ResultScreen(
                                    result: result,
                                    test: TestItem(
                                      id: a.testId,
                                      title: a.testTitle,
                                      subtitle: '',
                                      durationSeconds: a.timeTakenSeconds,
                                      correctMarks: 2,
                                      negativeMarks: 0.5,
                                      questions: const [],
                                      order: 0,
                                    ),
                                  ),
                                ),
                              );
                              return;
                            }
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    AnswerAnalysisScreen(result: result),
                              ),
                            );
                          },
                        ),
                      );
                    }),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const MyPerformanceScreen(),
                        ),
                      ),
                      child: const Text('Open full analytics'),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  const _QuickLink({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Icon(icon, color: AppColors.navy),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
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
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
