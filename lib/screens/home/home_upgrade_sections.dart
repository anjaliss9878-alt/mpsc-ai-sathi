import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/ai_lesson.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/ai_teacher_classroom_screen.dart';
import 'package:mpsc_combine_ai/screens/mcq_practice_screen.dart';
import 'package:mpsc_combine_ai/screens/revision/revision_hub_screen.dart';
import 'package:mpsc_combine_ai/screens/topic_list_screen.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_repository.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_progress_repository.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
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
          child: const _MiniTitle('AI शिक्षक'),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 10, horizontalPadding, 0),
          child: _AiTeacherSearchCard(),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 0),
          child: const _MiniTitle('आजचा सराव'),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 10, horizontalPadding, 0),
          child: Row(
            children: [
              Expanded(
                child: _MiniActionCard(
                  icon: Icons.quiz_rounded,
                  title: 'दैनिक MCQ',
                  subtitle: 'आजचे प्रश्न सोडवा',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const McqPracticeScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniActionCard(
                  icon: Icons.style_rounded,
                  title: 'पुनरावृत्ती',
                  subtitle: 'आजची आठवण',
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
        if (uid != null) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 0),
            child: const _MiniTitle('अलीकडील AI धडे'),
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
                      'अजून AI धडा नाही. विषय लिहून सुरू करा.',
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
            child: const _MiniTitle('विषयनिहाय प्रगती'),
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
              'कोणताही विषय लिहा — एका क्लिकमध्ये पूर्ण धडा',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _go(),
              decoration: const InputDecoration(
                hintText: 'उदा. गंगा नदी, महाराष्ट्रातील मृदा, संसद, मान्सून, भारतीय राज्यघटना',
                prefixIcon: Icon(Icons.psychology_rounded),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _go,
                style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
                child: const Text('AI Lesson तयार करा'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniTitle extends StatelessWidget {
  const _MiniTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
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
