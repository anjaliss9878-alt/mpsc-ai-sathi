import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/daily_study_plan.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/screens/auth/signup_screen.dart' show targetExamOptions;
import 'package:mpsc_combine_ai/screens/mcq_practice_screen.dart';
import 'package:mpsc_combine_ai/screens/mock_tests_screen.dart';
import 'package:mpsc_combine_ai/screens/notes_detail_screen.dart';
import 'package:mpsc_combine_ai/screens/pyq_screen.dart';
import 'package:mpsc_combine_ai/screens/revision/revision_hub_screen.dart';
import 'package:mpsc_combine_ai/screens/subject_notes_screen.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/daily_planner_service.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Today's personalized plan: prefs, generate, complete / skip / reschedule.
class DailyPlannerTab extends StatefulWidget {
  const DailyPlannerTab({super.key});

  @override
  State<DailyPlannerTab> createState() => _DailyPlannerTabState();
}

class _DailyPlannerTabState extends State<DailyPlannerTab> {
  String? _targetExam;
  DateTime? _examDate;
  double _hours = 4;
  List<String> _assignedSubjectIds = const [];
  bool _prefsReady = false;
  bool _generating = false;
  String? _actionError;

  String? get _uid => authService.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final profile = await profileRepository.getProfile(uid);
      if (!mounted || profile == null) return;
      setState(() {
        _applyProfile(profile);
        _prefsReady = true;
      });
    } catch (_) {
      if (mounted) setState(() => _prefsReady = true);
    }
  }

  void _applyProfile(StudentProfile profile) {
    _targetExam = profile.targetExam.isNotEmpty ? profile.targetExam : null;
    _hours = profile.dailyStudyHours.clamp(1, 12);
    _assignedSubjectIds = profile.assignedSubjectIds;
    if (profile.examDate.isNotEmpty) {
      _examDate = DateTime.tryParse(profile.examDate);
    }
  }

  PlannerPrefs _prefs() => PlannerPrefs(
        targetExam: _targetExam ?? 'MPSC Combine',
        examDate: _examDate == null
            ? ''
            : DailyStudyPlan.dateKeyFor(_examDate),
        dailyHours: _hours,
        assignedSubjectIds: _assignedSubjectIds,
      );

  Future<void> _savePrefs() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await profileRepository.updatePlannerPrefs(
        uid: uid,
        targetExam: _prefs().targetExam,
        examDate: _prefs().examDate,
        dailyStudyHours: _hours,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionError = 'Could not save preferences: $e');
    }
  }

  Future<void> _generate({bool force = false}) async {
    final uid = _uid;
    if (uid == null) return;
    if (_targetExam == null || _targetExam!.trim().isEmpty) {
      setState(() => _actionError = 'Please choose a target exam.');
      return;
    }
    setState(() {
      _generating = true;
      _actionError = null;
    });
    try {
      await _savePrefs();
      if (!force) {
        final existing = await studentProgressRepository.getDailyPlan(uid);
        if (existing != null && existing.openTasks.isNotEmpty) {
          if (!mounted) return;
          final replace = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('A plan already exists for today'),
              content: const Text(
                'Generating again will replace incomplete tasks. Completed tasks are not kept.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('New plan'),
                ),
              ],
            ),
          );
          if (replace != true) return;
        }
      }
      final plan = await dailyPlannerService.generate(
        uid: uid,
        prefs: _prefs(),
      );
      if (plan.tasks.isEmpty) {
        if (!mounted) return;
        setState(() {
          _actionError = plan.adaptationNotes.isEmpty
              ? 'Not enough student data to build a personalized plan.'
              : plan.adaptationNotes.join('\n');
        });
        return;
      }
      await studentProgressRepository.saveDailyPlan(uid, plan);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Today’s study plan was saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionError =
            'Could not generate the plan. Check your network and Firebase connection.\n$e';
      });
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _complete(DailyPlanTask task, String dateKey) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await studentProgressRepository.setTaskStatus(
        uid: uid,
        dateKey: dateKey,
        taskId: task.id,
        status: DailyPlanTaskStatus.completed,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionError = 'Could not mark the task complete: $e');
    }
  }

  Future<void> _skip(DailyPlanTask task, String dateKey) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await studentProgressRepository.setTaskStatus(
        uid: uid,
        dateKey: dateKey,
        taskId: task.id,
        status: DailyPlanTaskStatus.skipped,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionError = 'Could not skip the task: $e');
    }
  }

  Future<void> _reschedule(DailyPlanTask task, String dateKey) async {
    final uid = _uid;
    if (uid == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 120)),
    );
    if (picked == null) return;
    final target = DailyStudyPlan.dateKeyFor(picked);
    if (target == dateKey) return;
    try {
      await studentProgressRepository.rescheduleTask(
        uid: uid,
        fromDateKey: dateKey,
        taskId: task.id,
        targetDateKey: target,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Task moved to $target.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionError = 'Could not reschedule: $e');
    }
  }

  Future<void> _pickExamDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate ?? DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked == null) return;
    setState(() => _examDate = picked);
    await _savePrefs();
  }

  Future<void> _openTask(DailyPlanTask task) async {
    Widget screen;
    switch (task.type) {
      case DailyPlanTaskType.revision:
        screen = const RevisionHubScreen();
      case DailyPlanTaskType.practiceMcq:
        screen = const McqPracticeScreen();
      case DailyPlanTaskType.pyq:
        screen = const PyqScreen();
      case DailyPlanTaskType.testQuiz:
        screen = const MockTestsScreen();
      case DailyPlanTaskType.study:
        screen = await _notesScreenFor(task);
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Future<Widget> _notesScreenFor(DailyPlanTask task) async {
    if (task.chapterId.isEmpty) return const SubjectNotesScreen();
    try {
      final chapter = await notesRepository.getChapter(task.chapterId);
      if (chapter == null) return const SubjectNotesScreen();
      return NotesDetailScreen(
        subjectTitle: task.subject,
        chapter: chapter,
        topicNumber: chapter.order,
      );
    } catch (_) {
      return const SubjectNotesScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) {
      return const ErrorState(
        message: 'Sign in to use the daily planner.',
      );
    }

    return StreamBuilder<DailyStudyPlan?>(
      stream: studentProgressRepository.watchDailyPlan(uid),
      builder: (context, planSnap) {
        return StreamBuilder<WeeklyPlannerProgress>(
          stream: studentProgressRepository.watchDailyPlans(uid).asyncMap(
                (_) => studentProgressRepository.weeklyProgress(uid),
              ),
          builder: (context, weekSnap) {
            if (planSnap.hasError) {
              return ErrorState(
                message:
                    'Could not load today’s plan. Check your connection if you are offline.\n${planSnap.error}',
                onRetry: () => setState(() {}),
              );
            }
            if (planSnap.connectionState == ConnectionState.waiting &&
                !planSnap.hasData) {
              return const LoadingState();
            }
            final plan = planSnap.data;
            final weekly = weekSnap.data ??
                const WeeklyPlannerProgress(
                  completedTasks: 0,
                  totalTasks: 0,
                  daysWithPlan: 0,
                );
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _PrefsCard(
                  targetExam: _targetExam,
                  examDate: _examDate,
                  hours: _hours,
                  prefsReady: _prefsReady,
                  onExamChanged: (v) {
                    setState(() => _targetExam = v);
                    _savePrefs();
                  },
                  onHoursChanged: (v) => setState(() => _hours = v),
                  onHoursChangeEnd: (_) => _savePrefs(),
                  onPickDate: _pickExamDate,
                ),
                const SizedBox(height: 12),
                _ProgressCard(
                  daily: plan?.progress ?? 0,
                  weekly: weekly.progress,
                  remaining: plan?.remainingTasks.length ?? 0,
                  completed: plan?.completedCount ?? 0,
                  weekDays: weekly.daysWithPlan,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _generating ? null : () => _generate(),
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
                        ? 'Building plan…'
                        : (plan == null
                            ? 'Create today’s plan'
                            : 'Rebuild plan'),
                  ),
                ),
                if (_actionError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _actionError!,
                    style: const TextStyle(color: Colors.red, height: 1.4),
                  ),
                ],
                const SizedBox(height: 16),
                if (plan == null)
                  const EmptyState(
                    icon: Icons.event_note_rounded,
                    message:
                        'Create today’s plan. It uses your published syllabus, completed and pending topics, test scores, and weak topics from the AI Weakness Tracker — not a generic timetable.',
                  )
                else ...[
                  if (plan.adaptationNotes.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Why this plan',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            for (final n in plan.adaptationNotes)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '• $n',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            Text(
                              'Study ${plan.totalStudyMinutes} min · '
                              'Revision ${plan.totalRevisionMinutes} min · '
                              'Practice ${plan.totalPracticeMinutes} min',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.navy,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Remaining tasks',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (plan.remainingTasks.isEmpty)
                    const EmptyState(
                      icon: Icons.check_circle_outline_rounded,
                      message: 'No remaining tasks for today.',
                    )
                  else
                    for (final task in plan.remainingTasks)
                      _TaskCard(
                        task: task,
                        onOpen: () => _openTask(task),
                        onComplete: () => _complete(task, plan.dateKey),
                        onSkip: () => _skip(task, plan.dateKey),
                        onReschedule: () => _reschedule(task, plan.dateKey),
                      ),
                  const SizedBox(height: 12),
                  Text(
                    'Completed tasks',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (plan.completedTasks.isEmpty)
                    const Text(
                      'Nothing completed yet.',
                      style: TextStyle(color: AppColors.textSecondary),
                    )
                  else
                    for (final task in plan.completedTasks)
                      _TaskCard(task: task, done: true),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class PlannerHistoryTab extends StatelessWidget {
  const PlannerHistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = authService.currentUser?.uid;
    if (uid == null) {
      return const ErrorState(message: 'Sign in to view planner history.');
    }
    final today = DailyStudyPlan.dateKeyFor();
    return StreamBuilder<List<DailyStudyPlan>>(
      stream: studentProgressRepository.watchDailyPlans(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorState(
            message: 'Could not load previous plans.\n${snapshot.error}',
          );
        }
        if (!snapshot.hasData) return const LoadingState();
        final plans = snapshot.data!
            .where((p) => p.dateKey != today)
            .toList();
        if (plans.isEmpty) {
          return const EmptyState(
            icon: Icons.history_rounded,
            message: 'Plans from previous days will appear here.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: plans.length,
          itemBuilder: (context, i) {
            final plan = plans[i];
            return Card(
              child: ExpansionTile(
                title: Text(
                  plan.dateKey,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${plan.completedCount}/${plan.actionableCount} complete · '
                  '${(plan.progress * 100).round()}%',
                ),
                children: [
                  for (final task in plan.tasks)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        task.isDone
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: task.isDone ? Colors.green : AppColors.navy,
                      ),
                      title: Text('${task.typeLabel}: ${task.topic}'),
                      subtitle: Text(
                        '${task.subject} · ${task.durationMinutes} min'
                        '${task.status == DailyPlanTaskStatus.skipped ? ' · skip' : ''}'
                        '${task.status == DailyPlanTaskStatus.rescheduled ? ' → ${task.rescheduledToDateKey}' : ''}',
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _PrefsCard extends StatelessWidget {
  const _PrefsCard({
    required this.targetExam,
    required this.examDate,
    required this.hours,
    required this.prefsReady,
    required this.onExamChanged,
    required this.onHoursChanged,
    required this.onHoursChangeEnd,
    required this.onPickDate,
  });

  final String? targetExam;
  final DateTime? examDate;
  final double hours;
  final bool prefsReady;
  final ValueChanged<String?> onExamChanged;
  final ValueChanged<double> onHoursChanged;
  final ValueChanged<double> onHoursChangeEnd;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final examItems = {
      ...targetExamOptions,
      if (targetExam != null && targetExam!.isNotEmpty) targetExam!,
    }.toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your preparation',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose target exam, exam date, and daily hours. The plan uses your real Firebase progress and weakness analysis.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(targetExam),
              initialValue: examItems.contains(targetExam) ? targetExam : null,
              decoration: const InputDecoration(labelText: 'Target exam'),
              items: [
                for (final e in examItems)
                  DropdownMenuItem(value: e, child: Text(e)),
              ],
              onChanged: prefsReady ? onExamChanged : null,
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded, color: AppColors.navy),
              title: const Text('Exam date'),
              subtitle: Text(
                examDate == null
                    ? 'Optional — closer dates increase revision'
                    : DailyStudyPlan.dateKeyFor(examDate),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onPickDate,
            ),
            Text('Daily study hours: ${hours.toStringAsFixed(1)}'),
            Slider(
              value: hours,
              min: 1,
              max: 12,
              divisions: 22,
              label: '${hours.toStringAsFixed(1)} h',
              onChanged: onHoursChanged,
              onChangeEnd: onHoursChangeEnd,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.daily,
    required this.weekly,
    required this.remaining,
    required this.completed,
    required this.weekDays,
  });

  final double daily;
  final double weekly;
  final int remaining;
  final int completed;
  final int weekDays;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Today',
                    value: '${(daily * 100).round()}%',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Week',
                    value: '${(weekly * 100).round()}%',
                    subtitle: '$weekDays days',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Left',
                    value: '$remaining',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'Done',
                    value: '$completed',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: daily,
                minHeight: 8,
                backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                color: AppColors.sky,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    this.subtitle,
  });

  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppColors.navy,
          ),
        ),
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        if (subtitle != null)
          Text(
            subtitle!,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    this.done = false,
    this.onOpen,
    this.onComplete,
    this.onSkip,
    this.onReschedule,
  });

  final DailyPlanTask task;
  final bool done;
  final VoidCallback? onOpen;
  final VoidCallback? onComplete;
  final VoidCallback? onSkip;
  final VoidCallback? onReschedule;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                done ? Icons.check_circle_rounded : Icons.schedule_rounded,
                color: done ? Colors.green : AppColors.navy,
              ),
              title: Text(
                '${task.typeLabel} · ${task.topic}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${task.subject} · ${task.durationMinutes} min · ${task.priorityLabel}'
                '${task.reason.isEmpty ? '' : ' · ${task.reason}'}',
              ),
              onTap: onOpen,
            ),
            if (!done)
              OverflowBar(
                alignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: onSkip,
                    child: const Text('Skip'),
                  ),
                  TextButton(
                    onPressed: onReschedule,
                    child: const Text('Reschedule'),
                  ),
                  FilledButton(
                    onPressed: onComplete,
                    child: const Text('Complete'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
