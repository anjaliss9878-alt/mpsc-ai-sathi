import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/tests/admin_test_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_content_filter_bar.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_preview.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/test_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/test_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminTestsScreen extends StatefulWidget {
  const AdminTestsScreen({super.key});

  @override
  State<AdminTestsScreen> createState() => _AdminTestsScreenState();
}

class _AdminTestsScreenState extends State<AdminTestsScreen> {
  String _query = '';
  NoteWorkflowStatus? _status;
  String? _group;
  String? _difficulty;
  String? _subjectId;
  String? _chapterId;
  String? _topicId;

  Future<void> _setStatus(TestItem test, NoteWorkflowStatus status) async {
    try {
      await testRepository.update(test.copyWith(status: status));
      await auditLogRepository.log(
        action: status == NoteWorkflowStatus.published
            ? 'publish'
            : status == NoteWorkflowStatus.approved
                ? 'approve'
                : 'unpublish',
        module: 'Tests',
        targetLabel: test.title,
      );
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  List<TestItem> _filter(List<TestItem> all) {
    return all.where((test) {
      return matchesAdminContentFilters(
        query: _query,
        fields: [test.title, test.subtitle, test.instructions],
        targetGroup: _group,
        itemTargetGroup: test.targetGroup,
        status: _status,
        itemStatus: test.status,
        difficulty: _difficulty,
        itemDifficulty: test.difficulty,
        subjectId: _subjectId,
        itemSubjectId: test.subjectId,
        chapterId: _chapterId,
        itemChapterId: test.chapterId,
        topicId: _topicId,
        itemTopicId: test.topicId,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Content → Tests',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AdminTestFormScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<TestItem>>(
        stream: testRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load tests: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final all = snapshot.data!;
          if (all.isEmpty) {
            return const EmptyState(
              message: 'No tests yet. Tap + to create the first mock test.',
              icon: Icons.assignment_outlined,
            );
          }
          final tests = _filter(all);
          return Column(
            children: [
              AdminContentFilterBar(
                queryHint: 'Search title, topic…',
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
                child: tests.isEmpty
                    ? const EmptyState(
                        message: 'No tests match these filters.',
                        icon: Icons.search_off_rounded,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: tests.length,
                        itemBuilder: (context, index) {
                          final test = tests[index];
                          return AdminListTile(
                            title: test.title,
                            subtitle:
                                '${contentWorkflowStatusLabel(test.status)} · '
                                '${test.questions.length} questions · ${test.durationSeconds ~/ 60} min · '
                                '+${test.correctMarks}/-${test.negativeMarks}',
                            icon: Icons.assignment_turned_in_rounded,
                            isActive: test.status == NoteWorkflowStatus.published,
                            onPreview: () => showTestPreview(context, test),
                            onApprove: () => _setStatus(
                              test,
                              NoteWorkflowStatus.approved,
                            ),
                            onToggleActive: () => _setStatus(
                              test,
                              test.status == NoteWorkflowStatus.published
                                  ? NoteWorkflowStatus.unpublished
                                  : NoteWorkflowStatus.published,
                            ),
                            onEdit: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AdminTestFormScreen(existing: test),
                              ),
                            ),
                            onDelete: () async {
                              final confirmed =
                                  await confirmDelete(context, test.title);
                              if (!confirmed) return;
                              try {
                                await testRepository.delete(test.id);
                                await auditLogRepository.log(
                                  action: 'delete',
                                  module: 'Tests',
                                  targetLabel: test.title,
                                );
                                if (context.mounted) {
                                  showAdminMessage(context, 'Test deleted.');
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
