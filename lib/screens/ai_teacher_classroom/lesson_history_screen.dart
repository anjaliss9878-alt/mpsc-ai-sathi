import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_history_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/date_format.dart';

/// Lists past AI Teacher lessons saved to Firebase for this student —
/// architecture step: "Save lesson history in Firebase", made visible and
/// usable rather than just a silent write. Tapping a past lesson loads it
/// back into the classroom screen.
class LessonHistoryScreen extends StatelessWidget {
  const LessonHistoryScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Lesson History', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: StreamBuilder<List<GeneratedLesson>>(
          stream: lessonHistoryRepository.watchHistory(uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Could not load lesson history.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              );
            }
            final lessons = snapshot.data ?? const [];
            if (lessons.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No lessons yet. Ask your AI Teacher a question to generate your first lesson — it will be saved here automatically.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: lessons.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final lesson = lessons[i];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.navy,
                      child: Icon(Icons.school_rounded, color: Colors.white, size: 20),
                    ),
                    title: Text(
                      lesson.topicName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${lesson.subjectName} · ${formatFriendlyDateTime(lesson.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).pop(lesson),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
