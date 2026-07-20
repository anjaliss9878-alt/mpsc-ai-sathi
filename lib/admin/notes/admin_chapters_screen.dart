import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_chapter_form_screen.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_note_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminChaptersScreen extends StatelessWidget {
  const AdminChaptersScreen({super.key, required this.subject});

  final SubjectItem subject;

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: '${subject.title} — Chapters',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AdminChapterFormScreen(subjectId: subject.id),
          ),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<ChapterItem>>(
        stream: notesRepository.watchChapters(subject.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load chapters: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final chapters = snapshot.data!;
          if (chapters.isEmpty) {
            return const EmptyState(
              message: 'No chapters yet. Tap + to add the first chapter.',
              icon: Icons.menu_book_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: chapters.length,
            itemBuilder: (context, index) {
              final chapter = chapters[index];
              return AdminListTile(
                title: chapter.title,
                subtitle: 'Chapter ${index + 1} · tap to edit notes',
                icon: Icons.menu_book_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminNoteFormScreen(
                      subjectId: subject.id,
                      chapter: chapter,
                    ),
                  ),
                ),
                onEdit: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminChapterFormScreen(
                      subjectId: subject.id,
                      existing: chapter,
                    ),
                  ),
                ),
                onDelete: () async {
                  final confirmed = await confirmDelete(context, chapter.title);
                  if (!confirmed) return;
                  try {
                    await notesRepository.deleteChapter(chapter.id);
                    if (context.mounted) showAdminMessage(context, 'Chapter deleted.');
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
