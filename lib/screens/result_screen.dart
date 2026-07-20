import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/test_item.dart';
import 'package:mpsc_combine_ai/models/test_result.dart';
import 'package:mpsc_combine_ai/screens/answer_analysis_screen.dart';
import 'package:mpsc_combine_ai/screens/cbt_test_screen.dart';
import 'package:mpsc_combine_ai/services/test_result_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.result, required this.test});

  final TestResult result;

  /// Kept only to let "Retake Test" restart the same test — its questions
  /// and marking scheme always come fresh from Firestore via [test].
  final TestItem test;

  String get _timeTakenText {
    final m = result.timeTakenSeconds ~/ 60;
    final s = result.timeTakenSeconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final recentResults = TestResultRepository.instance
        .getResults()
        .where((r) => r != result)
        .take(4)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Test Result')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ScoreHeader(result: result),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.2,
              children: [
                _StatCard(
                  label: 'Total Questions',
                  value: '${result.totalQuestions}',
                  icon: Icons.list_alt_rounded,
                  color: AppColors.navy,
                ),
                _StatCard(
                  label: 'Attempted',
                  value: '${result.attempted}',
                  icon: Icons.edit_note_rounded,
                  color: AppColors.navy,
                ),
                _StatCard(
                  label: 'Unattempted',
                  value: '${result.unattempted}',
                  icon: Icons.remove_circle_outline_rounded,
                  color: AppColors.textSecondary,
                ),
                _StatCard(
                  label: 'Correct Answers',
                  value: '${result.correct}',
                  icon: Icons.check_circle_rounded,
                  color: Colors.green,
                ),
                _StatCard(
                  label: 'Wrong Answers',
                  value: '${result.wrong}',
                  icon: Icons.cancel_rounded,
                  color: Colors.red,
                ),
                _StatCard(
                  label: 'Time Taken',
                  value: _timeTakenText,
                  icon: Icons.timer_rounded,
                  color: AppColors.orange,
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AnswerAnalysisScreen(result: result),
                    ),
                  );
                },
                icon: const Icon(Icons.fact_check_rounded),
                label: const Text('View Answer Analysis'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.navy,
                  side: BorderSide(
                    color: AppColors.navy.withValues(alpha: 0.3),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => CbtTestScreen(test: test),
                    ),
                  );
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retake Test'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back to Mock Tests'),
              ),
            ),
            if (recentResults.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text(
                'Recent Attempts',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
              ),
              const SizedBox(height: 10),
              ...recentResults.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RecentAttemptTile(result: r),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({required this.result});

  final TestResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navyDark, AppColors.navy, AppColors.navyLight],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            result.percentage >= 50
                ? Icons.emoji_events_rounded
                : Icons.info_outline_rounded,
            color: AppColors.orange,
            size: 36,
          ),
          const SizedBox(height: 8),
          Text(
            result.testTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            result.score.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 40,
            ),
          ),
          Text(
            'out of ${result.maxScore.toStringAsFixed(0)} marks',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${result.percentage.toStringAsFixed(1)}%',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentAttemptTile extends StatelessWidget {
  const _RecentAttemptTile({required this.result});

  final TestResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.navy.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.assignment_turned_in_rounded,
            color: AppColors.navy,
            size: 20,
          ),
        ),
        title: Text(
          result.testTitle,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${result.dateTime.day}/${result.dateTime.month}/${result.dateTime.year} · '
          '${result.correct}/${result.totalQuestions} correct',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          '${result.percentage.toStringAsFixed(0)}%',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.orange,
          ),
        ),
      ),
    );
  }
}
