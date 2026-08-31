import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/ai_teacher_classroom_screen.dart';
import 'package:mpsc_combine_ai/screens/mcq_practice_screen.dart';
import 'package:mpsc_combine_ai/screens/mock_tests_screen.dart';
import 'package:mpsc_combine_ai/screens/pyq_screen.dart';
import 'package:mpsc_combine_ai/screens/revision/revision_hub_screen.dart';
import 'package:mpsc_combine_ai/screens/study_planner_screen.dart';
import 'package:mpsc_combine_ai/screens/syllabus/syllabus_subject_screen.dart';
import 'package:mpsc_combine_ai/services/ai_weakness_tracker.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Student weakness overview from real tests + classroom quizzes + syllabus.
class AiWeaknessTrackerScreen extends StatefulWidget {
  const AiWeaknessTrackerScreen({super.key});

  @override
  State<AiWeaknessTrackerScreen> createState() =>
      _AiWeaknessTrackerScreenState();
}

class _AiWeaknessTrackerScreenState extends State<AiWeaknessTrackerScreen> {
  late final String? _uid;
  Stream<WeaknessSnapshot>? _stream;
  int _retry = 0;

  @override
  void initState() {
    super.initState();
    final uid = authService.currentUser?.uid;
    _uid = uid;
    _stream = uid == null ? null : aiWeaknessTracker.watch(uid);
  }

  void _reload() {
    final uid = _uid;
    setState(() {
      _retry++;
      if (uid != null) {
        _stream = aiWeaknessTracker.watch(uid);
      }
    });
  }

  String _errorMessage(Object error) {
    final text = '$error'.toLowerCase();
    if (text.contains('permission-denied') ||
        text.contains('permission_denied')) {
      return 'Firebase permission was denied. Please sign in again.';
    }
    if (text.contains('unavailable') ||
        text.contains('network') ||
        text.contains('socket') ||
        text.contains('offline')) {
      return 'Network unavailable. Check your connection and try again.';
    }
    return 'Could not load weakness analysis.\n$error';
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    return Scaffold(
      appBar: AppBar(title: const Text('AI Weakness Tracker')),
      body: uid == null
          ? const ErrorState(message: 'Sign in to view your weakness analysis.')
          : StreamBuilder<WeaknessSnapshot>(
              key: ValueKey(_retry),
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorState(
                    message: _errorMessage(snapshot.error!),
                    onRetry: _reload,
                  );
                }
                if (!snapshot.hasData) return const LoadingState();
                final data = snapshot.data!;
                final analysis = data.analysis;
                if (analysis == null || !analysis.hasPerformance) {
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const EmptyState(
                        icon: Icons.insights_outlined,
                        message:
                            'Not enough performance data yet.\n'
                            'Complete a test, classroom quiz, or MCQ practice set '
                            'and weak topics will appear here from your real results.',
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const MockTestsScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.quiz_outlined),
                        label: const Text('Take a test'),
                      ),
                    ],
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _OverviewCard(snapshot: data, analysis: analysis),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const StudyPlannerScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.edit_calendar_rounded),
                      label: const Text('Add to today’s plan'),
                    ),
                    const SizedBox(height: 20),
                    const _SectionTitle('Priority weak areas'),
                    if (analysis.priorityWeakAreas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'No weak or critical topics found.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    else
                      for (final topic in analysis.priorityWeakAreas.take(8))
                        _WeakAreaCard(
                          topic: topic,
                          onAction: (action) =>
                              _openAction(context, action, topic),
                        ),
                    const SizedBox(height: 12),
                    const _SectionTitle('Subject performance'),
                    _SubjectGroups(analysis: analysis),
                    const SizedBox(height: 12),
                    const _SectionTitle('Topic performance'),
                    if (analysis.topics.isEmpty)
                      const Text(
                        'Not enough data',
                        style: TextStyle(color: AppColors.textSecondary),
                      )
                    else
                      for (final topic in analysis.topics)
                        _TopicTile(topic: topic),
                    const SizedBox(height: 12),
                    const _SectionTitle('Syllabus mix'),
                    _SyllabusMix(analysis: analysis),
                    const SizedBox(height: 12),
                    const _SectionTitle('Recommended actions'),
                    _ActionsList(
                      analysis: analysis,
                      onAction: (action, topic) =>
                          _openAction(context, action, topic),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Future<void> _openAction(
    BuildContext context,
    WeaknessAction action,
    TopicWeaknessReport topic,
  ) async {
    switch (action.kind) {
      case WeaknessActionKind.revise:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const RevisionHubScreen()),
        );
      case WeaknessActionKind.mcq:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const McqPracticeScreen()),
        );
      case WeaknessActionKind.pyq:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PyqScreen()),
        );
      case WeaknessActionKind.test:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const MockTestsScreen()),
        );
      case WeaknessActionKind.aiTeacher:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AiTeacherClassroomScreen(
              initialTopic: topic.label,
              subjectTitle: topic.subjectTitle,
            ),
          ),
        );
      case WeaknessActionKind.syllabus:
        if (topic.subjectId.isEmpty) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const StudyPlannerScreen(),
            ),
          );
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SyllabusSubjectScreen(subjectId: topic.subjectId),
          ),
        );
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.snapshot, required this.analysis});

  final WeaknessSnapshot snapshot;
  final WeaknessAnalysisResult analysis;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your weak areas',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Overall accuracy: ${analysis.overallAccuracy.round()}%  ·  '
              'Questions: ${analysis.overallAttempted}  ·  '
              'Correct ${analysis.overallCorrect}  ·  Wrong ${analysis.overallWrong}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              'Trend: ${analysis.overallTrend.label}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (analysis.timeSpentSeconds > 0)
              Text(
                'वेळ: ${(analysis.timeSpentSeconds / 60).round()} मि',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            const SizedBox(height: 8),
            Text(
              'Strong ≥ ${snapshot.thresholds.strongMin.round()}% · '
              'Improving ${snapshot.thresholds.improvingMin.round()}–${(snapshot.thresholds.strongMin - 1).round()}% · '
              'Weak ${snapshot.thresholds.weakMin.round()}–${(snapshot.thresholds.improvingMin - 1).round()}% · '
              'Critical < ${snapshot.thresholds.weakMin.round()}%',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeakAreaCard extends StatelessWidget {
  const _WeakAreaCard({required this.topic, required this.onAction});

  final TopicWeaknessReport topic;
  final void Function(WeaknessAction action) onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _BandChip(band: topic.band),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    topic.subjectTitle.isEmpty
                        ? topic.label
                        : '${topic.subjectTitle} → ${topic.label}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Accuracy: ${topic.accuracyPercent.round()}%  ·  '
              'Attempts: ${topic.attempted}  ·  '
              'Correct ${topic.correct} / Wrong ${topic.wrong}  ·  '
              'Trend: ${topic.trend.label}  ·  '
              'Priority: ${topic.band.priorityLabel}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (topic.repeatedMistakes)
              const Text(
                'Repeated mistakes',
                style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final action in topic.actions.take(3))
                  ActionChip(
                    label: Text(action.label, style: const TextStyle(fontSize: 12)),
                    onPressed: () => onAction(action),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectGroups extends StatelessWidget {
  const _SubjectGroups({required this.analysis});

  final WeaknessAnalysisResult analysis;

  @override
  Widget build(BuildContext context) {
    Widget group(String title, WeaknessBand band) {
      final rows = analysis.subjects.where((s) => s.band == band).toList();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              if (rows.isEmpty)
                const Text(
                  'Not enough data',
                  style: TextStyle(color: AppColors.textSecondary),
                )
              else
                for (final s in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${s.subjectTitle}: ${s.accuracyPercent.round()}% '
                      '(${s.correct}/${s.attempted}) · ${s.trend.label}',
                    ),
                  ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        group('Critical subjects', WeaknessBand.critical),
        group('Weak subjects', WeaknessBand.weak),
        group('Improving subjects', WeaknessBand.improving),
        group('Strong subjects', WeaknessBand.strong),
      ],
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.topic});

  final TopicWeaknessReport topic;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(topic.label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${topic.subjectTitle.isEmpty ? '' : '${topic.subjectTitle} · '}'
          '${topic.accuracyPercent.round()}% · ${topic.attempted} attempts · '
          'Correct ${topic.correct} / Wrong ${topic.wrong} · '
          '${topic.band.label} · ${topic.trend.label}'
          '${topic.syllabusStatus == null ? '' : ' · ${_statusMr(topic.syllabusStatus!)}'}',
        ),
        trailing: _BandChip(band: topic.band),
      ),
    );
  }
}

class _SyllabusMix extends StatelessWidget {
  const _SyllabusMix({required this.analysis});

  final WeaknessAnalysisResult analysis;

  @override
  Widget build(BuildContext context) {
    Widget row(String title, List<TopicWeaknessReport> items) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              if (items.isEmpty)
                const Text(
                  'Not enough data',
                  style: TextStyle(color: AppColors.textSecondary),
                )
              else
                for (final t in items)
                  Text('${t.subjectTitle} → ${t.label} (${t.accuracyPercent.round()}%)'),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        row('Weak + incomplete', analysis.weakIncomplete),
        row('Weak + completed', analysis.weakCompleted),
        row('Strong + completed', analysis.strongCompleted),
      ],
    );
  }
}

class _ActionsList extends StatelessWidget {
  const _ActionsList({
    required this.analysis,
    required this.onAction,
  });

  final WeaknessAnalysisResult analysis;
  final void Function(WeaknessAction action, TopicWeaknessReport topic) onAction;

  @override
  Widget build(BuildContext context) {
    final topics = analysis.priorityWeakAreas.take(5).toList();
    if (topics.isEmpty) {
      return const Text(
        'No recommended actions until a weak topic is recorded.',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    return Column(
      children: [
        for (final topic in topics)
          for (final action in topic.actions.take(2))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.chevron_right_rounded, color: AppColors.orange),
              title: Text(action.label),
              subtitle: Text(topic.label),
              onTap: () => onAction(action, topic),
            ),
      ],
    );
  }
}

class _BandChip extends StatelessWidget {
  const _BandChip({required this.band});

  final WeaknessBand band;

  @override
  Widget build(BuildContext context) {
    final color = switch (band) {
      WeaknessBand.critical => Colors.red.shade700,
      WeaknessBand.weak => AppColors.orange,
      WeaknessBand.improving => AppColors.gold,
      WeaknessBand.strong => Colors.green.shade700,
      WeaknessBand.insufficient => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        band.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

String _statusMr(SyllabusTopicStatus status) {
  switch (status) {
    case SyllabusTopicStatus.completed:
      return 'Completed';
    case SyllabusTopicStatus.inProgress:
      return 'In progress';
    case SyllabusTopicStatus.pending:
      return 'Pending';
  }
}
