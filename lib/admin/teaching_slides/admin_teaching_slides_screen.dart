import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/teaching_slides/admin_teaching_slide_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/teaching_slide_deck_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/storage_service.dart';
import 'package:mpsc_combine_ai/services/teaching_slide_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';
import 'package:mpsc_combine_ai/widgets/teaching_slide_viewer.dart';

class AdminTeachingSlidesScreen extends StatelessWidget {
  const AdminTeachingSlidesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Teaching Slides',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AdminTeachingSlideFormScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<TeachingSlideDeckItem>>(
        stream: teachingSlideRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load slide decks: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const EmptyState(
              message: 'No slide decks yet. Tap + to upload the first one.',
              icon: Icons.slideshow_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return AdminListTile(
                title: item.title,
                subtitle: '${item.slides.length} slides',
                icon: Icons.slideshow_rounded,
                onTap: () => showTeachingSlideViewer(context, title: item.title, slides: item.slides),
                onEdit: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminTeachingSlideFormScreen(existing: item),
                  ),
                ),
                onDelete: () async {
                  final confirmed = await confirmDelete(context, item.title);
                  if (!confirmed) return;
                  try {
                    await teachingSlideRepository.delete(item.id);
                    for (final slide in item.slides) {
                      await storageService.deleteByUrl(slide.url);
                    }
                    await auditLogRepository.log(
                      action: 'delete',
                      module: 'Teaching Slides',
                      targetLabel: item.title,
                    );
                    if (context.mounted) showAdminMessage(context, 'Slide deck deleted.');
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
