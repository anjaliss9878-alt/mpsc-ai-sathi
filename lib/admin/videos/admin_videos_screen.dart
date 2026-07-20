import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/videos/admin_video_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/video_item.dart';
import 'package:mpsc_combine_ai/services/video_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminVideosScreen extends StatelessWidget {
  const AdminVideosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Videos',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AdminVideoFormScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<VideoItem>>(
        stream: videoRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load videos: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const EmptyState(
              message: 'No videos yet. Tap + to add the first video link.',
              icon: Icons.smart_display_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return AdminListTile(
                title: item.title,
                subtitle: item.subject,
                icon: Icons.play_circle_fill_rounded,
                onEdit: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminVideoFormScreen(existing: item),
                  ),
                ),
                onDelete: () async {
                  final confirmed = await confirmDelete(context, item.title);
                  if (!confirmed) return;
                  try {
                    await videoRepository.delete(item.id);
                    if (context.mounted) showAdminMessage(context, 'Video deleted.');
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
