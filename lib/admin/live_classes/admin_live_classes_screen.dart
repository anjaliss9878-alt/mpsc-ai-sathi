import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/live_classes/admin_live_class_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/live_class_item.dart';
import 'package:mpsc_combine_ai/services/live_class_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminLiveClassesScreen extends StatelessWidget {
  const AdminLiveClassesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Live Classes',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AdminLiveClassFormScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<LiveClassItem>>(
        stream: liveClassRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load live classes: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const EmptyState(
              message: 'No live classes yet. Tap + to schedule the first one.',
              icon: Icons.live_tv_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return AdminListTile(
                title: item.title,
                subtitle: '${item.status.toUpperCase()} · ${item.subject} · ${item.scheduleText}',
                icon: Icons.live_tv_rounded,
                onEdit: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminLiveClassFormScreen(existing: item),
                  ),
                ),
                onDelete: () async {
                  final confirmed = await confirmDelete(context, item.title);
                  if (!confirmed) return;
                  try {
                    await liveClassRepository.delete(item.id);
                    if (context.mounted) showAdminMessage(context, 'Live class deleted.');
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
