import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/current_affair_item.dart';
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
  late final _titleController = TextEditingController(text: widget.existing?.title ?? '');
  late final _categoryController =
      TextEditingController(text: widget.existing?.category ?? 'General');
  late final _descriptionController =
      TextEditingController(text: widget.existing?.description ?? '');
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
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

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      showAdminMessage(context, 'Title is required.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final item = CurrentAffairItem(
        id: widget.existing?.id ?? '',
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _categoryController.text.trim().isEmpty
            ? 'General'
            : _categoryController.text.trim(),
        date: _date,
      );
      if (widget.existing == null) {
        await currentAffairsRepository.add(item);
      } else {
        await currentAffairsRepository.update(item);
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
      title: widget.existing == null ? 'Add Current Affair' : 'Edit Current Affair',
      isSaving: _isSaving,
      onSave: _save,
      children: [
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
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(labelText: 'Description / summary'),
        ),
      ],
    );
  }
}
