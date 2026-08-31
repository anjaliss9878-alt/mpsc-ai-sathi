import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/study_plan.dart';
import 'package:mpsc_combine_ai/screens/mock_tests_screen.dart';
import 'package:mpsc_combine_ai/screens/planner/daily_planner_tab.dart';
import 'package:mpsc_combine_ai/screens/revision/revision_hub_screen.dart';
import 'package:mpsc_combine_ai/screens/study_goal_screen.dart';
import 'package:mpsc_combine_ai/screens/subject_notes_screen.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/study_planner_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

class StudyPlannerScreen extends StatelessWidget {
  const StudyPlannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Study Planner'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: AppColors.sky,
            tabs: [
              Tab(text: 'Today'),
              Tab(text: 'History'),
              Tab(text: 'Week'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            DailyPlannerTab(),
            PlannerHistoryTab(),
            _WeeklyPlannerTab(),
          ],
        ),
      ),
    );
  }
}

class _WeeklyPlannerTab extends StatefulWidget {
  const _WeeklyPlannerTab();

  @override
  State<_WeeklyPlannerTab> createState() => _WeeklyPlannerTabState();
}

class _WeeklyPlannerTabState extends State<_WeeklyPlannerTab> {
  bool _generating = false;
  String? _error;

  Future<void> _generate() async {
    final uid = authService.currentUser?.uid;
    if (uid == null) {
      setState(() => _error = 'Sign in to generate and sync your study plan.');
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final profile = await profileRepository.getProfile(uid);
      final plan = await studyPlannerService.generateWeeklyPlan(
        targetExam: profile?.targetExam.isNotEmpty == true
            ? profile!.targetExam
            : 'MPSC Combine',
        dailyHours: (profile?.dailyStudyHours ?? 4).round(),
      );
      await studentProgressRepository.saveStudyPlan(uid, plan);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weekly plan saved to your account.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not generate plan: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = authService.currentUser?.uid;
    return uid == null
        ? const Center(child: Text('Sign in to use the AI study planner.'))
        : StreamBuilder<StudyPlan?>(
            stream: studentProgressRepository.watchCurrentStudyPlan(uid),
            builder: (context, planSnap) {
              final plan = planSnap.data;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Weekly Planner',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Generate a Gemini-backed timetable with daily slots, weekly goals, and revision reminders — synced to Firebase.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _generating ? null : _generate,
                            icon: _generating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.auto_awesome_rounded),
                            label: Text(
                              _generating
                                  ? 'Generating…'
                                  : (plan == null
                                      ? 'Generate this week\'s plan'
                                      : 'Regenerate plan'),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Text(_error!,
                                style: const TextStyle(color: Colors.red)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _QuickChip(
                        label: "Today's Goal",
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const StudyGoalScreen(),
                          ),
                        ),
                      ),
                      _QuickChip(
                        label: 'Notes',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SubjectNotesScreen(),
                          ),
                        ),
                      ),
                      _QuickChip(
                        label: 'Revision',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const RevisionHubScreen(),
                          ),
                        ),
                      ),
                      _QuickChip(
                        label: 'Mock Test',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const MockTestsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (planSnap.hasError)
                    Text(
                      'Weekly plan load failed.\n${planSnap.error}',
                      style: const TextStyle(color: Colors.red),
                    )
                  else if (plan == null)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No plan for this week yet. Tap Generate to create one.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else ...[
                    Text(
                      plan.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (plan.summary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        plan.summary,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Weekly goals',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ...plan.weeklyGoals.map(
                      (g) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.flag_rounded,
                            color: AppColors.orange),
                        title: Text(g),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Daily timetable',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ...plan.dailySlots.map(
                      (day) => Card(
                        child: ExpansionTile(
                          title: Text(
                            day.dayLabel,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          children: day.slots
                              .map(
                                (slot) => ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.schedule_rounded,
                                    color: AppColors.navy,
                                  ),
                                  title: Text(slot),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                    if (plan.revisionReminders.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Revision reminders',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      ...plan.revisionReminders.map(
                        (r) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.notifications_active_rounded,
                              color: AppColors.navy),
                          title: Text(r),
                        ),
                      ),
                    ],
                  ],
                ],
              );
            },
          );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: AppColors.navy.withValues(alpha: 0.06),
    );
  }
}
