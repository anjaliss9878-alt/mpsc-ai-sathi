import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_index_picker.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_preview.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/current_affair_item.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/content_knowledge_indexer.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';

class AdminCurrentAffairFormScreen extends StatefulWidget {
  const AdminCurrentAffairFormScreen({super.key, this.existing});

  final CurrentAffairItem? existing;

  @override
  State<AdminCurrentAffairFormScreen> createState() =>
      _AdminCurrentAffairFormScreenState();
}

class _AdminCurrentAffairFormScreenState
    extends State<AdminCurrentAffairFormScreen> {
  late final _titleController =
      TextEditingController(text: widget.existing?.title ?? '');
  late final _categoryController =
      TextEditingController(text: widget.existing?.category ?? 'General');
  late final _descriptionController =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _detailController = TextEditingController(
    text: widget.existing?.detailedExplanation ?? '',
  );
  late final _sourceController =
      TextEditingController(text: widget.existing?.source ?? '');
  late final _tagsController = TextEditingController(
    text: (widget.existing?.tags ?? const []).join(', '),
  );
  late final _quizQuestionController =
      TextEditingController(text: widget.existing?.quizQuestion ?? '');
  late final List<TextEditingController> _quizOptions = List.generate(
    4,
    (i) => TextEditingController(
      text: (widget.existing?.quizOptions.length ?? 0) > i
          ? widget.existing!.quizOptions[i]
          : '',
    ),
  );
  late int _quizCorrect = widget.existing?.quizCorrectIndex ?? 0;
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  late NoteWorkflowStatus _status =
      widget.existing?.status ?? NoteWorkflowStatus.draft;
  late ContentIndexSelection _index = ContentIndexSelection(
    examId: widget.existing?.examId.isNotEmpty == true
        ? widget.existing!.examId
        : kDefaultExamId,
    targetGroup: targetGroupFromString(widget.existing?.targetGroup ?? 'both'),
    subjectId: widget.existing?.subjectId ?? '',
    chapterId: widget.existing?.chapterId ?? '',
    topicId: widget.existing?.topicId ?? '',
  );
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _detailController.dispose();
    _sourceController.dispose();
    _tagsController.dispose();
    _quizQuestionController.dispose();
    for (final c in _quizOptions) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  CurrentAffairItem _buildItem({String? id}) {
    final options = _quizOptions.map((c) => c.text.trim()).toList();
    final filled = options.where((o) => o.isNotEmpty).toList();
    return CurrentAffairItem(
      id: id ?? widget.existing?.id ?? '',
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      category: _categoryController.text.trim().isEmpty
          ? 'General'
          : _categoryController.text.trim(),
      date: _date,
      pdfUrl: widget.existing?.pdfUrl ?? '',
      monthlyPdfUrl: widget.existing?.monthlyPdfUrl ?? '',
      quizQuestion: _quizQuestionController.text.trim(),
      quizOptions: filled.length >= 2 ? filled : const [],
      quizCorrectIndex: _quizCorrect,
      examId: _index.examId,
      targetGroup: targetGroupToString(_index.targetGroup),
      subjectId: _index.subjectId,
      chapterId: _index.chapterId,
      topicId: _index.topicId,
      detailedExplanation: _detailController.text.trim(),
      source: _sourceController.text.trim(),
      tags: _tagsController.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
      published: contentWorkflowPublishedFlag(_status),
      status: _status,
      createdAt: widget.existing?.createdAt,
    );
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      showAdminMessage(context, 'Title is required.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      var item = _buildItem();
      if (widget.existing == null) {
        final id = await currentAffairsRepository.add(item);
        item = _buildItem(id: id);
        await auditLogRepository.log(
          action: 'create',
          module: 'Current Affairs',
          targetLabel: item.title,
        );
      } else {
        await currentAffairsRepository.update(item);
        await auditLogRepository.log(
          action: 'update',
          module: 'Current Affairs',
          targetLabel: item.title,
        );
      }
      try {
        await contentKnowledgeIndexer.syncCurrentAffair(item);
      } catch (_) {}
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminFormScaffold(
      title: widget.existing == null
          ? 'Add Current Affair'
          : 'Edit Current Affair',
      isSaving: _isSaving,
      onSave: _save,
      saveLabel: _status == NoteWorkflowStatus.published
          ? 'Save & Publish'
          : 'Save Draft',
      children: [
        const AdminSectionLabel(label: 'Related topic (optional)'),
        ContentIndexPicker(
          initial: _index,
          onChanged: (v) => _index = v,
        ),
        const SizedBox(height: 14),
        WorkflowStatusDropdown(
          value: _status,
          onChanged: (v) => setState(() => _status = v),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _categoryController,
          decoration: const InputDecoration(
            labelText: 'Category (e.g. National, State, International)',
          ),
        ),
        const SizedBox(height: 14),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Date: ${_date.day}/${_date.month}/${_date.year}'),
          trailing: const Icon(Icons.calendar_today_rounded),
          onTap: _pickDate,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _descriptionController,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Short summary'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _detailController,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(labelText: 'Detailed explanation'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _sourceController,
          decoration: const InputDecoration(labelText: 'Source'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _tagsController,
          decoration: const InputDecoration(labelText: 'Tags (comma separated)'),
        ),
        const AdminSectionLabel(label: 'Optional quiz'),
        TextField(
          controller: _quizQuestionController,
          decoration: const InputDecoration(labelText: 'Quiz question'),
        ),
        const SizedBox(height: 10),
        ...List.generate(4, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Radio<int>(
                  value: i,
                  groupValue: _quizCorrect,
                  onChanged: (v) => setState(() => _quizCorrect = v ?? 0),
                ),
                Expanded(
                  child: TextField(
                    controller: _quizOptions[i],
                    decoration: InputDecoration(
                      labelText: 'Option ${String.fromCharCode(65 + i)}',
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => showCurrentAffairPreview(context, _buildItem()),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Preview'),
        ),
      ],
    );
  }
}
