import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/live_class_item.dart';
import 'package:mpsc_combine_ai/services/live_class_repository.dart';

class AdminLiveClassFormScreen extends StatefulWidget {
  const AdminLiveClassFormScreen({super.key, this.existing});

  final LiveClassItem? existing;

  @override
  State<AdminLiveClassFormScreen> createState() => _AdminLiveClassFormScreenState();
}

class _AdminLiveClassFormScreenState extends State<AdminLiveClassFormScreen> {
  late final _titleController = TextEditingController(text: widget.existing?.title ?? '');
  late final _subjectController =
      TextEditingController(text: widget.existing?.subject ?? '');
  late final _urlController =
      TextEditingController(text: widget.existing?.meetingUrl ?? '');
  late final _scheduleController =
      TextEditingController(text: widget.existing?.scheduleText ?? '');
  late String _platform = widget.existing?.platform ?? liveClassPlatforms.first;
  late String _status = widget.existing?.status ?? 'upcoming';
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _subjectController.dispose();
    _urlController.dispose();
    _scheduleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      showAdminMessage(context, 'Title is required.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final item = LiveClassItem(
        id: widget.existing?.id ?? '',
        title: _titleController.text.trim(),
        subject: _subjectController.text.trim(),
        meetingUrl: _urlController.text.trim(),
        platform: _platform,
        scheduleText: _scheduleController.text.trim(),
        status: _status,
      );
      if (widget.existing == null) {
        await liveClassRepository.add(item);
      } else {
        await liveClassRepository.update(item);
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
      title: widget.existing == null ? 'Add Live Class' : 'Edit Live Class',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _subjectController,
          decoration: const InputDecoration(labelText: 'Subject (e.g. Polity)'),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _platform,
          decoration: const InputDecoration(labelText: 'Platform'),
          items: liveClassPlatforms
              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
              .toList(),
          onChanged: (value) => setState(() => _platform = value ?? _platform),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _urlController,
          decoration: const InputDecoration(
            labelText: 'Meeting / stream link',
            hintText: 'https://meet.google.com/...',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _scheduleController,
          decoration: const InputDecoration(
            labelText: 'Schedule text (free-form)',
            hintText: 'e.g. Today, 7:00 PM',
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Status'),
          items: liveClassStatuses
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: (value) => setState(() => _status = value ?? _status),
        ),
      ],
    );
  }
}
