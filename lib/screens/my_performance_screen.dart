import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/mock_tests_screen.dart';
import 'package:mpsc_combine_ai/screens/revision/revision_hub_screen.dart';
import 'package:mpsc_combine_ai/screens/subject_notes_screen.dart';
import 'package:mpsc_combine_ai/screens/weakness/ai_weakness_tracker_screen.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

class MyPerformanceScreen extends StatelessWidget {
  const MyPerformanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = authService.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Performance')),
        body: const Center(child: Text('Sign in to sync performance analytics.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Performance')),
      body: StreamBuilder<List<PersistedTestAttempt>>(
        stream: studentProgressRepository.watchTestAttempts(uid),
        builder: (context, attemptSnap) {
          return StreamBuilder<List<CertificateItem>>(
            stream: studentProgressRepository.watchCertificates(uid),
            builder: (context, certSnap) {
              return StreamBuilder<int>(
                stream: studentProgressRepository.watchStudyStreak(uid),
                builder: (context, streakSnap) {
                  final attempts =
                      attemptSnap.data ?? const <PersistedTestAttempt>[];
                  final certs = certSnap.data ?? const <CertificateItem>[];
                  final streak = streakSnap.data ?? 0;

                  final studySeconds = attempts.fold<int>(
                    0,
                    (s, a) => s + a.timeTakenSeconds,
                  );
                  final studyHours = studySeconds / 3600.0;
                  final avg = attempts.isEmpty
                      ? 0.0
                      : attempts
                              .map((a) => a.percentage)
                              .fold<double>(0, (s, v) => s + v) /
                          attempts.length;
                  final accuracy = attempts.isEmpty
                      ? 0.0
                      : attempts
                              .map((a) => a.totalQuestions == 0
                                  ? 0.0
                                  : a.correct / a.totalQuestions)
                              .fold<double>(0, (s, v) => s + v) /
                          attempts.length;

                  final weak = [...attempts]
                    ..sort((a, b) => a.percentage.compareTo(b.percentage));
                  final strong = [...attempts]
                    ..sort((a, b) => b.percentage.compareTo(a.percentage));
                  final weakTitles =
                      weak.take(3).map((a) => a.testTitle).toSet().toList();
                  final strongTitles =
                      strong.take(3).map((a) => a.testTitle).toSet().toList();

                  final recent = attempts.take(7).toList().reversed.toList();

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.warning_amber_rounded,
                            color: AppColors.orange,
                          ),
                          title: const Text(
                            'कमकुवत विषय ट्रॅकर',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'चाचणी/क्विझ वरून खरे कमकुवत विषय',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AiWeaknessTrackerScreen(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              label: 'Study hours',
                              value: studyHours < 0.1
                                  ? '—'
                                  : '${studyHours.toStringAsFixed(1)}h',
                              icon: Icons.timer_rounded,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatCard(
                              label: 'Chapters done',
                              value: '${certs.length}',
                              icon: Icons.menu_book_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              label: 'Accuracy',
                              value: attempts.isEmpty
                                  ? '—'
                                  : '${(accuracy * 100).toStringAsFixed(0)}%',
                              icon: Icons.gps_fixed_rounded,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatCard(
                              label: 'Daily streak',
                              value: streak == 0 ? '—' : '$streak days',
                              icon: Icons.local_fire_department_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _StatCard(
                        label: 'Overall score (avg)',
                        value: attempts.isEmpty
                            ? '—'
                            : '${avg.toStringAsFixed(0)}%',
                        icon: Icons.grade_rounded,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Recent scores',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      if (recent.isEmpty)
                        const Text(
                          'Take a mock test to unlock score graphs.',
                          style: TextStyle(color: AppColors.textSecondary),
                        )
                      else
                        SizedBox(
                          height: 140,
                          child: _ScoreBars(attempts: recent),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'Weak topics',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        weakTitles.isEmpty
                            ? 'Not enough attempts yet'
                            : weakTitles.join(' · '),
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Strong topics',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        strongTitles.isEmpty
                            ? 'Not enough attempts yet'
                            : strongTitles.join(' · '),
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 20),
                      ListTile(
                        leading: const Icon(Icons.assignment_rounded,
                            color: AppColors.navy),
                        title: Text('Mock history (${attempts.length})'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const MockTestsScreen(),
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.style_rounded,
                            color: AppColors.navy),
                        title: const Text('Revise weak areas'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const RevisionHubScreen(),
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.library_books_rounded,
                            color: AppColors.navy),
                        title: const Text('Continue notes'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SubjectNotesScreen(),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: AppColors.navy,
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
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreBars extends StatelessWidget {
  const _ScoreBars({required this.attempts});

  final List<PersistedTestAttempt> attempts;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final a in attempts)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${a.percentage.toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: FractionallySizedBox(
                      heightFactor: (a.percentage / 100).clamp(0.05, 1.0),
                      widthFactor: 1,
                      alignment: Alignment.bottomCenter,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.orange.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
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
