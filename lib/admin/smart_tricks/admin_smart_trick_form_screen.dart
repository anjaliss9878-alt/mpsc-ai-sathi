import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_index_picker.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_preview.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/smart_trick_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/content_knowledge_indexer.dart';
import 'package:mpsc_combine_ai/services/smart_trick_repository.dart';

class AdminSmartTrickFormScreen extends StatefulWidget {
  const AdminSmartTrickFormScreen({super.key, this.existing});

  final SmartTrickItem? existing;

  @override
  State<AdminSmartTrickFormScreen> createState() =>
      _AdminSmartTrickFormScreenState();
}

class _AdminSmartTrickFormScreenState extends State<AdminSmartTrickFormScreen> {
  late final _titleController =
      TextEditingController(text: widget.existing?.title ?? '');
  late final _conceptController =
      TextEditingController(text: widget.existing?.concept ?? '');
  late final _trickController =
      TextEditingController(text: widget.existing?.memoryTrick ?? '');
  late final _explanationController =
      TextEditingController(text: widget.existing?.explanation ?? '');
  late final _exampleController =
      TextEditingController(text: widget.existing?.example ?? '');
  late final _tagsController = TextEditingController(
    text: (widget.existing?.tags ?? const []).join(', '),
  );
  late NoteWorkflowStatus _status =
      widget.existing?.status ?? NoteWorkflowStatus.draft;
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
    _conceptController.dispose();
    _trickController.dispose();
    _explanationController.dispose();
    _exampleController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  SmartTrickItem _buildItem({String? id}) {
    final concept = _conceptController.text.trim();
    return SmartTrickItem(
      id: id ?? widget.existing?.id ?? '',
      title: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : concept,
      concept: concept,
      memoryTrick: _trickController.text.trim(),
      explanation: _explanationController.text.trim(),
      example: _exampleController.text.trim(),
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
    if (_conceptController.text.trim().isEmpty ||
        _trickController.text.trim().isEmpty) {
      showAdminMessage(context, 'Concept and memory trick are required.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      var item = _buildItem();
      if (widget.existing == null) {
        final id = await smartTrickRepository.add(item);
        item = _buildItem(id: id);
        await auditLogRepository.log(
          action: 'create',
          module: 'Smart Tricks',
          targetLabel: item.title,
        );
      } else {
        await smartTrickRepository.update(item);
        await auditLogRepository.log(
          action: 'update',
          module: 'Smart Tricks',
          targetLabel: item.title,
        );
      }
      try {
        await contentKnowledgeIndexer.syncSmartTrick(item);
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
      title: widget.existing == null ? 'Add Smart Trick' : 'Edit Smart Trick',
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
        DropdownButtonFormField<String>(
          value: _language,
          decoration: const InputDecoration(labelText: 'Language'),
          items: const [
            DropdownMenuItem(value: 'mr', child: Text('Marathi')),
            DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(value: 'hi', child: Text('Hindi')),
          ],
          onChanged: (v) => setState(() => _language = v ?? 'mr'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Title (optional — defaults to concept)',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _conceptController,
          decoration: const InputDecoration(labelText: 'Concept'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _trickController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Memory trick'),
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
          controller: _exampleController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Example'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _tagsController,
          decoration: const InputDecoration(labelText: 'Tags (comma separated)'),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => showSmartTrickPreview(context, _buildItem()),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Preview'),
        ),
      ],
    );
  }
}
