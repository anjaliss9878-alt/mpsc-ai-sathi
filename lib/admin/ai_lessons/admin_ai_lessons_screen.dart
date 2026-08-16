import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/ai_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_asset_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_queue.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_repository.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminAiLessonsScreen extends StatefulWidget {
  const AdminAiLessonsScreen({super.key});

  @override
  State<AdminAiLessonsScreen> createState() => _AdminAiLessonsScreenState();
}

class _AdminAiLessonsScreenState extends State<AdminAiLessonsScreen> {
  final _topic = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final topic = _topic.text.trim();
    final uid = authService.currentUser?.uid;
    if (topic.isEmpty || uid == null || _busy) return;
    setState(() => _busy = true);
    try {
      final id = await aiLessonRepository.enqueue(
        uid: uid,
        topic: topic,
        forceRegenerate: true,
      );
      aiLessonQueue.submit(id);
      await auditLogRepository.log(
        action: 'create',
        module: 'AI Lessons',
        targetLabel: topic,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lesson queued.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not queue lesson.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _regenerate(AiLesson lesson, {required bool voiceOnly}) async {
    final uid = lesson.uid.isNotEmpty
        ? lesson.uid
        : authService.currentUser?.uid;
    if (uid == null) return;
    try {
      final id = await aiLessonRepository.enqueue(
        uid: uid,
        topic: lesson.topic,
        chapterId: lesson.chapterId,
        subjectId: lesson.subjectId,
        subjectTitle: lesson.subjectTitle,
        forceRegenerate: true,
      );
      aiLessonQueue.submit(id);
      await auditLogRepository.log(
        action: 'update',
        module: 'AI Lessons',
        targetLabel: '${voiceOnly ? 'Voice' : 'Video'} · ${lesson.topic}',
      );
    } catch (_) {}
  }

  Future<void> _delete(AiLesson lesson) async {
    final ok = await confirmDelete(context, lesson.topic);
    if (!ok) return;
    try {
      await aiLessonAssetService.deletePath(lesson.audioUrl);
      await aiLessonAssetService.deletePath(lesson.videoUrl);
      await aiLessonAssetService.deletePath(lesson.thumbnailUrl);
      await aiLessonRepository.delete(lesson.id);
      await auditLogRepository.log(
        action: 'delete',
        module: 'AI Lessons',
        targetLabel: lesson.topic,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete assets.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'AI Classroom Lessons',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _topic,
                    decoration: const InputDecoration(
                      hintText: 'Topic (e.g. संसद)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _generate,
                  icon: const Icon(Icons.movie_creation_outlined),
                  label: const Text('Generate AI Lesson'),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<AiLesson>>(
              stream: aiLessonRepository.watchAll(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorState(message: 'Could not load lessons.');
                }
                if (!snapshot.hasData) return const LoadingState();
                final items = snapshot.data!;
                if (items.isEmpty) {
                  return const EmptyState(
                    message: 'No generated lessons yet.',
                    icon: Icons.smart_display_outlined,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ExpansionTile(
                        leading: Icon(
                          item.isReady
                              ? Icons.check_circle_rounded
                              : item.isFailed
                                  ? Icons.error_outline_rounded
                                  : Icons.hourglass_top_rounded,
                          color: item.isReady
                              ? Colors.green
                              : item.isFailed
                                  ? Colors.redAccent
                                  : AppColors.orange,
                        ),
                        title: Text(
                          item.topic,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${item.status.wire} · ${item.progress}% · ${item.stage.labelEn}',
                        ),
                        children: [
                          LinearProgressIndicator(
                            value: (item.progress / 100).clamp(0.05, 1),
                            color: AppColors.orange,
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.friendlyMessage.isEmpty
                                    ? item.stage.labelEn
                                    : item.friendlyMessage),
                                const SizedBox(height: 8),
                                const Text(
                                  'Generation logs',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                for (final log in item.logs.reversed.take(12))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '${log.stage}: ${log.message}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    OutlinedButton(
                                      onPressed: () =>
                                          _regenerate(item, voiceOnly: true),
                                      child: const Text('Regenerate Voice'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () =>
                                          _regenerate(item, voiceOnly: false),
                                      child: const Text('Regenerate Video'),
                                    ),
                                    TextButton(
                                      onPressed: () => _delete(item),
                                      child: const Text('Delete assets'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
