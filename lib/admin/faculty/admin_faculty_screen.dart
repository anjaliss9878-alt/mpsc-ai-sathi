import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/faculty/admin_faculty_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/faculty_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/faculty_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminFacultyScreen extends StatelessWidget {
  const AdminFacultyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Faculty',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AdminFacultyFormScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<FacultyItem>>(
        stream: facultyRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load faculty: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const EmptyState(
              message: 'No faculty yet. Tap + to add the first one.',
              icon: Icons.person_outline_rounded,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return AdminListTile(
                title: item.name,
                subtitle: [
                  item.designation,
                  item.subject,
                ].where((s) => s.isNotEmpty).join(' · '),
                icon: Icons.person_rounded,
                onEdit: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminFacultyFormScreen(existing: item),
                  ),
                ),
                onDelete: () async {
                  final confirmed = await confirmDelete(context, item.name);
                  if (!confirmed) return;
                  try {
                    await facultyRepository.delete(item.id);
                    await auditLogRepository.log(action: 'delete', module: 'Faculty', targetLabel: item.name);
                    if (context.mounted) showAdminMessage(context, 'Faculty deleted.');
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
