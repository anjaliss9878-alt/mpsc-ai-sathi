import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';

class AdminChapterFormScreen extends StatefulWidget {
  const AdminChapterFormScreen({super.key, required this.subjectId, this.existing});

  final String subjectId;
  final ChapterItem? existing;

  @override
  State<AdminChapterFormScreen> createState() => _AdminChapterFormScreenState();
}

class _AdminChapterFormScreenState extends State<AdminChapterFormScreen> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _orderController =
      TextEditingController(text: (widget.existing?.order ?? 0).toString());
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      showAdminMessage(context, 'Title is required.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final chapter = ChapterItem(
        id: widget.existing?.id ?? '',
        subjectId: widget.subjectId,
        title: _titleController.text.trim(),
        order: int.tryParse(_orderController.text.trim()) ?? 0,
      );
      if (widget.existing == null) {
        await notesRepository.addChapter(chapter);
      } else {
        await notesRepository.updateChapter(chapter);
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
      title: widget.existing == null ? 'Add Chapter' : 'Edit Chapter',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Chapter title'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _orderController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Display order (lower shows first)'),
        ),
      ],
    );
  }
}
