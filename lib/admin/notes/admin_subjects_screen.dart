import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_chapters_screen.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_subject_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminSubjectsScreen extends StatelessWidget {
  const AdminSubjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Notes — Subjects',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AdminSubjectFormScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<SubjectItem>>(
        stream: notesRepository.watchSubjects(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load subjects: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final subjects = snapshot.data!;
          if (subjects.isEmpty) {
            return const EmptyState(
              message: 'No subjects yet. Tap + to add the first subject '
                  '(e.g. Polity, Economy, Geography).',
              icon: Icons.library_books_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: subjects.length,
            itemBuilder: (context, index) {
              final subject = subjects[index];
              return AdminListTile(
                title: subject.title,
                subtitle: subject.subtitle,
                icon: subject.icon,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminChaptersScreen(subject: subject),
                  ),
                ),
                onEdit: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminSubjectFormScreen(existing: subject),
                  ),
                ),
                onDelete: () async {
                  final confirmed = await confirmDelete(context, subject.title);
                  if (!confirmed) return;
                  try {
                    await notesRepository.deleteSubject(subject.id);
                    if (context.mounted) {
                      showAdminMessage(context, 'Subject deleted.');
                    }
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
