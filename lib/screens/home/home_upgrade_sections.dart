import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/ai_lesson.dart';
import 'package:mpsc_combine_ai/models/daily_study_plan.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/ai_teacher_classroom_screen.dart';
import 'package:mpsc_combine_ai/screens/mcq_practice_screen.dart';
import 'package:mpsc_combine_ai/screens/revision/revision_hub_screen.dart';
import 'package:mpsc_combine_ai/screens/study_planner_screen.dart';
import 'package:mpsc_combine_ai/screens/syllabus/syllabus_tracker_screen.dart';
import 'package:mpsc_combine_ai/screens/topic_list_screen.dart';
import 'package:mpsc_combine_ai/screens/weakness/ai_weakness_tracker_screen.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_repository.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_progress_repository.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';
import 'package:mpsc_combine_ai/services/ai_weakness_tracker.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

class HomeUpgradeSections extends StatelessWidget {
  const HomeUpgradeSections({super.key, required this.horizontalPadding});

  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final uid = authService.currentUser?.uid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 0),
          child: const _MiniTitle('AI Teacher'),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 10, horizontalPadding, 0),
          child: _AiTeacherSearchCard(),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 0),
          child: const _MiniTitle("Today's Practice"),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 10, horizontalPadding, 0),
          child: Row(
            children: [
              Expanded(
                child: _MiniActionCard(
                  icon: Icons.quiz_rounded,
                  title: 'Daily MCQ',
                  subtitle: "Solve today's questions",
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const McqPracticeScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniActionCard(
                  icon: Icons.style_rounded,
                  title: 'Revision',
                  subtitle: "Today's recall",
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RevisionHubScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (uid != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              0,
            ),
            child: _TodayPlannerCard(uid: uid),
          ),
        if (uid != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              0,
            ),
            child: _SyllabusProgressCard(uid: uid),
          ),
        if (uid != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              0,
            ),
            child: _WeaknessTrackerCard(uid: uid),
          ),
        if (uid != null) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 0),
            child: const _MiniTitle('Recent AI Lessons'),
          ),
          SizedBox(
            height: 108,
            child: StreamBuilder<List<AiLesson>>(
              stream: aiLessonRepository.watchMine(uid, limit: 8),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const SizedBox.shrink();
                }
                final items = (snapshot.data ?? const <AiLesson>[])
                    .where((e) => e.topic.trim().isNotEmpty)
                    .toList();
                if (items.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 0),
                    child: const Text(
                      'No AI lessons yet. Enter a topic to start.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }
                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 0),
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final lesson = items[i];
                    return ActionChip(
                      avatar: const Icon(Icons.school_rounded, size: 18, color: AppColors.navy),
                      label: Text(lesson.topic),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AiTeacherClassroomScreen(
                              initialTopic: lesson.topic,
                              subjectTitle: lesson.subjectTitle,
                              autoTeachChapter: true,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 0),
            child: const _MiniTitle('Progress by Subject'),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 10, horizontalPadding, 0),
            child: StreamBuilder(
              stream: notesRepository.watchPublishedSubjects(),
              builder: (context, subSnap) {
                if (subSnap.hasError) return const SizedBox.shrink();
                final subjects = subSnap.data ?? const <SubjectItem>[];
                return StreamBuilder(
                  stream: lessonProgressRepository.watchAll(uid, limit: 40),
                  builder: (context, progSnap) {
                    if (progSnap.hasError) return const SizedBox.shrink();
                    final progress = progSnap.data ?? const [];
                    if (subjects.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final bySubject = <String, List<double>>{};
                    for (final p in progress) {
                      if (p.subjectId.trim().isEmpty) continue;
                      bySubject.putIfAbsent(p.subjectId, () => []).add(p.fraction);
                    }
                    return Column(
                      children: [
                        for (final subject in subjects.take(8))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _SubjectProgressRow(
                              title: subject.title,
                              value: _avg(bySubject[subject.id] ?? const []),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => TopicListScreen(subject: subject),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  static double _avg(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}

class _AiTeacherSearchCard extends StatefulWidget {
  @override
  State<_AiTeacherSearchCard> createState() => _AiTeacherSearchCardState();
}

class _AiTeacherSearchCardState extends State<_AiTeacherSearchCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go() {
    final topic = _controller.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiTeacherClassroomScreen(
          initialTopic: topic.isEmpty ? null : topic,
          autoTeachChapter: topic.isNotEmpty,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter any topic — get a complete lesson in one tap',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _go(),
              decoration: const InputDecoration(
                hintText: 'e.g. Ganga River, soils of Maharashtra, Parliament, monsoon, Indian Constitution',
                prefixIcon: Icon(Icons.psychology_rounded),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _go,
                style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
                child: const Text('Create AI Lesson'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayPlannerCard extends StatelessWidget {
  const _TodayPlannerCard({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DailyStudyPlan?>(
      stream: studentProgressRepository.watchDailyPlan(uid),
      builder: (context, snapshot) {
        final plan = snapshot.data;
        final remaining = plan?.remainingTasks.length ?? 0;
        final progress = plan?.progress ?? 0;
        final subtitle = snapshot.hasError
            ? 'Could not load the plan'
            : plan == null
                ? "Create today's personalized study plan"
                : remaining == 0
                    ? "Today's tasks complete"
                    : '$remaining tasks left · ${(progress * 100).round()}%';
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const StudyPlannerScreen(),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.sky.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.edit_calendar_rounded,
                      color: AppColors.sky,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Today's Study Plan",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.orange,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SyllabusProgressCard extends StatefulWidget {
  const _SyllabusProgressCard({required this.uid});

  final String uid;

  @override
  State<_SyllabusProgressCard> createState() => _SyllabusProgressCardState();
}

class _SyllabusProgressCardState extends State<_SyllabusProgressCard> {
  late final Stream<SyllabusProgressSnapshot> _stream =
      syllabusProgressTracker.watch(widget.uid);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyllabusProgressSnapshot>(
      stream: _stream,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final subtitle = snapshot.hasError
            ? 'Could not load progress'
            : data == null
                ? 'View syllabus progress'
                : !data.hasSyllabus
                    ? 'Progress will appear when subjects are published'
                    : '${data.completedTopics}/${data.totalTopics} topics · ${data.overallPercent.round()}%';
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SyllabusTrackerScreen(),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.checklist_rounded,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Syllabus Progress',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.orange,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WeaknessTrackerCard extends StatefulWidget {
  const _WeaknessTrackerCard({required this.uid});

  final String uid;

  @override
  State<_WeaknessTrackerCard> createState() => _WeaknessTrackerCardState();
}

class _WeaknessTrackerCardState extends State<_WeaknessTrackerCard> {
  late final Stream<WeaknessSnapshot> _stream =
      aiWeaknessTracker.watch(widget.uid);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WeaknessSnapshot>(
      stream: _stream,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final analysis = data?.analysis;
        final subtitle = snapshot.hasError
            ? 'Could not load analysis'
            : analysis == null || !analysis.hasPerformance
                ? 'Weak topics will appear after tests or quizzes'
                : analysis.priorityWeakAreas.isEmpty
                    ? 'No weak topics · accuracy ${analysis.overallAccuracy.round()}%'
                    : '${analysis.priorityWeakAreas.length} weak topics · ${analysis.overallAccuracy.round()}%';
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AiWeaknessTrackerScreen(),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.insights_rounded,
                      color: AppColors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI Weakness Tracker',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.orange,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniTitle extends StatelessWidget {
  const _MiniTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.sky,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
        ),
      ],
    );
  }
}

class _MiniActionCard extends StatelessWidget {
  const _MiniActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.navy, size: 22),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubjectProgressRow extends StatelessWidget {
  const _SubjectProgressRow({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final double value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 88,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: value.clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                  color: AppColors.orange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
