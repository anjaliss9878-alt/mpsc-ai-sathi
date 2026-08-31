import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_index_picker.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_preview.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';

const List<String> _difficulties = ['Easy', 'Medium', 'Hard'];

class AdminMcqFormScreen extends StatefulWidget {
  const AdminMcqFormScreen({super.key, this.existing, this.setTitle = ''});

  final McqItem? existing;
  final String setTitle;

  @override
  State<AdminMcqFormScreen> createState() => _AdminMcqFormScreenState();
}

class _AdminMcqFormScreenState extends State<AdminMcqFormScreen> {
  late final _setTitleController = TextEditingController(
    text: widget.existing?.setTitle ?? widget.setTitle,
  );
  late final _questionController =
      TextEditingController(text: widget.existing?.question ?? '');
  late final _explanationController =
      TextEditingController(text: widget.existing?.explanation ?? '');
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
  late String _difficulty = widget.existing?.difficulty ?? 'Medium';
  late int _correctIndex = widget.existing?.correctIndex ?? 0;
  late NoteWorkflowStatus _status =
      widget.existing?.status ?? NoteWorkflowStatus.draft;
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
    _setTitleController.dispose();
    _questionController.dispose();
    _explanationController.dispose();
    _tagsController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  McqItem _buildItem() {
    return McqItem(
      id: widget.existing?.id ?? '',
      setTitle: _setTitleController.text.trim(),
      subject: _index.subjectTitle,
      difficulty: _difficulty,
      question: _questionController.text.trim(),
      options: _optionControllers.map((c) => c.text.trim()).toList(),
      correctIndex: _correctIndex,
      explanation: _explanationController.text.trim(),
      order: widget.existing?.order ?? DateTime.now().millisecondsSinceEpoch,
      tags: _tagsController.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
      subjectId: _index.subjectId,
      chapterId: _index.chapterId,
      published: contentWorkflowPublishedFlag(_status),
      examId: _index.examId,
      targetGroup: targetGroupToString(_index.targetGroup),
      topicId: _index.topicId,
      status: _status,
    );
  }

  Future<void> _save() async {
    final options = _optionControllers.map((c) => c.text.trim()).toList();
    if (_questionController.text.trim().isEmpty ||
        _setTitleController.text.trim().isEmpty ||
        options.any((o) => o.isEmpty)) {
      showAdminMessage(
        context,
        'Set title, question and all 4 options are required.',
      );
      return;
    }
    if (!_index.isComplete) {
      showAdminMessage(context, 'Select subject, chapter and topic.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final item = _buildItem();
      if (widget.existing == null) {
        await mcqRepository.add(item);
        await auditLogRepository.log(
          action: 'create',
          module: 'MCQs',
          targetLabel: item.question,
        );
      } else {
        await mcqRepository.update(item);
        await auditLogRepository.log(
          action: 'update',
          module: 'MCQs',
          targetLabel: item.question,
        );
      }
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
      title: widget.existing == null ? 'Add MCQ' : 'Edit MCQ',
      isSaving: _isSaving,
      onSave: _save,
      saveLabel:
          _status == NoteWorkflowStatus.published ? 'Save & Publish' : 'Save Draft',
      children: [
        TextField(
          controller: _setTitleController,
          decoration: const InputDecoration(
            labelText: 'MCQ set title',
            hintText: 'e.g. Article 14 — Practice Set',
          ),
        ),
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
        DropdownButtonFormField<String>(
          value: _difficulty,
          decoration: const InputDecoration(labelText: 'Difficulty'),
          items: _difficulties
              .map((d) => DropdownMenuItem(value: d, child: Text(d)))
              .toList(),
          onChanged: (value) => setState(() => _difficulty = value ?? 'Medium'),
        ),
        const AdminSectionLabel(label: 'Question'),
        TextField(
          controller: _questionController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Question text'),
        ),
        const AdminSectionLabel(label: 'Options (select the correct one)'),
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
                    decoration: InputDecoration(
                      labelText: 'Option ${String.fromCharCode(65 + i)}',
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const AdminSectionLabel(label: 'Explanation'),
        TextField(
          controller: _explanationController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Explanation'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _tagsController,
          decoration: const InputDecoration(labelText: 'Tags (comma separated)'),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => showMcqPreview(context, _buildItem()),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Preview'),
        ),
      ],
    );
  }
}
