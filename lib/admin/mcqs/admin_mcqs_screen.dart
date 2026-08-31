import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/admin_bulk_upload_screen.dart';
import 'package:mpsc_combine_ai/admin/mcqs/admin_ai_mcq_generate_screen.dart';
import 'package:mpsc_combine_ai/admin/mcqs/admin_mcq_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_content_filter_bar.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_preview.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class _McqSet {
  _McqSet(this.title) : questions = [];

  final String title;
  final List<McqItem> questions;

  String get subject => questions.isEmpty ? '' : questions.first.subject;
  NoteWorkflowStatus get status {
    if (questions.every((q) => q.status == NoteWorkflowStatus.published)) {
      return NoteWorkflowStatus.published;
    }
    return questions.first.status;
  }
}

List<_McqSet> _groupBySet(List<McqItem> items) {
  final map = <String, _McqSet>{};
  for (final item in items) {
    map.putIfAbsent(item.setTitle, () => _McqSet(item.setTitle)).questions.add(item);
  }
  return map.values.toList();
}

class AdminMcqsScreen extends StatefulWidget {
  const AdminMcqsScreen({super.key});

  @override
  State<AdminMcqsScreen> createState() => _AdminMcqsScreenState();
}

class _AdminMcqsScreenState extends State<AdminMcqsScreen> {
  String _query = '';
  NoteWorkflowStatus? _status;
  String? _group;
  String? _difficulty;
  String? _subjectId;
  String? _chapterId;
  String? _topicId;

  Future<void> _setStatus(List<McqItem> questions, NoteWorkflowStatus status) async {
    try {
      for (final q in questions) {
        await mcqRepository.update(q.copyWith(status: status));
      }
      await auditLogRepository.log(
        action: status == NoteWorkflowStatus.published
            ? 'publish'
            : status == NoteWorkflowStatus.approved
                ? 'approve'
                : 'unpublish',
        module: 'MCQs',
        targetLabel: questions.isEmpty ? 'set' : questions.first.setTitle,
      );
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  List<McqItem> _filter(List<McqItem> all) {
    return all.where((q) {
      return matchesAdminContentFilters(
        query: _query,
        fields: [q.setTitle, q.question, q.subject, ...q.tags],
        targetGroup: _group,
        itemTargetGroup: q.targetGroup,
        status: _status,
        itemStatus: q.status,
        difficulty: _difficulty,
        itemDifficulty: q.difficulty,
        subjectId: _subjectId,
        itemSubjectId: q.subjectId,
        chapterId: _chapterId,
        itemChapterId: q.chapterId,
        topicId: _topicId,
        itemTopicId: q.topicId,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Content → MCQs / Practice',
      actions: [
        IconButton(
          tooltip: 'Generate with AI (draft)',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AdminAiMcqGenerateScreen(),
            ),
          ),
          icon: const Icon(Icons.auto_awesome_rounded),
        ),
        IconButton(
          tooltip: 'Import CSV / Excel',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AdminBulkUploadScreen(),
            ),
          ),
          icon: const Icon(Icons.upload_file_rounded),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AdminMcqFormScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<McqItem>>(
        stream: mcqRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load MCQs: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const EmptyState(
              message: 'No MCQ sets yet. Tap + to add the first question.',
              icon: Icons.quiz_outlined,
            );
          }
          final sets = _groupBySet(_filter(items));
          return Column(
            children: [
              AdminContentFilterBar(
                queryHint: 'Search set, question, topic…',
                onQueryChanged: (v) => setState(() => _query = v),
                status: _status,
                onStatusChanged: (v) => setState(() => _status = v),
                targetGroup: _group,
                onTargetGroupChanged: (v) => setState(() => _group = v),
                difficulty: _difficulty,
                onDifficultyChanged: (v) => setState(() => _difficulty = v),
                subjectId: _subjectId,
                onSubjectIdChanged: (v) => setState(() => _subjectId = v),
                chapterId: _chapterId,
                onChapterIdChanged: (v) => setState(() => _chapterId = v),
                topicId: _topicId,
                onTopicIdChanged: (v) => setState(() => _topicId = v),
                showIndexFilters: true,
              ),
              Expanded(
                child: sets.isEmpty
                    ? const EmptyState(
                        message: 'No MCQs match these filters.',
                        icon: Icons.search_off_rounded,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: sets.length,
                        itemBuilder: (context, index) {
                          final set = sets[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ExpansionTile(
                              leading: const Icon(
                                Icons.quiz_rounded,
                                color: AppColors.navy,
                              ),
                              title: Text(
                                set.title,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                '${set.questions.length} Q · ${set.subject} · '
                                '${contentWorkflowStatusLabel(set.status)}',
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Wrap(
                                    spacing: 8,
                                    children: [
                                      TextButton(
                                        onPressed: () => showMcqPreview(
                                          context,
                                          set.questions.first,
                                        ),
                                        child: const Text('Preview'),
                                      ),
                                      TextButton(
                                        onPressed: () => _setStatus(
                                          set.questions,
                                          NoteWorkflowStatus.approved,
                                        ),
                                        child: const Text('Approve'),
                                      ),
                                      TextButton(
                                        onPressed: () => _setStatus(
                                          set.questions,
                                          NoteWorkflowStatus.published,
                                        ),
                                        child: const Text('Publish'),
                                      ),
                                      TextButton(
                                        onPressed: () => _setStatus(
                                          set.questions,
                                          NoteWorkflowStatus.unpublished,
                                        ),
                                        child: const Text('Unpublish'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => AdminMcqFormScreen(
                                              setTitle: set.title,
                                            ),
                                          ),
                                        ),
                                        child: const Text('Add question'),
                                      ),
                                    ],
                                  ),
                                ),
                                for (final q in set.questions)
                                  AdminListTile(
                                    title: q.question,
                                    subtitle:
                                        '${contentWorkflowStatusLabel(q.status)} · ${q.difficulty}',
                                    icon: Icons.gavel_rounded,
                                    isActive:
                                        q.status == NoteWorkflowStatus.published,
                                    onPreview: () => showMcqPreview(context, q),
                                    onApprove: () => _setStatus(
                                      [q],
                                      NoteWorkflowStatus.approved,
                                    ),
                                    onToggleActive: () => _setStatus(
                                      [q],
                                      q.status == NoteWorkflowStatus.published
                                          ? NoteWorkflowStatus.unpublished
                                          : NoteWorkflowStatus.published,
                                    ),
                                    onEdit: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            AdminMcqFormScreen(existing: q),
                                      ),
                                    ),
                                    onDelete: () async {
                                      final confirmed =
                                          await confirmDelete(context, q.question);
                                      if (!confirmed) return;
                                      try {
                                        await mcqRepository.delete(q.id);
                                        await auditLogRepository.log(
                                          action: 'delete',
                                          module: 'MCQs',
                                          targetLabel: q.question,
                                        );
                                        if (context.mounted) {
                                          showAdminMessage(context, 'MCQ deleted.');
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          showAdminError(context, e);
                                        }
                                      }
                                    },
                                  ),
                              ],
                            ),
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
