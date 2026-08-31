import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/current_affairs/admin_current_affair_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_content_filter_bar.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_preview.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/current_affair_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/content_knowledge_indexer.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/utils/date_format.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminCurrentAffairsScreen extends StatefulWidget {
  const AdminCurrentAffairsScreen({super.key});

  @override
  State<AdminCurrentAffairsScreen> createState() =>
      _AdminCurrentAffairsScreenState();
}

class _AdminCurrentAffairsScreenState extends State<AdminCurrentAffairsScreen> {
  String _query = '';
  NoteWorkflowStatus? _status;
  String? _group;
  String? _subjectId;
  String? _chapterId;
  String? _topicId;
  DateTime? _date;

  Future<void> _setStatus(
    CurrentAffairItem item,
    NoteWorkflowStatus status,
  ) async {
    try {
      final next = item.copyWith(status: status);
      await currentAffairsRepository.update(next);
      try {
        await contentKnowledgeIndexer.syncCurrentAffair(next);
      } catch (_) {}
      await auditLogRepository.log(
        action: status == NoteWorkflowStatus.published
            ? 'publish'
            : status == NoteWorkflowStatus.approved
                ? 'approve'
                : 'unpublish',
        module: 'Current Affairs',
        targetLabel: item.title,
      );
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  List<CurrentAffairItem> _filter(List<CurrentAffairItem> all) {
    return all.where((e) {
      return matchesAdminContentFilters(
        query: _query,
        fields: [e.title, e.description, e.category, e.topicId, ...e.tags],
        targetGroup: _group,
        itemTargetGroup: e.targetGroup,
        status: _status,
        itemStatus: e.status,
        subjectId: _subjectId,
        itemSubjectId: e.subjectId,
        chapterId: _chapterId,
        itemChapterId: e.chapterId,
        topicId: _topicId,
        itemTopicId: e.topicId,
        date: _date,
        itemDate: e.date,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Content → Current Affairs',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const AdminCurrentAffairFormScreen(),
          ),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<CurrentAffairItem>>(
        stream: currentAffairsRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
              message: 'Could not load entries: ${snapshot.error}',
            );
          }
          if (!snapshot.hasData) return const LoadingState();
          final all = snapshot.data!;
          final items = _filter(all);
          if (all.isEmpty) {
            return const EmptyState(
              message: 'No current affairs yet. Tap + to add the first entry.',
              icon: Icons.newspaper_outlined,
            );
          }
          return Column(
            children: [
              AdminContentFilterBar(
                queryHint: 'Search title, topic, tags…',
                onQueryChanged: (v) => setState(() => _query = v),
                status: _status,
                onStatusChanged: (v) => setState(() => _status = v),
                targetGroup: _group,
                onTargetGroupChanged: (v) => setState(() => _group = v),
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
                        message: 'No current affairs match these filters.',
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
                                '${formatShortDate(item.date)} · ${item.category}',
                            icon: Icons.today_rounded,
                            isActive:
                                item.status == NoteWorkflowStatus.published,
                            onPreview: () =>
                                showCurrentAffairPreview(context, item),
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
                                builder: (_) => AdminCurrentAffairFormScreen(
                                  existing: item,
                                ),
                              ),
                            ),
                            onDelete: () async {
                              final confirmed =
                                  await confirmDelete(context, item.title);
                              if (!confirmed) return;
                              try {
                                await currentAffairsRepository.delete(item.id);
                                await auditLogRepository.log(
                                  action: 'delete',
                                  module: 'Current Affairs',
                                  targetLabel: item.title,
                                );
                                if (context.mounted) {
                                  showAdminMessage(context, 'Entry deleted.');
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
