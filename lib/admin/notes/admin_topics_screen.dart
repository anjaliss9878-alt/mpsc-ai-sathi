import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_chapter_form_screen.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_note_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/content_counts_service.dart';
import 'package:mpsc_combine_ai/services/content_knowledge_indexer.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Topics under one chapter. Same `chapters` collection, `parentChapterId` set.
class AdminTopicsScreen extends StatefulWidget {
  const AdminTopicsScreen({
    super.key,
    required this.subject,
    required this.chapter,
  });

  final SubjectItem subject;
  final ChapterItem chapter;

  @override
  State<AdminTopicsScreen> createState() => _AdminTopicsScreenState();
}

class _AdminTopicsScreenState extends State<AdminTopicsScreen> {
  String _query = '';
  final _counts = <String, TopicContentCounts>{};

  List<ChapterItem> _filter(List<ChapterItem> topics) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return topics;
    return topics.where((c) {
      return c.title.toLowerCase().contains(q) ||
          c.titleEn.toLowerCase().contains(q) ||
          c.slug.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _loadCounts(List<ChapterItem> topics) async {
    for (final topic in topics) {
      if (_counts.containsKey(topic.id)) continue;
      try {
        final counts = await contentCountsService.forTopic(
          topicId: topic.id,
          topicTitle: topic.title,
        );
        if (!mounted) return;
        setState(() => _counts[topic.id] = counts);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    final chapter = widget.chapter;
    return AdminScaffold(
      title: '${chapter.title} — Topics',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AdminChapterFormScreen(
              subjectId: subject.id,
              examId: subject.examId,
              parentChapterId: chapter.id,
              nodeType: contentNodeTypeToString(ContentNodeType.topic),
            ),
          ),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<ChapterItem>>(
        stream: notesRepository.watchChildChapters(chapter.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load topics: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final all = snapshot.data!;
          final topics = _filter(all);
          if (all.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadCounts(all);
            });
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    all.isEmpty
                        ? 'No topics yet. Tap + to add one (e.g. Fundamental Rights). '
                            'You can still attach a Note to this chapter from Content → Notes.'
                        : 'Tap a topic to edit its PDF notes. Drag ☰ to reorder. Eye toggles Active.',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ),
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AdminNoteFormScreen(
                          subjectId: subject.id,
                          subjectTitle: subject.title,
                          chapter: chapter,
                          examId: subject.examId,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('Notes for this chapter'),
                  ),
                ),
              Expanded(
                child: all.isEmpty
                    ? const EmptyState(
                        message: 'Add the first topic, or open chapter notes.',
                        icon: Icons.topic_outlined,
                      )
                    : topics.isEmpty
                        ? const EmptyState(
                            message: 'No topics match your search.',
                            icon: Icons.search_off_rounded,
                          )
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: topics.length,
                            onReorder: (oldIndex, newIndex) async {
                              if (_query.trim().isNotEmpty) {
                                showAdminMessage(
                                  context,
                                  'Clear search before reordering topics.',
                                );
                                return;
                              }
                              final reordered = List.of(topics);
                              if (newIndex > oldIndex) newIndex -= 1;
                              final moved = reordered.removeAt(oldIndex);
                              reordered.insert(newIndex, moved);
                              try {
                                for (var i = 0; i < reordered.length; i++) {
                                  if (reordered[i].order != i) {
                                    await notesRepository.updateChapter(
                                      reordered[i].copyWith(order: i),
                                    );
                                  }
                                }
                              } catch (e) {
                                if (context.mounted) showAdminError(context, e);
                              }
                            },
                            itemBuilder: (context, index) {
                              final topic = topics[index];
                              final counts = _counts[topic.id];
                              return AdminListTile(
                                key: ValueKey(topic.id),
                                title: topic.title,
                                subtitle:
                                    '${topic.published ? 'Active' : 'Inactive'} · '
                                    '${counts?.compactLabel ?? 'Counting…'}',
                                icon: Icons.topic_outlined,
                                isActive: topic.published,
                                onToggleActive: () async {
                                  try {
                                    final next = topic.copyWith(
                                      published: !topic.published,
                                    );
                                    await notesRepository.updateChapter(next);
                                    try {
                                      await contentKnowledgeIndexer
                                          .syncSyllabus(next);
                                    } catch (_) {}
                                  } catch (e) {
                                    if (context.mounted) {
                                      showAdminError(context, e);
                                    }
                                  }
                                },
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => AdminNoteFormScreen(
                                      subjectId: subject.id,
                                      subjectTitle: subject.title,
                                      chapter: topic,
                                      parentChapter: chapter,
                                      examId: subject.examId,
                                    ),
                                  ),
                                ),
                                onEdit: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => AdminChapterFormScreen(
                                      subjectId: subject.id,
                                      examId: subject.examId,
                                      parentChapterId: chapter.id,
                                      nodeType: contentNodeTypeToString(
                                        ContentNodeType.topic,
                                      ),
                                      existing: topic,
                                    ),
                                  ),
                                ),
                                onDelete: () async {
                                  final confirmed =
                                      await confirmDelete(context, topic.title);
                                  if (!confirmed) return;
                                  try {
                                    await notesRepository.deleteChapter(topic.id);
                                    try {
                                      await contentKnowledgeIndexer
                                          .removeSyllabusNode(topic.id);
                                    } catch (_) {}
                                    await auditLogRepository.log(
                                      action: 'delete',
                                      module: 'Topics',
                                      targetLabel: topic.title,
                                    );
                                    if (context.mounted) {
                                      showAdminMessage(context, 'Topic deleted.');
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      showAdminError(context, e);
                                    }
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
