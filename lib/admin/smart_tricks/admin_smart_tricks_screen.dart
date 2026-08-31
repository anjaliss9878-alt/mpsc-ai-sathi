import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/admin_smart_trick_bulk_upload_screen.dart';
import 'package:mpsc_combine_ai/admin/smart_tricks/admin_ai_smart_trick_generate_screen.dart';
import 'package:mpsc_combine_ai/admin/smart_tricks/admin_smart_trick_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_content_filter_bar.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_preview.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/smart_trick_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/content_knowledge_indexer.dart';
import 'package:mpsc_combine_ai/services/smart_trick_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminSmartTricksScreen extends StatefulWidget {
  const AdminSmartTricksScreen({super.key});

  @override
  State<AdminSmartTricksScreen> createState() => _AdminSmartTricksScreenState();
}

class _AdminSmartTricksScreenState extends State<AdminSmartTricksScreen> {
  String _query = '';
  NoteWorkflowStatus? _status;
  String? _group;
  String? _language;
  String? _subjectId;
  String? _chapterId;
  String? _topicId;
  DateTime? _date;

  Future<void> _setStatus(SmartTrickItem item, NoteWorkflowStatus status) async {
    try {
      final next = item.copyWith(status: status);
      await smartTrickRepository.update(next);
      try {
        await contentKnowledgeIndexer.syncSmartTrick(next);
      } catch (_) {}
      await auditLogRepository.log(
        action: status == NoteWorkflowStatus.published
            ? 'publish'
            : status == NoteWorkflowStatus.approved
                ? 'approve'
                : 'unpublish',
        module: 'Smart Tricks',
        targetLabel: item.title,
      );
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  List<SmartTrickItem> _filter(List<SmartTrickItem> all) {
    return all.where((t) {
      return matchesAdminContentFilters(
        query: _query,
        fields: [t.title, t.concept, t.memoryTrick, t.topicId, ...t.tags],
        targetGroup: _group,
        itemTargetGroup: t.targetGroup,
        status: _status,
        itemStatus: t.status,
        language: _language,
        itemLanguage: t.language,
        subjectId: _subjectId,
        itemSubjectId: t.subjectId,
        chapterId: _chapterId,
        itemChapterId: t.chapterId,
        topicId: _topicId,
        itemTopicId: t.topicId,
        date: _date,
        itemDate: t.updatedAt ?? t.createdAt,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Content → Smart Tricks',
      actions: [
        IconButton(
          tooltip: 'Generate with AI (draft)',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AdminAiSmartTrickGenerateScreen(),
            ),
          ),
          icon: const Icon(Icons.auto_awesome_rounded),
        ),
        IconButton(
          tooltip: 'Import CSV / Excel',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AdminSmartTrickBulkUploadScreen(),
            ),
          ),
          icon: const Icon(Icons.upload_file_rounded),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const AdminSmartTrickFormScreen(),
          ),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<SmartTrickItem>>(
        stream: smartTrickRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
              message: 'Could not load smart tricks: ${snapshot.error}',
            );
          }
          if (!snapshot.hasData) return const LoadingState();
          final all = snapshot.data!;
          final items = _filter(all);
          if (all.isEmpty) {
            return const EmptyState(
              message: 'No smart tricks yet. Tap + to add the first one.',
              icon: Icons.psychology_alt_outlined,
            );
          }
          return Column(
            children: [
              AdminContentFilterBar(
                queryHint: 'Search title, concept, topic, tags…',
                onQueryChanged: (v) => setState(() => _query = v),
                status: _status,
                onStatusChanged: (v) => setState(() => _status = v),
                targetGroup: _group,
                onTargetGroupChanged: (v) => setState(() => _group = v),
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
                        message: 'No smart tricks match these filters.',
                        icon: Icons.search_off_rounded,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return AdminListTile(
                            title: item.title,
                            subtitle:
                                '${contentWorkflowStatusLabel(item.status)} · '
                                '${targetGroupLabel(targetGroupFromString(item.targetGroup))} · '
                                '${item.memoryTrick}',
                            icon: Icons.psychology_alt_rounded,
                            isActive: item.status == NoteWorkflowStatus.published,
                            onPreview: () => showSmartTrickPreview(context, item),
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
                                    AdminSmartTrickFormScreen(existing: item),
                              ),
                            ),
                            onDelete: () async {
                              final confirmed =
                                  await confirmDelete(context, item.title);
                              if (!confirmed) return;
                              try {
                                await smartTrickRepository.delete(item.id);
                                await auditLogRepository.log(
                                  action: 'delete',
                                  module: 'Smart Tricks',
                                  targetLabel: item.title,
                                );
                                if (context.mounted) {
                                  showAdminMessage(context, 'Smart trick deleted.');
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
