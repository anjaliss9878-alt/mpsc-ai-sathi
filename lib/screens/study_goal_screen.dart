import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/study_goal.dart';
import 'package:mpsc_combine_ai/screens/mcq_practice_screen.dart';
import 'package:mpsc_combine_ai/screens/mock_tests_screen.dart';
import 'package:mpsc_combine_ai/screens/revision/revision_hub_screen.dart';
import 'package:mpsc_combine_ai/screens/subject_notes_screen.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Today's Study Goal — Firebase-backed, midnight-reset by date key.
class StudyGoalScreen extends StatelessWidget {
  const StudyGoalScreen({super.key});

  Future<void> _toggle(
    BuildContext context, {
    required StudyGoal goal,
    required String task,
    required bool current,
  }) async {
    final uid = authService.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to save study goals.')),
      );
      return;
    }
    try {
      await studentProgressRepository.markGoalTask(
        uid: uid,
        task: task,
        done: !current,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update goal: $e')),
      );
    }
  }

  Future<void> _openTask(BuildContext context, String task) async {
    final uid = authService.currentUser?.uid;
    final Widget? screen = switch (task) {
      'notes' => const SubjectNotesScreen(),
      'mcqs' => const McqPracticeScreen(),
      'revision' => const RevisionHubScreen(),
      'test' => const MockTestsScreen(),
      _ => null,
    };
    if (screen == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (uid == null) return;
    // Auto-mark as done when the student returns from the activity.
    try {
      await studentProgressRepository.markGoalTask(
        uid: uid,
        task: task,
        done: true,
        sessionType: task,
        sessionTitle: 'Continued $task',
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final uid = authService.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text("Today's Study Goal")),
      body: uid == null
          ? const Center(child: Text("Sign in to track today's goals."))
          : StreamBuilder<StudyGoal>(
              stream: studentProgressRepository.watchTodayGoal(uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Goal load failed.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final goal = snapshot.data ?? StudyGoal.emptyForToday();
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${goal.completedCount} of ${goal.totalCount} tasks completed',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                Text(
                                  '${(goal.progress * 100).toInt()}%',
                                  style: const TextStyle(
                                    color: AppColors.orange,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: goal.progress,
                                minHeight: 10,
                                backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                                color: AppColors.orange,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Resets at midnight · ${goal.dateKey}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            if (goal.lastSessionTitle.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Last session: ${goal.lastSessionTitle}',
                                style: const TextStyle(color: AppColors.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _GoalTaskTile(
                      label: 'Notes',
                      subtitle: 'Read chapter notes',
                      icon: Icons.library_books_rounded,
                      done: goal.notesDone,
                      onOpen: () => _openTask(context, 'notes'),
                      onToggle: () => _toggle(
                        context,
                        goal: goal,
                        task: 'notes',
                        current: goal.notesDone,
                      ),
                    ),
                    _GoalTaskTile(
                      label: 'MCQs',
                      subtitle: 'Practice question sets',
                      icon: Icons.quiz_rounded,
                      done: goal.mcqsDone,
                      onOpen: () => _openTask(context, 'mcqs'),
                      onToggle: () => _toggle(
                        context,
                        goal: goal,
                        task: 'mcqs',
                        current: goal.mcqsDone,
                      ),
                    ),
                    _GoalTaskTile(
                      label: 'Revision',
                      subtitle: 'Flashcards, summaries & timer',
                      icon: Icons.style_rounded,
                      done: goal.revisionDone,
                      onOpen: () => _openTask(context, 'revision'),
                      onToggle: () => _toggle(
                        context,
                        goal: goal,
                        task: 'revision',
                        current: goal.revisionDone,
                      ),
                    ),
                    _GoalTaskTile(
                      label: 'Test',
                      subtitle: 'Mock / topic tests',
                      icon: Icons.assignment_rounded,
                      done: goal.testDone,
                      onOpen: () => _openTask(context, 'test'),
                      onToggle: () => _toggle(
                        context,
                        goal: goal,
                        task: 'test',
                        current: goal.testDone,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _GoalTaskTile extends StatelessWidget {
  const _GoalTaskTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.done,
    required this.onOpen,
    required this.onToggle,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool done;
  final VoidCallback onOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: AppColors.navy),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: done ? 'Mark incomplete' : 'Mark complete',
              onPressed: onToggle,
              icon: Icon(
                done ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: done ? Colors.green : AppColors.textSecondary,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.orange),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }
}
