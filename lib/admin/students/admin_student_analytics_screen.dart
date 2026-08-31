import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/daily_study_plan.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/models/ai_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_repository.dart';
import 'package:mpsc_combine_ai/services/ai_weakness_tracker.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Admin analytics for one student. Reads the SAME Firestore documents and
/// services the student app uses — no second planner or weakness engine.
class AdminStudentAnalyticsScreen extends StatelessWidget {
  const AdminStudentAnalyticsScreen({super.key, required this.student});

  final StudentProfile student;

  @override
  Widget build(BuildContext context) {
    final name = student.name.isEmpty ? student.email : student.name;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: AppColors.sky,
            tabs: [
              Tab(text: 'Planner'),
              Tab(text: 'Weakness'),
              Tab(text: 'Performance'),
              Tab(text: 'Syllabus'),
              Tab(text: 'AI Teacher'),
            ],
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: TabBarView(
                children: [
                  _PlannerTab(uid: student.uid, profile: student),
                  _WeaknessTab(uid: student.uid),
                  _PerformanceTab(uid: student.uid),
                  _SyllabusTab(uid: student.uid),
                  _AiTeacherTab(uid: student.uid),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlannerTab extends StatelessWidget {
  const _PlannerTab({required this.uid, required this.profile});

  final String uid;
  final StudentProfile profile;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DailyStudyPlan>>(
      stream: studentProgressRepository.watchDailyPlans(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorState(
            message: 'Could not load study plans.\n${snapshot.error}',
          );
        }
        if (!snapshot.hasData) return const LoadingState();
        final plans = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Same daily plans the student app stores at '
              'students/$uid/studyPlans. Not a second planner.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Target: ${profile.targetExam.isEmpty ? '—' : profile.targetExam}'
              '${profile.examDate.isEmpty ? '' : ' · Exam ${profile.examDate}'}'
              ' · ${profile.dailyStudyHours} h/day',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (plans.isEmpty)
              const EmptyState(
                icon: Icons.event_note_outlined,
                message: 'No daily plans yet. They appear after the student generates a plan.',
              )
            else
              for (final plan in plans)
                Card(
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
                          title: Text(
                            '${task.typeLabel}: ${task.topic}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${task.subject} · ${task.durationMinutes} min · '
                            '${task.priorityLabel} · ${task.status.name}'
                            '${task.reason.isEmpty ? '' : ' · ${task.reason}'}',
                          ),
                        ),
                    ],
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _WeaknessTab extends StatelessWidget {
  const _WeaknessTab({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WeaknessSnapshot>(
      stream: aiWeaknessTracker.watch(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorState(
            message: 'Could not load weakness analysis.\n${snapshot.error}',
          );
        }
        if (!snapshot.hasData) return const LoadingState();
        final data = snapshot.data!;
        final analysis = data.analysis;
        if (analysis == null || !analysis.hasPerformance) {
          return const EmptyState(
            icon: Icons.insights_outlined,
            message:
                'No performance data yet. Completing a test, classroom quiz, or MCQ set in the student app updates this view.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Same AiWeaknessTracker output the student app uses. No separate calculation.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: Text(
                  'Accuracy ${analysis.overallAccuracy.round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'Questions ${analysis.overallAttempted} · '
                  'Correct ${analysis.overallCorrect} · '
                  'Wrong ${analysis.overallWrong} · '
                  'Trend ${analysis.overallTrend.label}',
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Topics',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final topic in analysis.topics)
              Card(
                child: ListTile(
                  title: Text(
                    topic.subjectTitle.isEmpty
                        ? topic.label
                        : '${topic.subjectTitle} → ${topic.label}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${topic.band.label} · ${topic.accuracyPercent.round()}% · '
                    'Attempts ${topic.attempted} · '
                    'Correct ${topic.correct} / Wrong ${topic.wrong} · '
                    'Trend ${topic.trend.label} · '
                    'Priority ${topic.band.priorityLabel}'
                    '${topic.actions.isEmpty ? '' : '\n${topic.actions.first.label}'}',
                  ),
                  isThreeLine: topic.actions.isNotEmpty,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PerformanceTab extends StatelessWidget {
  const _PerformanceTab({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PersistedTestAttempt>>(
      stream: studentProgressRepository.watchTestAttempts(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorState(
            message: 'Could not load attempts.\n${snapshot.error}',
          );
        }
        if (!snapshot.hasData) return const LoadingState();
        final attempts = snapshot.data!;
        if (attempts.isEmpty) {
          return const EmptyState(
            icon: Icons.quiz_outlined,
            message:
                'No saved attempts yet. Student test and MCQ results appear here from students/{uid}/testAttempts.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Same testAttempts documents the student app writes.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            for (final a in attempts)
              Card(
                child: ListTile(
                  title: Text(
                    a.testTitle,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${a.kind.isEmpty ? 'test' : a.kind} · '
                    '${a.percentage.toStringAsFixed(0)}% · '
                    'Correct ${a.correct} / Wrong ${a.wrong} · '
                    'Attempted ${a.attempted}/${a.totalQuestions}',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SyllabusTab extends StatelessWidget {
  const _SyllabusTab({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyllabusProgressSnapshot>(
      stream: syllabusProgressTracker.watch(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorState(
            message: 'Could not load syllabus progress.\n${snapshot.error}',
          );
        }
        if (!snapshot.hasData) return const LoadingState();
        final data = snapshot.data!;
        if (!data.hasSyllabus) {
          return const EmptyState(
            icon: Icons.checklist_outlined,
            message: 'No published syllabus topics yet.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${data.completedTopics}/${data.totalTopics} topics complete · '
              '${data.overallPercent.round()}%',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final subject in data.subjects)
              Card(
                child: ExpansionTile(
                  title: Text(subject.subject.title),
                  subtitle: Text(
                    '${subject.completedTopics}/${subject.totalTopics} · '
                    '${subject.percent.round()}%',
                  ),
                  children: [
                    for (final topic in subject.topics)
                      ListTile(
                        dense: true,
                        title: Text(topic.chapterTitle),
                        subtitle: Text(
                          '${topic.status.name} · '
                          '${topic.studyMinutes} min study · '
                          '${topic.revisionCount} revisions',
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AiTeacherTab extends StatelessWidget {
  const _AiTeacherTab({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AiLesson>>(
      stream: aiLessonRepository.watchMine(uid, limit: 40),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorState(
            message: 'Could not load AI Teacher lessons.\n${snapshot.error}',
          );
        }
        if (!snapshot.hasData) return const LoadingState();
        final lessons = snapshot.data!;
        final topics = <String, int>{};
        for (final lesson in lessons) {
          final key = lesson.topic.trim();
          if (key.isEmpty) continue;
          topics[key] = (topics[key] ?? 0) + 1;
        }
        final frequent = topics.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Existing ai_lessons documents for this student. The AI Teacher engine is not modified.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              '${lessons.length} lesson record${lessons.length == 1 ? '' : 's'}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (frequent.isNotEmpty) ...[
              const Text(
                'Frequently requested topics',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              for (final e in frequent.take(8))
                ListTile(
                  dense: true,
                  title: Text(e.key),
                  trailing: Text('${e.value}'),
                ),
            ],
            const SizedBox(height: 8),
            if (lessons.isEmpty)
              const EmptyState(
                icon: Icons.psychology_outlined,
                message: 'No AI Teacher classroom lessons for this student yet.',
              )
            else
              for (final lesson in lessons)
                Card(
                  child: ListTile(
                    title: Text(lesson.topic),
                    subtitle: Text(
                      '${lesson.status.name}'
                      '${lesson.subjectTitle.isEmpty ? '' : ' · ${lesson.subjectTitle}'}'
                      '${lesson.errorMessage.isEmpty ? '' : ' · ${lesson.friendlyMessage.isNotEmpty ? lesson.friendlyMessage : 'failed'}'}',
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
