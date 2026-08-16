import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_chapter_form_screen.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_note_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Admin Topics list for one Subject (Firestore `chapters` collection).
class AdminChaptersScreen extends StatefulWidget {
  const AdminChaptersScreen({super.key, required this.subject});

  final SubjectItem subject;

  @override
  State<AdminChaptersScreen> createState() => _AdminChaptersScreenState();
}

class _AdminChaptersScreenState extends State<AdminChaptersScreen> {
  String _query = '';

  List<ChapterItem> _filter(List<ChapterItem> chapters) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return chapters;
    return chapters.where((c) {
      return c.title.toLowerCase().contains(q) ||
          c.titleEn.toLowerCase().contains(q) ||
          c.description.toLowerCase().contains(q) ||
          c.slug.toLowerCase().contains(q) ||
          c.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    return AdminScaffold(
      title: '${subject.title} — Topics',
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
            return ErrorState(message: 'Could not load topics: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final all = snapshot.data!;
          final chapters = _filter(all);
          if (all.isEmpty) {
            return const EmptyState(
              message: 'No topics yet. Tap + to add the first topic '
                  '(e.g. प्रस्तावना, मूलभूत हक्क, संसद).',
              icon: Icons.menu_book_outlined,
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search topics…',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tap a topic to edit title/PDF/notes. Drag ☰ to reorder.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ),
              Expanded(
                child: chapters.isEmpty
                    ? const EmptyState(
                        message: 'No topics match your search.',
                        icon: Icons.search_off_rounded,
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: chapters.length,
                        onReorder: (oldIndex, newIndex) async {
                          if (_query.trim().isNotEmpty) {
                            showAdminMessage(
                              context,
                              'Clear search before reordering topics.',
                            );
                            return;
                          }
                          final reordered = List.of(chapters);
                          if (newIndex > oldIndex) newIndex -= 1;
                          final moved = reordered.removeAt(oldIndex);
                          reordered.insert(newIndex, moved);
                          try {
                            for (var i = 0; i < reordered.length; i++) {
                              if (reordered[i].order != i) {
                                await notesRepository
                                    .updateChapter(reordered[i].copyWith(order: i));
                              }
                            }
                          } catch (e) {
                            if (context.mounted) showAdminError(context, e);
                          }
                        },
                        itemBuilder: (context, index) {
                          final chapter = chapters[index];
                          final minutes = chapter.estimatedStudyMinutes;
                          return AdminListTile(
                            key: ValueKey(chapter.id),
                            title: chapter.title,
                            subtitle:
                                '${chapter.published ? 'Published' : 'Draft'} · '
                                'id=${chapter.id}'
                                '${minutes > 0 ? ' · ~$minutes min' : ''} · tap notes / edit',
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
                                await auditLogRepository.log(
                                  action: 'delete',
                                  module: 'Topics',
                                  targetLabel: chapter.title,
                                );
                                if (context.mounted) {
                                  showAdminMessage(context, 'Topic deleted.');
                                }
                              } catch (e) {
                                if (context.mounted) showAdminError(context, e);
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
