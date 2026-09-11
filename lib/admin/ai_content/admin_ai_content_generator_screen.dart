import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_select_field.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/data/student_curriculum.dart';
import 'package:mpsc_combine_ai/models/ai_generated_content.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/ai_content_generation_service.dart';
import 'package:mpsc_combine_ai/services/ai_generated_content_repository.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Admin → AI Content Generator (RAG-grounded drafts, never auto-publish).
class AdminAiContentGeneratorScreen extends StatefulWidget {
  const AdminAiContentGeneratorScreen({super.key});

  @override
  State<AdminAiContentGeneratorScreen> createState() =>
      _AdminAiContentGeneratorScreenState();
}

class _AdminAiContentGeneratorScreenState
    extends State<AdminAiContentGeneratorScreen> {
  bool _loaded = false;
  bool _busy = false;
  String? _loadError;
  String _progress = '';
  String _batchId = '';

  String _examId = kGroupBCombinedExamId;
  String _subjectId = '';
  String _chapterId = '';
  String _topicId = '';
  String _sourceId = '';
  String _difficulty = 'Medium';
  int _mcqCount = 10;
  int _flashcardCount = 10;
  final _customMcq = TextEditingController();
  final _customFlash = TextEditingController();

  List<ExamItem> _exams = const [];
  List<SubjectItem> _subjects = const [];
  List<ChapterItem> _chapters = const [];
  List<ChapterItem> _topics = const [];
  List<RagSource> _sources = const [];
  List<AiGeneratedContentItem> _drafts = const [];

  final Set<AiGeneratedContentType> _types = {
    AiGeneratedContentType.mcq,
    AiGeneratedContentType.flashcard,
    AiGeneratedContentType.revisionSummary,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _customMcq.dispose();
    _customFlash.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await notesRepository.ensureDefaultExam();
      final exams = await notesRepository.getExamsOnce();
      final subjects = await notesRepository.getSubjectsOnce();
      final sources = await ragSourceRepository.getPublishedReadyOnce();
      if (!mounted) return;
      setState(() {
        _exams = exams;
        _subjects = subjects;
        _sources = sources;
        _loaded = true;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _loadError = formatAdminError(e);
      });
    }
  }

  List<SubjectItem> get _examSubjects =>
      adminSubjectsForExam(_subjects, _examId);

  List<RagSource> get _filteredSources {
    return _sources.where((s) {
      if (!s.published || !s.isReady) return false;
      if (_examId.isNotEmpty &&
          s.examId.isNotEmpty &&
          s.examId != _examId) {
        return false;
      }
      if (_subjectId.isNotEmpty &&
          s.subjectId.isNotEmpty &&
          s.subjectId != _subjectId) {
        return false;
      }
      if (_chapterId.isNotEmpty &&
          s.chapterId.isNotEmpty &&
          s.chapterId != _chapterId) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _onExamChanged(String examId) async {
    setState(() {
      _examId = examId;
      _subjectId = '';
      _chapterId = '';
      _topicId = '';
      _chapters = const [];
      _topics = const [];
      _sourceId = '';
    });
  }

  Future<void> _onSubjectChanged(String subjectId) async {
    final chapters = await notesRepository.getChaptersOnce(subjectId);
    if (!mounted) return;
    setState(() {
      _subjectId = subjectId;
      _chapterId = '';
      _topicId = '';
      _chapters = chapters.where((c) => c.parentChapterId.isEmpty).toList();
      _topics = const [];
      _sourceId = '';
    });
  }

  Future<void> _onChapterChanged(String chapterId) async {
    final topics = await notesRepository.getChildChaptersOnce(chapterId);
    if (!mounted) return;
    setState(() {
      _chapterId = chapterId;
      _topics = topics;
      _topicId = topics.isEmpty ? chapterId : '';
      _sourceId = '';
    });
  }

  int _resolvedMcqCount() {
    final custom = int.tryParse(_customMcq.text.trim());
    if (custom != null && custom > 0) return custom.clamp(1, 50);
    return _mcqCount.clamp(1, 50);
  }

  int _resolvedFlashCount() {
    final custom = int.tryParse(_customFlash.text.trim());
    if (custom != null && custom > 0) return custom.clamp(1, 30);
    return _flashcardCount.clamp(1, 30);
  }

  Future<void> _generate({bool retry = false}) async {
    if (_subjectId.isEmpty || _chapterId.isEmpty) {
      showAdminMessage(context, 'Select Exam, Subject and Chapter.');
      return;
    }
    if (_sourceId.isEmpty) {
      showAdminMessage(context, 'Select a published Ready RAG source.');
      return;
    }
    if (_types.isEmpty) {
      showAdminMessage(context, 'Select at least one content type.');
      return;
    }

    final subject = _examSubjects.where((s) => s.id == _subjectId).firstOrNull;
    final chapter = _chapters.where((c) => c.id == _chapterId).firstOrNull;
    final topic = _topics.where((t) => t.id == _topicId).firstOrNull;
    final source = _sources.where((s) => s.id == _sourceId).firstOrNull;
    final exam = _exams.where((e) => e.id == _examId).firstOrNull;

    setState(() {
      _busy = true;
      _progress = 'Starting…';
    });

    try {
      final request = AiContentGenerationRequest(
        examId: _examId,
        subjectId: _subjectId,
        chapterId: _chapterId,
        topicId: _topicId.isEmpty ? _chapterId : _topicId,
        sourceId: _sourceId,
        examTitle: exam?.title ?? '',
        subjectTitle: subject?.title ?? '',
        chapterTitle: chapter?.title ?? '',
        topicTitle: topic?.title ?? '',
        sourceTitle: source?.title ?? '',
        types: Set.of(_types),
        mcqCount: _resolvedMcqCount(),
        flashcardCount: _resolvedFlashCount(),
        difficulty: _difficulty,
      );

      final result = await aiContentGenerationService.generate(
        request,
        reuseBatchId: retry && _batchId.isNotEmpty ? _batchId : null,
        onProgress: (stage, detail) {
          if (!mounted) return;
          setState(() => _progress = detail.isEmpty
              ? aiGenerationStageLabel(stage)
              : detail);
        },
      );

      final drafts =
          await aiGeneratedContentRepository.getBatchOnce(result.batchId);
      await auditLogRepository.log(
        action: retry ? 'ai-content-retry' : 'ai-content-generate',
        module: 'AI Content Generator',
        targetLabel: request.topicLabel,
        details:
            'batch=${result.batchId} saved=${result.savedCount} fails=${result.failures.length} hits=${result.hitCount}',
      );

      if (!mounted) return;
      setState(() {
        _batchId = result.batchId;
        _drafts = drafts;
        _progress = result.hasFailures
            ? 'Partial success: ${result.savedCount} saved, ${result.failures.length} failed.'
            : 'Saved ${result.savedCount} draft(s). Review before publish.';
      });

      if (result.insufficientEvidence) {
        showAdminMessage(
          context,
          'Not enough RAG evidence for this topic/source.',
        );
      } else if (result.hasFailures) {
        showAdminMessage(
          context,
          'Some types failed. Successful drafts were kept — use Retry.',
        );
      } else {
        showAdminMessage(
          context,
          '${result.savedCount} AI drafts saved. Not visible to students until you Publish.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _progress = 'Failed');
        showAdminError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshDrafts() async {
    if (_batchId.isEmpty) return;
    final drafts =
        await aiGeneratedContentRepository.getBatchOnce(_batchId);
    if (mounted) setState(() => _drafts = drafts);
  }

  Future<void> _deleteDraft(AiGeneratedContentItem item) async {
    final ok = await confirmDelete(
      context,
      aiGeneratedContentTypeLabel(item.contentType),
    );
    if (!ok) return;
    await aiGeneratedContentRepository.delete(item.id);
    await _refreshDrafts();
  }

  Future<void> _publishDraft(AiGeneratedContentItem item) async {
    setState(() => _busy = true);
    try {
      final id = await aiContentGenerationService.publishDraft(item);
      await auditLogRepository.log(
        action: 'ai-content-publish',
        module: 'AI Content Generator',
        targetLabel: aiGeneratedContentTypeLabel(item.contentType),
        details: 'promoted=$id from ${item.id}',
      );
      await _refreshDrafts();
      if (mounted) {
        showAdminMessage(
          context,
          'Published to live collection. Students see it only if workflow is published.',
        );
      }
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approveDraft(AiGeneratedContentItem item) async {
    if (!item.isDraft && item.status != NoteWorkflowStatus.aiGenerated) {
      showAdminMessage(context, 'Only draft/AI items can be approved.');
      return;
    }
    setState(() => _busy = true);
    try {
      await aiGeneratedContentRepository.update(
        item.copyWith(status: NoteWorkflowStatus.approved),
      );
      await auditLogRepository.log(
        action: 'ai-content-approve',
        module: 'AI Content Generator',
        targetLabel: aiGeneratedContentTypeLabel(item.contentType),
        details: item.id,
      );
      await _refreshDrafts();
      if (mounted) {
        showAdminMessage(
          context,
          'Marked approved. Still not student-visible until Publish.',
        );
      }
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showPreview(AiGeneratedContentItem item) async {
    final controller = TextEditingController(
      text: item.content.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\n\n'),
    );
    final edited = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(aiGeneratedContentTypeLabel(item.contentType)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: TextField(
              controller: controller,
              maxLines: 18,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Edit content fields (key: value per block)',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save edits'),
          ),
        ],
      ),
    );
    if (edited != true) {
      controller.dispose();
      return;
    }
    final next = Map<String, dynamic>.from(item.content);
    for (final block in controller.text.split(RegExp(r'\n\s*\n'))) {
      final idx = block.indexOf(':');
      if (idx <= 0) continue;
      final key = block.substring(0, idx).trim();
      final value = block.substring(idx + 1).trim();
      if (key.isEmpty) continue;
      next[key] = value;
    }
    controller.dispose();
    await aiGeneratedContentRepository.update(item.copyWith(content: next));
    await _refreshDrafts();
    if (mounted) {
      showAdminMessage(context, 'Draft updated (still not published).');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: LoadingState());
    }

    final examItems = uniqueAdminSelectItems([
      for (final e in (_exams.isEmpty
          ? [ExamItem.groupBCombined(), ExamItem.mpscCombine()]
          : _exams))
        AdminSelectItem(id: e.id, label: e.title),
    ]);
    final subjectItems = uniqueAdminSelectItems([
      for (final s in _examSubjects) AdminSelectItem(id: s.id, label: s.title),
    ]);
    final chapterItems = [
      for (final c in _chapters) AdminSelectItem(id: c.id, label: c.title),
    ];
    final topicItems = _topics.isEmpty && _chapterId.isNotEmpty
        ? [
            AdminSelectItem(
              id: _chapterId,
              label: 'Use chapter as topic',
            ),
          ]
        : [
            for (final t in _topics) AdminSelectItem(id: t.id, label: t.title),
          ];
    final sourceItems = [
      for (final s in _filteredSources)
        AdminSelectItem(
          id: s.id,
          label: '${s.title} · Ready',
        ),
    ];

    return AdminFormScaffold(
      title: 'AI Content Generator',
      isSaving: _busy,
      canSave: !_busy &&
          _subjectId.isNotEmpty &&
          _chapterId.isNotEmpty &&
          _sourceId.isNotEmpty &&
          _types.isNotEmpty,
      saveLabel: 'Generate with AI',
      onSave: () => _generate(retry: false),
      maxContentWidth: 920,
      children: [
        if (_loadError != null)
          Text('Load warning: $_loadError',
              style: TextStyle(color: Colors.red.shade800)),
        AdminFormSection(
          title: 'Content index',
          subtitle: 'Exam → Subject → Chapter → Topic',
          icon: Icons.account_tree_rounded,
          children: [
            AdminSelectField(
              label: 'Exam',
              value: committedSelectId(_examId, examItems.map((e) => e.id)),
              items: examItems,
              onChanged: _onExamChanged,
            ),
            const SizedBox(height: 12),
            AdminSelectField(
              label: 'Subject',
              value:
                  committedSelectId(_subjectId, subjectItems.map((e) => e.id)),
              items: subjectItems,
              onChanged: _onSubjectChanged,
            ),
            const SizedBox(height: 12),
            AdminSelectField(
              label: 'Chapter',
              value:
                  committedSelectId(_chapterId, chapterItems.map((e) => e.id)),
              items: chapterItems,
              onChanged: _onChapterChanged,
            ),
            const SizedBox(height: 12),
            AdminSelectField(
              label: 'Topic (optional)',
              value: committedSelectId(_topicId, topicItems.map((e) => e.id)),
              items: topicItems,
              onChanged: (v) => setState(() => _topicId = v),
            ),
          ],
        ),
        AdminFormSection(
          title: 'Reference RAG source',
          subtitle:
              'Only published + Ready sources. Generation uses retrieved chunks — not the full PDF.',
          icon: Icons.auto_stories_rounded,
          children: [
            if (sourceItems.isEmpty)
              const Text(
                'No published Ready RAG sources match this exam/subject. '
                'Index and publish a PDF in RAG Management first.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else
              AdminSelectField(
                label: 'RAG Source',
                value:
                    committedSelectId(_sourceId, sourceItems.map((e) => e.id)),
                items: sourceItems,
                onChanged: (v) => setState(() => _sourceId = v),
              ),
          ],
        ),
        AdminFormSection(
          title: 'Generate',
          subtitle: 'All output is DRAFT. Never labelled as actual PYQ.',
          icon: Icons.auto_awesome_rounded,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final type in AiGeneratedContentType.values)
                  FilterChip(
                    label: Text(aiGeneratedContentTypeLabel(type)),
                    selected: _types.contains(type),
                    onSelected: (on) {
                      setState(() {
                        if (on) {
                          _types.add(type);
                        } else {
                          _types.remove(type);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text('MCQ count',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final n in const [10, 20, 30, 50])
                  ChoiceChip(
                    label: Text('$n'),
                    selected: _mcqCount == n && _customMcq.text.isEmpty,
                    onSelected: (_) {
                      setState(() {
                        _mcqCount = n;
                        _customMcq.clear();
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _customMcq,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Custom MCQ count (1–50)',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Text('Flashcard count',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final n in const [10, 20, 30])
                  ChoiceChip(
                    label: Text('$n'),
                    selected: _flashcardCount == n && _customFlash.text.isEmpty,
                    onSelected: (_) {
                      setState(() {
                        _flashcardCount = n;
                        _customFlash.clear();
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _customFlash,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Custom flashcard count (1–30)',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: ValueKey('ai-diff-$_difficulty'),
              initialValue: _difficulty,
              decoration: const InputDecoration(labelText: 'Difficulty'),
              items: const [
                DropdownMenuItem(value: 'Easy', child: Text('Easy')),
                DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                DropdownMenuItem(value: 'Hard', child: Text('Hard')),
                DropdownMenuItem(value: 'Mixed', child: Text('Mixed')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _difficulty = v);
              },
            ),
            if (_busy || _progress.isNotEmpty) ...[
              const SizedBox(height: 16),
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(_progress,
                  style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ],
        ),
        if (_drafts.isNotEmpty)
          AdminFormSection(
            title: 'Generated content',
            subtitle:
                'Preview · delete · publish. Retry adds only missing items (no duplicates).',
            icon: Icons.fact_check_rounded,
            trailing: TextButton.icon(
              onPressed: _busy ? null : () => _generate(retry: true),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry failed'),
            ),
            children: [
              for (final item in _drafts)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  color: AppColors.skySoft,
                  child: ListTile(
                    title: Text(
                      aiGeneratedContentTypeLabel(item.contentType),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      [
                        noteWorkflowStatusLabel(item.status),
                        if (item.sourceCitation.isNotEmpty)
                          item.sourceCitation,
                        if (item.promotedDocId.isNotEmpty)
                          'Live: ${item.promotedCollection}/${item.promotedDocId}',
                        '${item.content}',
                      ].join(' · '),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Preview / Edit',
                          onPressed: () => _showPreview(item),
                          icon: const Icon(Icons.visibility_outlined),
                        ),
                        if (item.isDraft ||
                            item.status == NoteWorkflowStatus.aiGenerated)
                          IconButton(
                            tooltip: 'Approve',
                            onPressed:
                                _busy ? null : () => _approveDraft(item),
                            icon: const Icon(Icons.check_circle_outline),
                          ),
                        if (item.isDraft ||
                            item.status == NoteWorkflowStatus.approved)
                          IconButton(
                            tooltip: 'Publish',
                            onPressed:
                                _busy ? null : () => _publishDraft(item),
                            icon: const Icon(Icons.publish_rounded),
                          ),
                        IconButton(
                          tooltip: 'Delete draft',
                          onPressed: _busy ? null : () => _deleteDraft(item),
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

extension _FirstOrNullAiGen<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
