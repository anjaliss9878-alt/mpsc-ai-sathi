import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';

class AdminSubjectFormScreen extends StatefulWidget {
  const AdminSubjectFormScreen({super.key, this.existing});

  final SubjectItem? existing;

  @override
  State<AdminSubjectFormScreen> createState() => _AdminSubjectFormScreenState();
}

class _AdminSubjectFormScreenState extends State<AdminSubjectFormScreen> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _subtitleController =
      TextEditingController(text: widget.existing?.subtitle ?? '');
  late final TextEditingController _orderController =
      TextEditingController(text: (widget.existing?.order ?? 0).toString());
  late String _iconName = widget.existing?.iconName ?? 'menu_book';
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
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
      final subject = SubjectItem(
        id: widget.existing?.id ?? '',
        title: _titleController.text.trim(),
        subtitle: _subtitleController.text.trim(),
        iconName: _iconName,
        order: int.tryParse(_orderController.text.trim()) ?? 0,
      );
      if (widget.existing == null) {
        await notesRepository.addSubject(subject);
      } else {
        await notesRepository.updateSubject(subject);
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
      title: widget.existing == null ? 'Add Subject' : 'Edit Subject',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Title (e.g. भारतीय राज्यव्यवस्था)'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _subtitleController,
          decoration: const InputDecoration(labelText: 'Subtitle (e.g. 13 अध्याय — Polity)'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _orderController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Display order (lower shows first)'),
        ),
        const AdminSectionLabel(label: 'Icon'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: subjectIconChoices.entries.map((entry) {
            final selected = entry.key == _iconName;
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _iconName = entry.key),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: selected ? Colors.orange.withValues(alpha: 0.15) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? Colors.orange : Colors.grey.withValues(alpha: 0.3),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Icon(entry.value, color: selected ? Colors.orange : Colors.grey),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
