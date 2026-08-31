import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_chapter_form_screen.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_topics_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/content_knowledge_indexer.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Admin Chapters list for one Subject (Firestore `chapters` collection).
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
      title: '${subject.title} — Chapters',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AdminChapterFormScreen(
              subjectId: subject.id,
              examId: subject.examId,
              nodeType: contentNodeTypeToString(ContentNodeType.chapter),
            ),
          ),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<ChapterItem>>(
        stream: notesRepository.watchRootChapters(subject.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load chapters: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final all = snapshot.data!;
          final chapters = _filter(all);
          if (all.isEmpty) {
            return const EmptyState(
              message: 'No chapters yet. Tap + to add the first chapter '
                  '(e.g. Indian Constitution).',
              icon: Icons.menu_book_outlined,
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search chapters…',
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
                    'Tap a chapter to manage Topics. Drag ☰ to reorder.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ),
              Expanded(
                child: chapters.isEmpty
                    ? const EmptyState(
                        message: 'No chapters match your search.',
                        icon: Icons.search_off_rounded,
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: chapters.length,
                        onReorder: (oldIndex, newIndex) async {
                          if (_query.trim().isNotEmpty) {
                            showAdminMessage(
                              context,
                              'Clear search before reordering chapters.',
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
                          return AdminListTile(
                            key: ValueKey(chapter.id),
                            title: chapter.title,
                            subtitle:
                                '${chapter.published ? 'Active' : 'Inactive'} · '
                                'id=${chapter.id}'
                                '${chapter.slug.isNotEmpty ? ' · ${chapter.slug}' : ''}',
                            icon: Icons.folder_rounded,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AdminTopicsScreen(
                                  subject: subject,
                                  chapter: chapter,
                                ),
                              ),
                            ),
                            onEdit: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AdminChapterFormScreen(
                                  subjectId: subject.id,
                                  examId: subject.examId,
                                  nodeType: chapter.nodeType.isNotEmpty
                                      ? chapter.nodeType
                                      : contentNodeTypeToString(
                                          ContentNodeType.chapter,
                                        ),
                                  existing: chapter,
                                ),
                              ),
                            ),
                            onDelete: () async {
                              final confirmed =
                                  await confirmDelete(context, chapter.title);
                              if (!confirmed) return;
                              try {
                                await notesRepository.deleteChapter(chapter.id);
                                try {
                                  await contentKnowledgeIndexer
                                      .removeSyllabusNode(chapter.id);
                                } catch (_) {}
                                await auditLogRepository.log(
                                  action: 'delete',
                                  module: 'Chapters',
                                  targetLabel: chapter.title,
                                );
                                if (context.mounted) {
                                  showAdminMessage(context, 'Chapter deleted.');
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
