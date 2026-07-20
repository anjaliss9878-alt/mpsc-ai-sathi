import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/video_item.dart';
import 'package:mpsc_combine_ai/services/video_repository.dart';

class AdminVideoFormScreen extends StatefulWidget {
  const AdminVideoFormScreen({super.key, this.existing});

  final VideoItem? existing;

  @override
  State<AdminVideoFormScreen> createState() => _AdminVideoFormScreenState();
}

class _AdminVideoFormScreenState extends State<AdminVideoFormScreen> {
  late final _titleController = TextEditingController(text: widget.existing?.title ?? '');
  late final _subjectController =
      TextEditingController(text: widget.existing?.subject ?? '');
  late final _urlController = TextEditingController(text: widget.existing?.videoUrl ?? '');
  late final _descriptionController =
      TextEditingController(text: widget.existing?.description ?? '');
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _subjectController.dispose();
    _urlController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty || _urlController.text.trim().isEmpty) {
      showAdminMessage(context, 'Title and video link are required.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final item = VideoItem(
        id: widget.existing?.id ?? '',
        title: _titleController.text.trim(),
        subject: _subjectController.text.trim(),
        videoUrl: _urlController.text.trim(),
        description: _descriptionController.text.trim(),
      );
      if (widget.existing == null) {
        await videoRepository.add(item);
      } else {
        await videoRepository.update(item);
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
      title: widget.existing == null ? 'Add Video' : 'Edit Video',
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
        TextField(
          controller: _urlController,
          decoration: const InputDecoration(
            labelText: 'Video link (YouTube, Drive, etc.)',
            hintText: 'https://youtube.com/watch?v=...',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _descriptionController,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
      ],
    );
  }
}
