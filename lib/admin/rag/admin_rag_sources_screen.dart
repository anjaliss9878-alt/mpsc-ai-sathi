import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/rag/admin_rag_source_form_screen.dart';
import 'package:mpsc_combine_ai/admin/rag/admin_rag_test_console.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_content_filter_bar.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';
import 'package:mpsc_combine_ai/rag/rag_management.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_processing_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/date_format.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminRagSourcesScreen extends StatefulWidget {
  const AdminRagSourcesScreen({super.key});

  @override
  State<AdminRagSourcesScreen> createState() => _AdminRagSourcesScreenState();
}

class _AdminRagSourcesScreenState extends State<AdminRagSourcesScreen> {
  final _consoleKey = GlobalKey();
  final Set<String> _busy = {};
  String? _subjectId;
  String? _chapterId;
  String? _topicId;
  String? _contentType;
  String? _examId;
  RagDomain? _domain;
  RagAdminStatusFilter _ragStatus = RagAdminStatusFilter.all;
  List<ExamItem> _exams = const [];

  @override
  void initState() {
    super.initState();
    notesRepository.getExamsOnce().then((exams) {
      if (mounted) setState(() => _exams = exams);
    });
  }

  Future<void> _index(RagSource source, {required bool force}) async {
    final issues = ragIndexMetadataIssues(source);
    if (issues.isNotEmpty) {
      showAdminMessage(context, issues.first.message);
      return;
    }
    setState(() => _busy.add(source.id));
    try {
      await ragProcessingService.processSource(source.id, force: force);
      await auditLogRepository.log(
        action: force ? 'reindex' : 'index',
        module: 'RAG Management',
        targetLabel: source.title,
      );
      if (!mounted) return;
      showAdminMessage(context, force ? 'Re-index finished.' : 'Indexing finished.');
    } catch (e) {
      if (mounted) showAdminError(context, RagException.fromError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(source.id));
    }
  }

  Future<void> _retry(RagSource source) => _index(source, force: true);

  Future<void> _togglePublished(RagSource source, bool published) async {
    setState(() => _busy.add(source.id));
    try {
      await ragProcessingService.setPublished(source, published);
      await auditLogRepository.log(
        action: published ? 'publish' : 'unpublish',
        module: 'RAG Management',
        targetLabel: source.title,
      );
    } catch (e) {
      if (mounted) showAdminError(context, RagException.fromError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(source.id));
    }
  }

  Future<void> _removeFromRag(RagSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from RAG?'),
        content: Text(
          '"${source.title}" chunks will be deleted. The source row stays as Draft.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy.add(source.id));
    try {
      await ragProcessingService.removeFromRag(source);
      await auditLogRepository.log(
        action: 'remove_from_rag',
        module: 'RAG Management',
        targetLabel: source.title,
      );
    } catch (e) {
      if (mounted) showAdminError(context, RagException.fromError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(source.id));
    }
  }

  Future<void> _delete(RagSource source) async {
    final confirmed = await confirmDelete(context, source.title);
    if (!confirmed) return;
    setState(() => _busy.add(source.id));
    try {
      await ragProcessingService.deleteSourceSafely(source);
      await auditLogRepository.log(
        action: 'delete',
        module: 'RAG Management',
        targetLabel: source.title,
      );
    } catch (e) {
      if (mounted) showAdminError(context, RagException.fromError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(source.id));
    }
  }

  Future<void> _preview(RagSource source) async {
    List<RagChunk> chunks;
    try {
      chunks = await ragChunkRepository.getForSource(source.id);
    } catch (e) {
      if (mounted) showAdminError(context, RagException.fromError(e));
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(source.title.isEmpty ? 'Preview' : source.title),
        content: SizedBox(
          width: 520,
          child: chunks.isEmpty
              ? const Text('No chunks indexed yet.')
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final chunk in chunks.take(12)) ...[
                        Text(
                          'Chunk ${chunk.chunkIndex + 1}'
                          '${chunk.pageNumber != null ? ' · page ${chunk.pageNumber}' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(chunk.text, maxLines: 8, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 12),
                      ],
                      if (chunks.length > 12)
                        Text('${chunks.length - 12} more chunks…'),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _scrollToConsole() {
    final ctx = _consoleKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  Color _statusColor(RagManagementStatus status) {
    switch (status) {
      case RagManagementStatus.ready:
        return Colors.green.shade700;
      case RagManagementStatus.failed:
        return Colors.red.shade700;
      case RagManagementStatus.processing:
        return Colors.orange.shade800;
      case RagManagementStatus.needsReindex:
        return Colors.amber.shade800;
      case RagManagementStatus.draft:
        return AppColors.textSecondary;
    }
  }

  String _subtitle(RagSource item) {
    final management = ragManagementStatus(item);
    final indexedAt = ragLastIndexedAt(item);
    return [
      item.exam.isNotEmpty ? item.exam : item.examId,
      if (item.subject.isNotEmpty) item.subject,
      if (item.chapter.isNotEmpty) item.chapter,
      if (item.topicId.isNotEmpty) item.topicId,
      item.contentType.isNotEmpty
          ? item.contentType
          : ragSourceTypeLabel(item.sourceType),
      ragDocumentLabel(item),
      ragDomainLabel(item.domain),
      ragManagementStatusToString(management),
      '${item.chunkCount} chunks',
      ragEmbeddingStatusLabel(ragEmbeddingStatus(item)),
      if (indexedAt != null) formatFriendlyDateTime(indexedAt),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Content → RAG Management',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const AdminRagSourceFormScreen(),
          ),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<RagSource>>(
        stream: ragSourceRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
              message: 'Could not load sources: ${snapshot.error}',
            );
          }
          if (!snapshot.hasData) return const LoadingState();
          final items = snapshot.data!;
          final stats = ragAdminMonitorStats(items);
          final filtered = items
              .where(
                (s) => matchesRagAdminFilters(
                  s,
                  examId: _examId,
                  subjectId: _subjectId,
                  chapterId: _chapterId,
                  topicId: _topicId,
                  contentType: _contentType,
                  domain: _domain,
                  status: _ragStatus,
                ),
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Upload/Save → validate metadata → extract → clean → chunk → '
                'embed → index → Ready. Uses the existing RAG pipeline.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _RagStatCard(label: 'Total Sources', value: stats.total),
                  _RagStatCard(label: 'Indexed', value: stats.indexed),
                  _RagStatCard(label: 'Processing', value: stats.processing),
                  _RagStatCard(label: 'Failed', value: stats.failed),
                ],
              ),
              AdminContentFilterBar(
                queryHint: 'Filter by content index…',
                onQueryChanged: (_) {},
                showSearch: false,
                subjectId: _subjectId,
                onSubjectIdChanged: (v) => setState(() => _subjectId = v),
                chapterId: _chapterId,
                onChapterIdChanged: (v) => setState(() => _chapterId = v),
                topicId: _topicId,
                onTopicIdChanged: (v) => setState(() => _topicId = v),
                showIndexFilters: true,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DropdownButton<String?>(
                      value: _examId,
                      hint: const Text('Exam'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All exams')),
                        for (final exam in _exams)
                          DropdownMenuItem(value: exam.id, child: Text(exam.title)),
                      ],
                      onChanged: (v) => setState(() => _examId = v),
                    ),
                    DropdownButton<RagDomain?>(
                      value: _domain,
                      hint: const Text('RAG Domain'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All domains')),
                        for (final d in RagDomain.values)
                          DropdownMenuItem(
                            value: d,
                            child: Text(ragDomainLabel(d)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _domain = v),
                    ),
                    DropdownButton<String?>(
                      value: _contentType,
                      hint: const Text('Content Type'),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('All types')),
                        DropdownMenuItem(
                          value: kNotesPdfContentType,
                          child: Text('PDF Notes'),
                        ),
                        DropdownMenuItem(
                          value: kFlashcardContentType,
                          child: Text('Flashcard'),
                        ),
                        DropdownMenuItem(
                          value: kSmartTrickContentType,
                          child: Text('Smart Trick'),
                        ),
                        DropdownMenuItem(
                          value: kCurrentAffairsContentType,
                          child: Text('Current Affairs'),
                        ),
                        DropdownMenuItem(
                          value: kAiLessonContentType,
                          child: Text('AI Lesson'),
                        ),
                        DropdownMenuItem(
                          value: kPyqContentType,
                          child: Text('PYQ'),
                        ),
                        DropdownMenuItem(
                          value: kSyllabusContentType,
                          child: Text('Syllabus'),
                        ),
                        DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                        DropdownMenuItem(value: 'notes', child: Text('Notes')),
                      ],
                      onChanged: (v) => setState(() => _contentType = v),
                    ),
                    DropdownButton<RagAdminStatusFilter>(
                      value: _ragStatus,
                      items: const [
                        DropdownMenuItem(
                          value: RagAdminStatusFilter.all,
                          child: Text('All statuses'),
                        ),
                        DropdownMenuItem(
                          value: RagAdminStatusFilter.draft,
                          child: Text('Draft'),
                        ),
                        DropdownMenuItem(
                          value: RagAdminStatusFilter.processing,
                          child: Text('Processing'),
                        ),
                        DropdownMenuItem(
                          value: RagAdminStatusFilter.indexed,
                          child: Text('Ready'),
                        ),
                        DropdownMenuItem(
                          value: RagAdminStatusFilter.failed,
                          child: Text('Failed'),
                        ),
                        DropdownMenuItem(
                          value: RagAdminStatusFilter.needsReindex,
                          child: Text('Needs Re-index'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _ragStatus = v);
                      },
                    ),
                  ],
                ),
              ),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: EmptyState(
                    message: 'No knowledge sources yet. Tap + to add the first one.',
                    icon: Icons.menu_book_outlined,
                  ),
                )
              else if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: EmptyState(
                    message: 'No sources match these filters.',
                    icon: Icons.search_off_rounded,
                  ),
                )
              else
                for (final item in filtered)
                  Card(
                    margin: const EdgeInsets.only(top: 12),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        children: [
                          AdminListTile(
                            title: item.title,
                            subtitle: _subtitle(item),
                            icon: Icons.source_rounded,
                            onPreview: _busy.contains(item.id)
                                ? null
                                : () => _preview(item),
                            onEdit: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    AdminRagSourceFormScreen(existing: item),
                              ),
                            ),
                            onDelete: _busy.contains(item.id)
                                ? () {}
                                : () => _delete(item),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _statusColor(ragManagementStatus(item))
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    ragManagementStatusToString(
                                      ragManagementStatus(item),
                                    ),
                                    style: TextStyle(
                                      color: _statusColor(
                                        ragManagementStatus(item),
                                      ),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (_busy.contains(item.id))
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                else
                                  Switch(
                                    value: item.published,
                                    onChanged: item.isReady
                                        ? (v) => _togglePublished(item, v)
                                        : null,
                                  ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                            child: Wrap(
                              spacing: 4,
                              children: [
                                TextButton(
                                  onPressed: () => _index(item, force: false),
                                  child: const Text('Index'),
                                ),
                                TextButton(
                                  onPressed: () => _index(item, force: true),
                                  child: const Text('Re-index'),
                                ),
                                TextButton(
                                  onPressed: () => _retry(item),
                                  child: const Text('Retry'),
                                ),
                                TextButton(
                                  onPressed: () => _removeFromRag(item),
                                  child: const Text('Remove from RAG'),
                                ),
                                TextButton(
                                  onPressed: () => _preview(item),
                                  child: const Text('Preview'),
                                ),
                                TextButton(
                                  onPressed: _scrollToConsole,
                                  child: const Text('Search/Test'),
                                ),
                              ],
                            ),
                          ),
                          if (item.errorMessage.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Text(
                                item.errorMessage,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 16),
              AdminRagTestConsole(
                key: _consoleKey,
                initialExamId: _examId ?? kDefaultExamId,
                initialSubjectId: _subjectId ?? '',
                initialChapterId: _chapterId ?? '',
                initialTopicId: _topicId ?? '',
              ),
              const SizedBox(height: 48),
            ],
          );
        },
      ),
    );
  }
}

class _RagStatCard extends StatelessWidget {
  const _RagStatCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
