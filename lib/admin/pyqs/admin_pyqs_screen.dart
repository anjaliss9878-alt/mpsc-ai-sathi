import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/admin_pyq_bulk_upload_screen.dart';
import 'package:mpsc_combine_ai/admin/pyqs/admin_pyq_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_content_filter_bar.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_preview.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/content_knowledge_indexer.dart';
import 'package:mpsc_combine_ai/services/pyq_analysis_service.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminPyqsScreen extends StatefulWidget {
  const AdminPyqsScreen({super.key});

  @override
  State<AdminPyqsScreen> createState() => _AdminPyqsScreenState();
}

class _AdminPyqsScreenState extends State<AdminPyqsScreen> {
  int? _yearFilter;
  String _query = '';
  NoteWorkflowStatus? _status;
  String? _group;
  String? _difficulty;
  String? _subjectId;
  String? _chapterId;
  String? _topicId;

  Future<void> _setStatus(PyqItem item, NoteWorkflowStatus status) async {
    try {
      await pyqRepository.updateWorkflow(item.id, status);
      final next = item.copyWith(status: status);
      try {
        await contentKnowledgeIndexer.syncPyq(next);
      } catch (_) {}
      await auditLogRepository.log(
        action: status == NoteWorkflowStatus.published
            ? 'publish'
            : status == NoteWorkflowStatus.approved
                ? 'approve'
                : 'unpublish',
        module: 'PYQs',
        targetLabel: item.title,
      );
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  List<PyqItem> _filter(List<PyqItem> all) {
    return all.where((item) {
      if (_yearFilter != null && item.year != _yearFilter) return false;
      return matchesAdminContentFilters(
        query: _query,
        fields: [item.title, item.question, item.subtitle, item.subject, ...item.tags],
        targetGroup: _group,
        itemTargetGroup: item.targetGroup,
        status: _status,
        itemStatus: item.status,
        difficulty: _difficulty,
        itemDifficulty: item.difficulty,
        subjectId: _subjectId,
        itemSubjectId: item.subjectId,
        chapterId: _chapterId,
        itemChapterId: item.chapterId,
        topicId: _topicId,
        itemTopicId: item.topicId,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Content → PYQs',
      actions: [
        IconButton(
          tooltip: 'Import CSV / Excel',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AdminPyqBulkUploadScreen(),
            ),
          ),
          icon: const Icon(Icons.upload_file_rounded),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AdminPyqFormScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<PyqItem>>(
        stream: pyqRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load PYQs: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final allItems = snapshot.data!;
          final years = allItems
              .map((i) => i.year)
              .whereType<int>()
              .toSet()
              .toList()
            ..sort((a, b) => b.compareTo(a));
          final items = _filter(allItems);
          final analysis = analyzeUploadedPyqs(allItems);
          return Column(
            children: [
              AdminContentFilterBar(
                queryHint: 'Search title, question, topic…',
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
              _PyqAnalysisStrip(analysis: analysis),
              if (years.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      const Text(
                        'Filter by year:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ChoiceChip(
                                label: const Text('All'),
                                selected: _yearFilter == null,
                                onSelected: (_) =>
                                    setState(() => _yearFilter = null),
                              ),
                              const SizedBox(width: 6),
                              ...years.map(
                                (y) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text('$y'),
                                    selected: _yearFilter == y,
                                    onSelected: (_) =>
                                        setState(() => _yearFilter = y),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: items.isEmpty
                    ? const EmptyState(
                        message: 'No PYQs yet. Tap + to add the first one.',
                        icon: Icons.history_edu_outlined,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final subtitle = [
                            contentWorkflowStatusLabel(item.status),
                            targetGroupLabel(
                              targetGroupFromString(item.targetGroup),
                            ),
                            if (item.year != null) '${item.year}',
                            if (item.question.isNotEmpty) item.question,
                            if (item.subtitle.isNotEmpty) item.subtitle,
                          ].join(' · ');
                          return AdminListTile(
                            title: item.title,
                            subtitle: subtitle,
                            icon: item.isStructuredQuestion
                                ? Icons.quiz_outlined
                                : Icons.description_rounded,
                            isActive: item.status == NoteWorkflowStatus.published,
                            onPreview: () => showPyqPreview(context, item),
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
                                    AdminPyqFormScreen(existing: item),
                              ),
                            ),
                            onDelete: () async {
                              final confirmed =
                                  await confirmDelete(context, item.title);
                              if (!confirmed) return;
                              try {
                                await pyqRepository.delete(item.id);
                                try {
                                  await contentKnowledgeIndexer.removeLinked(
                                    collection: PyqRepository.collection,
                                    linkedId: item.id,
                                  );
                                } catch (_) {}
                                await auditLogRepository.log(
                                  action: 'delete',
                                  module: 'PYQs',
                                  targetLabel: item.title,
                                );
                                if (context.mounted) {
                                  showAdminMessage(context, 'Entry deleted.');
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

class _PyqAnalysisStrip extends StatelessWidget {
  const _PyqAnalysisStrip({required this.analysis});

  final PyqAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    if (analysis.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          'PYQ analysis appears after approved/published PYQs are uploaded.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }
    String freq(List<PyqFrequencyRow> rows) => rows.isEmpty
        ? '—'
        : rows.take(4).map((r) => '${r.label} (${r.count})').join(' · ');
    final difficulty = analysis.difficultyDistribution.entries
        .map((e) => '${e.key} ${e.value}')
        .join(' · ');
    final priority = analysis.preparationPriority.isEmpty
        ? '—'
        : analysis.preparationPriority
            .take(4)
            .map((r) => r.label)
            .join(' · ');
    final concepts = analysis.repeatedConcepts.isEmpty
        ? '—'
        : analysis.repeatedConcepts.take(6).map((c) => c.concept).join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PYQ analysis (${analysis.analyzedCount} approved)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text('Topic frequency: ${freq(analysis.topicFrequency)}',
                  style: const TextStyle(fontSize: 12)),
              Text('Chapter frequency: ${freq(analysis.chapterFrequency)}',
                  style: const TextStyle(fontSize: 12)),
              Text('Repeated concepts: $concepts',
                  style: const TextStyle(fontSize: 12)),
              Text(
                'Important areas: ${freq(analysis.importantAreas)}',
                style: const TextStyle(fontSize: 12),
              ),
              Text('Difficulty: $difficulty',
                  style: const TextStyle(fontSize: 12)),
              Text('Preparation priority: $priority',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

