import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
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
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _fileUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      showAdminMessage(context, 'Title is required.');
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
      );
      if (widget.existing == null) {
        await pyqRepository.add(item);
      } else {
        await pyqRepository.update(item);
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
      title: widget.existing == null ? 'Add PYQ Paper' : 'Edit PYQ Paper',
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
