import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/pyqs/admin_pyq_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminPyqsScreen extends StatelessWidget {
  const AdminPyqsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Previous Year Questions',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AdminPyqFormScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<PyqItem>>(
        stream: pyqRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load PYQs: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const EmptyState(
              message: 'No question papers yet. Tap + to add the first one.',
              icon: Icons.history_edu_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return AdminListTile(
                title: item.title,
                subtitle: item.subtitle,
                icon: Icons.description_rounded,
                onEdit: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminPyqFormScreen(existing: item),
                  ),
                ),
                onDelete: () async {
                  final confirmed = await confirmDelete(context, item.title);
                  if (!confirmed) return;
                  try {
                    await pyqRepository.delete(item.id);
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
