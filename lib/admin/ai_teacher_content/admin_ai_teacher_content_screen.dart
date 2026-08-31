import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/ai_teacher_content/admin_ai_teacher_content_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_content_filter_bar.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_preview.dart';
import 'package:mpsc_combine_ai/models/ai_teacher_content_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_content_repository.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/content_knowledge_indexer.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Admin CRUD for lessons the AI Teacher Classroom can play back instantly
/// (matched by keyword) instead of always calling Gemini live.
class AdminAiTeacherContentScreen extends StatefulWidget {
  const AdminAiTeacherContentScreen({super.key});

  @override
  State<AdminAiTeacherContentScreen> createState() =>
      _AdminAiTeacherContentScreenState();
}

class _AdminAiTeacherContentScreenState
    extends State<AdminAiTeacherContentScreen> {
  String _query = '';
  NoteWorkflowStatus? _status;
  String? _group;
  String? _subjectId;
  String? _chapterId;
  String? _topicId;
  DateTime? _date;

  Future<void> _setStatus(
    AiTeacherContentItem item,
    NoteWorkflowStatus status,
  ) async {
    try {
      final next = item.copyWith(status: status);
      await aiTeacherContentRepository.update(next);
      try {
        await contentKnowledgeIndexer.syncAiLesson(next);
      } catch (_) {}
      await auditLogRepository.log(
        action: status == NoteWorkflowStatus.published
            ? 'publish'
            : status == NoteWorkflowStatus.approved
                ? 'approve'
                : 'unpublish',
        module: 'AI Teacher Content',
        targetLabel: item.lessonTitle,
      );
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  List<AiTeacherContentItem> _filter(List<AiTeacherContentItem> all) {
    return all.where((l) {
      return matchesAdminContentFilters(
        query: _query,
        fields: [l.lessonTitle, l.summary, l.subjectName, ...l.keywords],
        targetGroup: _group,
        itemTargetGroup: l.targetGroup,
        status: _status,
        itemStatus: l.status,
        subjectId: _subjectId,
        itemSubjectId: l.subjectId,
        chapterId: _chapterId,
        itemChapterId: l.chapterId,
        topicId: _topicId,
        itemTopicId: l.topicId,
        date: _date,
        itemDate: l.updatedAt ?? l.createdAt,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'AI Teacher Content',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const AdminAiTeacherContentFormScreen(),
          ),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<AiTeacherContentItem>>(
        stream: aiTeacherContentRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
              message: 'Could not load lessons: ${snapshot.error}',
            );
          }
          if (!snapshot.hasData) return const LoadingState();
          final all = snapshot.data!;
          final items = _filter(all);
          if (all.isEmpty) {
            return const EmptyState(
              message: 'No authored lessons yet. Tap + to write the first one — '
                  'the AI Teacher will use it instantly whenever a student '
                  'asks a matching question.',
              icon: Icons.smart_toy_outlined,
            );
          }
          return Column(
            children: [
              AdminContentFilterBar(
                queryHint: 'Search title, topic, keywords…',
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
                        message: 'No lessons match these filters.',
                        icon: Icons.search_off_rounded,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return AdminListTile(
                            title: item.lessonTitle,
                            subtitle:
                                '${contentWorkflowStatusLabel(item.status)} · '
                                'Keywords: ${item.keywords.join(', ')}',
                            icon: Icons.smart_toy_rounded,
                            isActive:
                                item.status == NoteWorkflowStatus.published,
                            onPreview: () => showAiLessonPreview(context, item),
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
                                    AdminAiTeacherContentFormScreen(
                                  existing: item,
                                ),
                              ),
                            ),
                            onDelete: () async {
                              final confirmed = await confirmDelete(
                                context,
                                item.lessonTitle,
                              );
                              if (!confirmed) return;
                              try {
                                await aiTeacherContentRepository.delete(item.id);
                                await auditLogRepository.log(
                                  action: 'delete',
                                  module: 'AI Teacher Content',
                                  targetLabel: item.lessonTitle,
                                );
                                if (context.mounted) {
                                  showAdminMessage(context, 'Lesson deleted.');
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
