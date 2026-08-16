import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/ai_teacher_content/admin_ai_teacher_content_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/ai_teacher_content_item.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_content_repository.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Admin CRUD for lessons the AI Teacher Classroom can play back instantly
/// (matched by keyword) instead of always calling Gemini live.
class AdminAiTeacherContentScreen extends StatelessWidget {
  const AdminAiTeacherContentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'AI Teacher Content',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AdminAiTeacherContentFormScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<AiTeacherContentItem>>(
        stream: aiTeacherContentRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load lessons: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const EmptyState(
              message: 'No authored lessons yet. Tap + to write the first one — '
                  'the AI Teacher will use it instantly whenever a student '
                  'asks a matching question.',
              icon: Icons.smart_toy_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return AdminListTile(
                title: item.lessonTitle,
                subtitle: 'Keywords: ${item.keywords.join(', ')}',
                icon: Icons.smart_toy_rounded,
                onEdit: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminAiTeacherContentFormScreen(existing: item),
                  ),
                ),
                onDelete: () async {
                  final confirmed = await confirmDelete(context, item.lessonTitle);
                  if (!confirmed) return;
                  try {
                    await aiTeacherContentRepository.delete(item.id);
                    await auditLogRepository.log(
                      action: 'delete',
                      module: 'AI Teacher Content',
                      targetLabel: item.lessonTitle,
                    );
                    if (context.mounted) showAdminMessage(context, 'Lesson deleted.');
                  } catch (e) {
                    if (context.mounted) showAdminError(context, e);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
