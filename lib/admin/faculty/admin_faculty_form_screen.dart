import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/faculty_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/faculty_repository.dart';

class AdminFacultyFormScreen extends StatefulWidget {
  const AdminFacultyFormScreen({super.key, this.existing});

  final FacultyItem? existing;

  @override
  State<AdminFacultyFormScreen> createState() => _AdminFacultyFormScreenState();
}

class _AdminFacultyFormScreenState extends State<AdminFacultyFormScreen> {
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late final _designationController =
      TextEditingController(text: widget.existing?.designation ?? '');
  late final _subjectController = TextEditingController(text: widget.existing?.subject ?? '');
  late final _photoUrlController = TextEditingController(text: widget.existing?.photoUrl ?? '');
  late final _bioController = TextEditingController(text: widget.existing?.bio ?? '');
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _designationController.dispose();
    _subjectController.dispose();
    _photoUrlController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      showAdminMessage(context, 'Name is required.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final item = FacultyItem(
        id: widget.existing?.id ?? '',
        name: _nameController.text.trim(),
        designation: _designationController.text.trim(),
        subject: _subjectController.text.trim(),
        photoUrl: _photoUrlController.text.trim(),
        bio: _bioController.text.trim(),
      );
      if (widget.existing == null) {
        await facultyRepository.add(item);
        await auditLogRepository.log(action: 'create', module: 'Faculty', targetLabel: item.name);
      } else {
        await facultyRepository.update(item);
        await auditLogRepository.log(action: 'update', module: 'Faculty', targetLabel: item.name);
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
      title: widget.existing == null ? 'Add Faculty' : 'Edit Faculty',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _designationController,
          decoration: const InputDecoration(
            labelText: 'Designation',
            hintText: 'e.g. MPSC Combine Expert Faculty',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _subjectController,
          decoration: const InputDecoration(labelText: 'Primary subject (e.g. Polity)'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _photoUrlController,
          decoration: const InputDecoration(
            labelText: 'Photo URL (optional)',
            hintText: 'https://...',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _bioController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Short bio (optional)'),
        ),
      ],
    );
  }
}
