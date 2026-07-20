import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/current_affairs/admin_current_affair_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/current_affair_item.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/utils/date_format.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminCurrentAffairsScreen extends StatelessWidget {
  const AdminCurrentAffairsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Current Affairs',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const AdminCurrentAffairFormScreen(),
          ),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<CurrentAffairItem>>(
        stream: currentAffairsRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load entries: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const EmptyState(
              message: 'No current affairs yet. Tap + to add the first entry.',
              icon: Icons.newspaper_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return AdminListTile(
                title: item.title,
                subtitle: '${formatShortDate(item.date)} · ${item.category}',
                icon: Icons.today_rounded,
                onEdit: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminCurrentAffairFormScreen(existing: item),
                  ),
                ),
                onDelete: () async {
                  final confirmed = await confirmDelete(context, item.title);
                  if (!confirmed) return;
                  try {
                    await currentAffairsRepository.delete(item.id);
                    if (context.mounted) showAdminMessage(context, 'Entry deleted.');
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
