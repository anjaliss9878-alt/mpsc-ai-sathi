import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/bookmark_item.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/screens/mcq_set_screen.dart';
import 'package:mpsc_combine_ai/screens/notes_detail_screen.dart';
import 'package:mpsc_combine_ai/screens/subject_notes_screen.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  Future<void> _open(BuildContext context, BookmarkItem item) async {
    if (item.type == 'mcq') {
      final all = await mcqRepository.watchPublished().first;
      McqItem? match;
      for (final q in all) {
        if (q.id == item.refId) {
          match = q;
          break;
        }
      }
      if (!context.mounted) return;
      if (match == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bookmarked MCQ is no longer available.')),
        );
        return;
      }
      final setQs = all.where((q) => q.setTitle == match!.setTitle).toList();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => McqSetScreen(
            setTitle: match!.setTitle,
            questions: setQs.isEmpty ? [match] : setQs,
          ),
        ),
      );
      return;
    }

    if (item.type == 'note' || item.type == 'chapter') {
      final chapter = await notesRepository.getChapter(item.refId);
      if (!context.mounted) return;
      if (chapter == null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SubjectNotesScreen()),
        );
        return;
      }
      final subject = await notesRepository.getSubject(chapter.subjectId);
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NotesDetailScreen(
            subjectTitle: subject?.title ?? item.subtitle,
            chapter: chapter,
            topicNumber: chapter.order > 0 ? chapter.order : 1,
          ),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SubjectNotesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = authService.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: uid == null
          ? const Center(child: Text('Sign in to sync bookmarks.'))
          : StreamBuilder<List<BookmarkItem>>(
              stream: studentProgressRepository.watchBookmarks(uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorState(message: 'Could not load bookmarks.\n${snapshot.error}');
                }
                if (!snapshot.hasData) return const LoadingState();
                final items = snapshot.data!;
                if (items.isEmpty) {
                  return const EmptyState(
                    message: 'No bookmarks yet.\nBookmark notes or MCQs while studying.',
                    icon: Icons.bookmark_border_rounded,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final b = items[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          b.type == 'mcq'
                              ? Icons.quiz_rounded
                              : Icons.bookmark_rounded,
                          color: AppColors.navy,
                        ),
                        title: Text(
                          b.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(b.subtitle),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _open(context, b),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
