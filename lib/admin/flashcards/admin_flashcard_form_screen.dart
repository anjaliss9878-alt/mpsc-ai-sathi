import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_index_picker.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_preview.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/flashcard_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/content_knowledge_indexer.dart';
import 'package:mpsc_combine_ai/services/flashcard_repository.dart';

class AdminFlashcardFormScreen extends StatefulWidget {
  const AdminFlashcardFormScreen({super.key, this.existing});

  final FlashcardItem? existing;

  @override
  State<AdminFlashcardFormScreen> createState() =>
      _AdminFlashcardFormScreenState();
}

class _AdminFlashcardFormScreenState extends State<AdminFlashcardFormScreen> {
  late final _titleController =
      TextEditingController(text: widget.existing?.title ?? '');
  late final _frontController =
      TextEditingController(text: widget.existing?.front ?? '');
  late final _backController =
      TextEditingController(text: widget.existing?.back ?? '');
  late final _explanationController =
      TextEditingController(text: widget.existing?.explanation ?? '');
  late final _tagsController = TextEditingController(
    text: (widget.existing?.tags ?? const []).join(', '),
  );
  late NoteWorkflowStatus _status =
      widget.existing?.status ?? NoteWorkflowStatus.draft;
  late String _difficulty = widget.existing?.difficulty ?? 'Medium';
  late String _language = widget.existing?.language ?? 'mr';
  late ContentIndexSelection _index = ContentIndexSelection(
    examId: widget.existing?.examId.isNotEmpty == true
        ? widget.existing!.examId
        : kDefaultExamId,
    targetGroup: targetGroupFromString(widget.existing?.targetGroup),
    subjectId: widget.existing?.subjectId ?? '',
    chapterId: widget.existing?.chapterId ?? '',
    topicId: widget.existing?.topicId ?? '',
  );
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _frontController.dispose();
    _backController.dispose();
    _explanationController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  FlashcardItem _buildItem({String? id}) {
    final front = _frontController.text.trim();
    return FlashcardItem(
      id: id ?? widget.existing?.id ?? '',
      title: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : front,
      front: front,
      back: _backController.text.trim(),
      explanation: _explanationController.text.trim(),
      difficulty: _difficulty,
      tags: _tagsController.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
      examId: _index.examId,
      targetGroup: targetGroupToString(_index.targetGroup),
      subjectId: _index.subjectId,
      chapterId: _index.chapterId,
      topicId: _index.topicId,
      language: _language,
      published: contentWorkflowPublishedFlag(_status),
      status: _status,
      order: widget.existing?.order ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _save() async {
    if (!_index.isComplete) {
      showAdminMessage(context, 'Select subject, chapter and topic.');
      return;
    }
    if (_frontController.text.trim().isEmpty ||
        _backController.text.trim().isEmpty) {
      showAdminMessage(context, 'Front and back are required.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      var item = _buildItem();
      if (widget.existing == null) {
        final id = await flashcardRepository.add(item);
        item = _buildItem(id: id);
        await auditLogRepository.log(
          action: 'create',
          module: 'Flashcards',
          targetLabel: item.title,
        );
      } else {
        await flashcardRepository.update(item);
        await auditLogRepository.log(
          action: 'update',
          module: 'Flashcards',
          targetLabel: item.title,
        );
      }
      try {
        await contentKnowledgeIndexer.syncFlashcard(item);
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
      title: widget.existing == null ? 'Add Flashcard' : 'Edit Flashcard',
      isSaving: _isSaving,
      onSave: _save,
      saveLabel: _status == NoteWorkflowStatus.published
          ? 'Save & Publish'
          : 'Save Draft',
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
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _language,
                decoration: const InputDecoration(labelText: 'Language'),
                items: const [
                  DropdownMenuItem(value: 'mr', child: Text('Marathi')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                ],
                onChanged: (v) => setState(() => _language = v ?? 'mr'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Title (optional — defaults to front)',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _frontController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Front / question'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _backController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Back / answer'),
        ),
        const SizedBox(height: 14),
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
          onPressed: () => showFlashcardPreview(context, _buildItem()),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Preview'),
        ),
      ],
    );
  }
}
