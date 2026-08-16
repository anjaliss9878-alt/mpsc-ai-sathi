import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/services/storage_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Reusable "pick a file → upload to Firebase Storage → show progress →
/// keep the resulting download URL" control used across every Admin Panel
/// form that needs a real file upload (subject images, video files, note
/// attachments, teaching slides, ...).
///
/// Fully self-contained: manages its own picking/uploading/progress state
/// and only reports back the final download URL via [onUploaded]. The
/// containing form simply keeps that URL in its own state, exactly like it
/// already keeps any other text field's value.
class AdminFileUploadField extends StatefulWidget {
  const AdminFileUploadField({
    super.key,
    required this.label,
    required this.folder,
    this.currentUrl,
    this.currentFileName,
    required this.onUploaded,
    this.onCleared,
    this.allowedExtensions,
    this.previewAsImage = false,
  });

  final String label;

  /// Storage folder this file is uploaded into, e.g. `subjects`, `notes`,
  /// `videos`, `teachingSlides`.
  final String folder;

  final String? currentUrl;
  final String? currentFileName;

  /// Called with the new download URL (and original file name) once the
  /// upload finishes successfully.
  final void Function(String url, String fileName) onUploaded;

  /// Called when the admin removes the current file without replacing it.
  final VoidCallback? onCleared;

  /// Restrict the file picker to these extensions (without the dot), e.g.
  /// `['jpg', 'png', 'webp']` or `['pdf', 'doc', 'docx']`. `null` allows any
  /// file type.
  final List<String>? allowedExtensions;

  /// Shows a small image preview thumbnail instead of a generic file chip.
  final bool previewAsImage;

  @override
  State<AdminFileUploadField> createState() => _AdminFileUploadFieldState();
}

class _AdminFileUploadFieldState extends State<AdminFileUploadField> {
  bool _isUploading = false;
  double _progress = 0;
  String? _error;

  Future<void> _pickAndUpload() async {
    setState(() {
      _error = null;
    });
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: widget.allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: widget.allowedExtensions,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'Could not read the selected file.');
      return;
    }

    setState(() {
      _isUploading = true;
      _progress = 0;
    });
    try {
      final url = await storageService.uploadBytes(
        folder: widget.folder,
        fileName: file.name,
        bytes: bytes,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p.fraction);
        },
      );
      if (!mounted) return;
      widget.onUploaded(url, file.name);
    } catch (e) {
      if (mounted) setState(() => _error = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await confirmDelete(context, widget.currentFileName ?? 'this file');
    if (!confirmed) return;
    widget.onCleared?.call();
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = (widget.currentUrl ?? '').isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        if (hasFile && !_isUploading)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                if (widget.previewAsImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      widget.currentUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                  )
                else
                  const Icon(Icons.insert_drive_file_rounded, color: AppColors.navy),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.currentFileName ?? 'Uploaded file',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Replace',
                  icon: const Icon(Icons.upload_file_rounded, color: AppColors.navy),
                  onPressed: _pickAndUpload,
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close_rounded, color: Colors.red),
                  onPressed: _clear,
                ),
              ],
            ),
          )
        else if (_isUploading)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              const SizedBox(height: 6),
              Text(
                'Uploading… ${(_progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          )
        else
          OutlinedButton.icon(
            onPressed: _pickAndUpload,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Choose file & upload'),
          ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
      ],
    );
  }
}
