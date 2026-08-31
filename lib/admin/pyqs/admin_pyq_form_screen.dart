import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_index_picker.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_preview.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/content_knowledge_indexer.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/utils/correct_answer.dart';

class AdminPyqFormScreen extends StatefulWidget {
  const AdminPyqFormScreen({super.key, this.existing});

  final PyqItem? existing;

  @override
  State<AdminPyqFormScreen> createState() => _AdminPyqFormScreenState();
}

class _AdminPyqFormScreenState extends State<AdminPyqFormScreen> {
  late final _titleController =
      TextEditingController(text: widget.existing?.title ?? '');
  late final _subtitleController =
      TextEditingController(text: widget.existing?.subtitle ?? '');
  late final _fileUrlController =
      TextEditingController(text: widget.existing?.fileUrl ?? '');
  late final _yearController =
      TextEditingController(text: widget.existing?.year?.toString() ?? '');
  late final _questionController =
      TextEditingController(text: widget.existing?.question ?? '');
  late final _answerController =
      TextEditingController(text: widget.existing?.answer ?? '');
  late final _explanationController =
      TextEditingController(text: widget.existing?.explanation ?? '');
  late final _sourceController =
      TextEditingController(text: widget.existing?.source ?? '');
  late final _tagsController = TextEditingController(
    text: (widget.existing?.tags ?? const []).join(', '),
  );
  late final List<TextEditingController> _optionControllers = List.generate(
    4,
    (i) => TextEditingController(
      text: (widget.existing?.options.length ?? 0) > i
          ? widget.existing!.options[i]
          : '',
    ),
  );

  late bool _isStructured = widget.existing?.isStructuredQuestion ?? true;
  late NoteWorkflowStatus _status =
      widget.existing?.status ?? NoteWorkflowStatus.draft;
  late String _difficulty = widget.existing?.difficulty ?? 'Medium';
  late int _correctIndex = widget.existing?.correctIndex ?? 0;
  late ContentIndexSelection _index = ContentIndexSelection(
    examId: widget.existing?.examId.isNotEmpty == true
        ? widget.existing!.examId
        : kDefaultExamId,
    targetGroup: targetGroupFromString(widget.existing?.targetGroup),
    subjectId: widget.existing?.subjectId ?? '',
    chapterId: widget.existing?.chapterId ?? '',
    topicId: widget.existing?.topicId ?? '',
    subjectTitle: widget.existing?.subject ?? '',
  );
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _fileUrlController.dispose();
    _yearController.dispose();
    _questionController.dispose();
    _answerController.dispose();
    _explanationController.dispose();
    _sourceController.dispose();
    _tagsController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  PyqItem _buildItem() {
    final options = _optionControllers.map((c) => c.text.trim()).toList();
    final filled = options.where((o) => o.isNotEmpty).toList();
    final answer = _answerController.text.trim().isNotEmpty
        ? _answerController.text.trim()
        : (filled.length == 4 ? correctAnswerLetter(_correctIndex) : '');
    final question = _isStructured ? _questionController.text.trim() : '';
    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : (question.isNotEmpty
            ? question
            : 'MPSC Combine PYQ ${widget.existing?.year ?? ''}');
    return PyqItem(
      id: widget.existing?.id ?? '',
      title: title,
      subtitle: _subtitleController.text.trim(),
      fileUrl: _isStructured ? '' : _fileUrlController.text.trim(),
      order: widget.existing?.order ?? DateTime.now().millisecondsSinceEpoch,
      year: int.tryParse(_yearController.text.trim()),
      examName: 'MPSC Combine',
      question: question,
      answer: _isStructured ? answer : '',
      explanation: _isStructured ? _explanationController.text.trim() : '',
      subject: _index.subjectTitle,
      subjectId: _index.subjectId,
      chapterId: _index.chapterId,
      tags: _tagsController.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
      published: contentWorkflowPublishedFlag(_status),
      examId: _index.examId,
      targetGroup: targetGroupToString(_index.targetGroup),
      topicId: _index.topicId,
      options: filled.length == 4 ? filled : const [],
      correctIndex: _correctIndex,
      difficulty: _difficulty,
      source: _sourceController.text.trim(),
      status: _status,
    );
  }

  Future<void> _save() async {
    if (_index.subjectId.isEmpty ||
        _index.chapterId.isEmpty ||
        _index.topicId.isEmpty) {
      showAdminMessage(context, 'Select subject, chapter and topic.');
      return;
    }
    if (_isStructured && _questionController.text.trim().isEmpty) {
      showAdminMessage(context, 'Question text is required.');
      return;
    }
    if (!_isStructured && _titleController.text.trim().isEmpty) {
      showAdminMessage(context, 'Title is required for a paper link.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      var item = _buildItem();
      if (widget.existing == null) {
        final id = await pyqRepository.add(item);
        item = item.copyWith(id: id);
        await auditLogRepository.log(
          action: 'create',
          module: 'PYQs',
          targetLabel: item.title,
        );
      } else {
        await pyqRepository.update(item);
        await auditLogRepository.log(
          action: 'update',
          module: 'PYQs',
          targetLabel: item.title,
        );
      }
      try {
        await contentKnowledgeIndexer.syncPyq(item);
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
      title: widget.existing == null ? 'Add PYQ' : 'Edit PYQ',
      isSaving: _isSaving,
      onSave: _save,
      saveLabel: _status == NoteWorkflowStatus.published ? 'Save & Publish' : 'Save Draft',
      children: [
        const AdminSectionLabel(label: 'Content index'),
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
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _yearController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Year'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _difficulty,
                decoration: const InputDecoration(labelText: 'Difficulty'),
                items: const [
                  DropdownMenuItem(value: 'Easy', child: Text('Easy')),
                  DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'Hard', child: Text('Hard')),
                ],
                onChanged: (v) => setState(() => _difficulty = v ?? 'Medium'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Title (optional — defaults to question)',
          ),
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
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Structured question (Q & A)'),
          subtitle: const Text('Off = paper / solutions link only'),
          value: _isStructured,
          onChanged: (v) => setState(() => _isStructured = v),
        ),
        if (_isStructured) ...[
          const AdminSectionLabel(label: 'Question'),
          TextField(
            controller: _questionController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Question'),
          ),
          const AdminSectionLabel(label: 'Options (optional)'),
          ...List.generate(4, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Radio<int>(
                    value: i,
                    groupValue: _correctIndex,
                    onChanged: (value) =>
                        setState(() => _correctIndex = value ?? 0),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _optionControllers[i],
                      decoration:
                          InputDecoration(labelText: 'Option ${String.fromCharCode(65 + i)}'),
                    ),
                  ),
                ],
              ),
            );
          }),
          TextField(
            controller: _answerController,
            decoration: const InputDecoration(
              labelText: 'Correct answer (letter or text)',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _explanationController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Explanation'),
          ),
        ] else ...[
          TextField(
            controller: _subtitleController,
            decoration: const InputDecoration(labelText: 'Subtitle'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _fileUrlController,
            decoration: const InputDecoration(
              labelText: 'Paper / solutions link',
              hintText: 'https://...',
            ),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => showPyqPreview(context, _buildItem()),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Preview'),
        ),
      ],
    );
  }
}
