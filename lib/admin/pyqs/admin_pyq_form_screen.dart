import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';

class AdminPyqFormScreen extends StatefulWidget {
  const AdminPyqFormScreen({super.key, this.existing});

  final PyqItem? existing;

  @override
  State<AdminPyqFormScreen> createState() => _AdminPyqFormScreenState();
}

class _AdminPyqFormScreenState extends State<AdminPyqFormScreen> {
  late final _titleController = TextEditingController(text: widget.existing?.title ?? '');
  late final _subtitleController =
      TextEditingController(text: widget.existing?.subtitle ?? '');
  late final _fileUrlController =
      TextEditingController(text: widget.existing?.fileUrl ?? '');
  late final _yearController =
      TextEditingController(text: widget.existing?.year?.toString() ?? '');
  late final _examNameController =
      TextEditingController(text: widget.existing?.examName ?? '');
  late final _questionController =
      TextEditingController(text: widget.existing?.question ?? '');
  late final _answerController =
      TextEditingController(text: widget.existing?.answer ?? '');
  late final _explanationController =
      TextEditingController(text: widget.existing?.explanation ?? '');
  late final _subjectController =
      TextEditingController(text: widget.existing?.subject ?? '');
  late final _subjectIdController =
      TextEditingController(text: widget.existing?.subjectId ?? '');
  late final _chapterIdController =
      TextEditingController(text: widget.existing?.chapterId ?? '');
  late final _tagsController =
      TextEditingController(text: (widget.existing?.tags ?? const []).join(', '));
  late bool _isStructured = widget.existing?.isStructuredQuestion ?? false;
  late bool _published = widget.existing?.published ?? true;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _fileUrlController.dispose();
    _yearController.dispose();
    _examNameController.dispose();
    _questionController.dispose();
    _answerController.dispose();
    _explanationController.dispose();
    _subjectController.dispose();
    _subjectIdController.dispose();
    _chapterIdController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      showAdminMessage(context, 'Title is required.');
      return;
    }
    if (_isStructured && _questionController.text.trim().isEmpty) {
      showAdminMessage(context, 'Question text is required for a structured entry.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final item = PyqItem(
        id: widget.existing?.id ?? '',
        title: _titleController.text.trim(),
        subtitle: _subtitleController.text.trim(),
        fileUrl: _fileUrlController.text.trim(),
        order: widget.existing?.order ?? DateTime.now().millisecondsSinceEpoch,
        year: int.tryParse(_yearController.text.trim()),
        examName: _examNameController.text.trim(),
        question: _isStructured ? _questionController.text.trim() : '',
        answer: _isStructured ? _answerController.text.trim() : '',
        explanation: _isStructured ? _explanationController.text.trim() : '',
        subject: _subjectController.text.trim(),
        subjectId: _subjectIdController.text.trim(),
        chapterId: _chapterIdController.text.trim(),
        tags: _tagsController.text
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList(),
        published: _published,
      );
      if (widget.existing == null) {
        await pyqRepository.add(item);
        await auditLogRepository.log(action: 'create', module: 'PYQs', targetLabel: item.title);
      } else {
        await pyqRepository.update(item);
        await auditLogRepository.log(action: 'update', module: 'PYQs', targetLabel: item.title);
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
      title: widget.existing == null ? 'Add PYQ' : 'Edit PYQ',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Title (e.g. MPSC Combine 2025)'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _subtitleController,
          decoration: const InputDecoration(
            labelText: 'Subtitle (e.g. Prelims Paper — 100 questions)',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _subjectController,
          decoration: const InputDecoration(labelText: 'Subject label (e.g. इतिहास)'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _subjectIdController,
          decoration: const InputDecoration(labelText: 'subjectId (optional)'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _chapterIdController,
          decoration: const InputDecoration(labelText: 'chapterId / topicId (optional)'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _tagsController,
          decoration: const InputDecoration(
            labelText: 'Tags (comma separated)',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Published'),
          subtitle: Text(_published ? 'Visible to students' : 'Draft'),
          value: _published,
          onChanged: (v) => setState(() => _published = v),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _yearController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Year (e.g. 2024)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _examNameController,
                decoration: const InputDecoration(labelText: 'Exam name'),
              ),
            ),
          ],
        ),
        const AdminSectionLabel(label: 'Entry type'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Structured question (Q & A)'),
          subtitle: const Text('Off = just a paper/solutions link'),
          value: _isStructured,
          onChanged: (v) => setState(() => _isStructured = v),
        ),
        if (_isStructured) ...[
          const AdminSectionLabel(label: 'Question'),
          TextField(
            controller: _questionController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Question text'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _answerController,
            decoration: const InputDecoration(labelText: 'Answer'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _explanationController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Explanation (optional)'),
          ),
        ] else
          TextField(
            controller: _fileUrlController,
            decoration: const InputDecoration(
              labelText: 'Paper / solutions link (optional)',
              hintText: 'https://...',
            ),
          ),
      ],
    );
  }
}
