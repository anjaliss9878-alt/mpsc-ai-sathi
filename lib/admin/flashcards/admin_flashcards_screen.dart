import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/admin_flashcard_bulk_upload_screen.dart';
import 'package:mpsc_combine_ai/admin/flashcards/admin_ai_flashcard_generate_screen.dart';
import 'package:mpsc_combine_ai/admin/flashcards/admin_flashcard_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_content_filter_bar.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_preview.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/flashcard_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/content_knowledge_indexer.dart';
import 'package:mpsc_combine_ai/services/flashcard_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminFlashcardsScreen extends StatefulWidget {
  const AdminFlashcardsScreen({super.key});

  @override
  State<AdminFlashcardsScreen> createState() => _AdminFlashcardsScreenState();
}

class _AdminFlashcardsScreenState extends State<AdminFlashcardsScreen> {
  String _query = '';
  NoteWorkflowStatus? _status;
  String? _group;
  String? _difficulty;
  String? _language;
  String? _subjectId;
  String? _chapterId;
  String? _topicId;
  DateTime? _date;

  Future<void> _setStatus(FlashcardItem item, NoteWorkflowStatus status) async {
    try {
      final next = item.copyWith(status: status);
      await flashcardRepository.update(next);
      try {
        await contentKnowledgeIndexer.syncFlashcard(next);
      } catch (_) {}
      await auditLogRepository.log(
        action: status == NoteWorkflowStatus.published
            ? 'publish'
            : status == NoteWorkflowStatus.approved
                ? 'approve'
                : 'unpublish',
        module: 'Flashcards',
        targetLabel: item.title,
      );
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  List<FlashcardItem> _filter(List<FlashcardItem> all) {
    return all.where((c) {
      return matchesAdminContentFilters(
        query: _query,
        fields: [c.title, c.front, c.back, c.topicId, ...c.tags],
        targetGroup: _group,
        itemTargetGroup: c.targetGroup,
        status: _status,
        itemStatus: c.status,
        difficulty: _difficulty,
        itemDifficulty: c.difficulty,
        language: _language,
        itemLanguage: c.language,
        subjectId: _subjectId,
        itemSubjectId: c.subjectId,
        chapterId: _chapterId,
        itemChapterId: c.chapterId,
        topicId: _topicId,
        itemTopicId: c.topicId,
        date: _date,
        itemDate: c.updatedAt ?? c.createdAt,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Content → Flashcards',
      actions: [
        IconButton(
          tooltip: 'Generate with AI (draft)',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AdminAiFlashcardGenerateScreen(),
            ),
          ),
          icon: const Icon(Icons.auto_awesome_rounded),
        ),
        IconButton(
          tooltip: 'Import CSV / Excel',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AdminFlashcardBulkUploadScreen(),
            ),
          ),
          icon: const Icon(Icons.upload_file_rounded),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const AdminFlashcardFormScreen(),
          ),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<FlashcardItem>>(
        stream: flashcardRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
              message: 'Could not load flashcards: ${snapshot.error}',
            );
          }
          if (!snapshot.hasData) return const LoadingState();
          final all = snapshot.data!;
          final items = _filter(all);
          if (all.isEmpty) {
            return const EmptyState(
              message: 'No flashcards yet. Tap + to add the first one.',
              icon: Icons.style_outlined,
            );
          }
          return Column(
            children: [
              AdminContentFilterBar(
                queryHint: 'Search title, question, topic, tags…',
                onQueryChanged: (v) => setState(() => _query = v),
                status: _status,
                onStatusChanged: (v) => setState(() => _status = v),
                targetGroup: _group,
                onTargetGroupChanged: (v) => setState(() => _group = v),
                difficulty: _difficulty,
                onDifficultyChanged: (v) => setState(() => _difficulty = v),
                language: _language,
                onLanguageChanged: (v) => setState(() => _language = v),
                subjectId: _subjectId,
                onSubjectIdChanged: (v) => setState(() => _subjectId = v),
                chapterId: _chapterId,
                onChapterIdChanged: (v) => setState(() => _chapterId = v),
                topicId: _topicId,
                onTopicIdChanged: (v) => setState(() => _topicId = v),
                date: _date,
                onDateChanged: (v) => setState(() => _date = v),
                showIndexFilters: true,
              ),
              Expanded(
                child: items.isEmpty
                    ? const EmptyState(
                        message: 'No flashcards match these filters.',
                        icon: Icons.search_off_rounded,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return AdminListTile(
                            title: item.title.isNotEmpty ? item.title : item.front,
                            subtitle:
                                '${contentWorkflowStatusLabel(item.status)} · '
                                '${targetGroupLabel(targetGroupFromString(item.targetGroup))} · '
                                '${item.difficulty}',
                            icon: Icons.style_rounded,
                            isActive: item.status == NoteWorkflowStatus.published,
                            onPreview: () => showFlashcardPreview(context, item),
                            onApprove: () => _setStatus(
                              item,
                              NoteWorkflowStatus.approved,
                            ),
                            onToggleActive: () => _setStatus(
                              item,
                              item.status == NoteWorkflowStatus.published
                                  ? NoteWorkflowStatus.unpublished
                                  : NoteWorkflowStatus.published,
                            ),
                            onEdit: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    AdminFlashcardFormScreen(existing: item),
                              ),
                            ),
                            onDelete: () async {
                              final confirmed =
                                  await confirmDelete(context, item.title);
                              if (!confirmed) return;
                              try {
                                await flashcardRepository.delete(item.id);
                                await auditLogRepository.log(
                                  action: 'delete',
                                  module: 'Flashcards',
                                  targetLabel: item.title,
                                );
                                if (context.mounted) {
                                  showAdminMessage(context, 'Flashcard deleted.');
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
