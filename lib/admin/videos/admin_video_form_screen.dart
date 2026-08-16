import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_file_upload_field.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/video_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/storage_service.dart';
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
  late final _durationController = TextEditingController(
    text: (widget.existing?.durationSeconds ?? 0) > 0
        ? (widget.existing!.durationSeconds ~/ 60).toString()
        : '',
  );
  late String _sourceType = widget.existing?.sourceType ?? 'youtube';
  late String _thumbnailUrl = widget.existing?.thumbnailUrl ?? '';
  late bool _isFree = widget.existing?.isFree ?? true;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _subjectController.dispose();
    _urlController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty || _urlController.text.trim().isEmpty) {
      showAdminMessage(context, 'Title and video link are required.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      var thumbnail = _thumbnailUrl;
      if (thumbnail.isEmpty && _sourceType == 'youtube') {
        thumbnail = youtubeThumbnailFor(_urlController.text.trim()) ?? '';
      }
      final minutes = int.tryParse(_durationController.text.trim()) ?? 0;
      final item = VideoItem(
        id: widget.existing?.id ?? '',
        title: _titleController.text.trim(),
        subject: _subjectController.text.trim(),
        videoUrl: _urlController.text.trim(),
        description: _descriptionController.text.trim(),
        sourceType: _sourceType,
        thumbnailUrl: thumbnail,
        durationSeconds: minutes * 60,
        isFree: _isFree,
      );
      if (widget.existing == null) {
        await videoRepository.add(item);
        await auditLogRepository.log(action: 'create', module: 'Videos', targetLabel: item.title);
      } else {
        await videoRepository.update(item);
        await auditLogRepository.log(action: 'update', module: 'Videos', targetLabel: item.title);
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
        const AdminSectionLabel(label: 'Source'),
        Wrap(
          spacing: 8,
          children: videoSourceTypes.map((type) {
            return ChoiceChip(
              label: Text(type[0].toUpperCase() + type.substring(1)),
              selected: _sourceType == type,
              onSelected: (_) => setState(() => _sourceType = type),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        if (_sourceType == 'upload')
          AdminFileUploadField(
            label: 'Video file',
            folder: 'videos',
            currentUrl: _urlController.text,
            currentFileName: _urlController.text.isEmpty ? null : 'Uploaded video',
            allowedExtensions: const ['mp4', 'mov', 'webm', 'mkv'],
            onUploaded: (url, name) => setState(() => _urlController.text = url),
            onCleared: () {
              final old = _urlController.text;
              setState(() => _urlController.text = '');
              storageService.deleteByUrl(old);
            },
          )
        else
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: _sourceType == 'vimeo' ? 'Vimeo link' : 'Video link (YouTube, Drive, etc.)',
              hintText: 'https://youtube.com/watch?v=...',
            ),
          ),
        const AdminSectionLabel(label: 'Thumbnail (optional)'),
        AdminFileUploadField(
          label: 'Thumbnail image',
          folder: 'videos/thumbnails',
          currentUrl: _thumbnailUrl,
          currentFileName: _thumbnailUrl.isEmpty ? null : 'Thumbnail',
          previewAsImage: true,
          allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
          onUploaded: (url, name) => setState(() => _thumbnailUrl = url),
          onCleared: () => setState(() => _thumbnailUrl = ''),
        ),
        const Text(
          'Leave blank for a YouTube link — a thumbnail is fetched automatically.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _durationController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Duration (minutes, optional)'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _descriptionController,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Free for all students'),
          subtitle: const Text('Turn off to mark this as a Paid video'),
          value: _isFree,
          onChanged: (v) => setState(() => _isFree = v),
        ),
      ],
    );
  }
}
