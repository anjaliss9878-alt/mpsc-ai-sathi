import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/line_list_field.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/pdf_content_block.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pdf_structure_extract_service.dart';
import 'package:mpsc_combine_ai/services/storage_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

String _attachmentTypeFor(String fileName) {
  final ext = fileName.toLowerCase().split('.').last;
  if (ext == 'pdf') return 'pdf';
  if (ext == 'doc' || ext == 'docx') return 'docx';
  if (['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext)) return 'image';
  if (ext == 'mp4') return 'video';
  return 'other';
}

IconData _iconForAttachment(String type) {
  switch (type) {
    case 'pdf':
      return Icons.picture_as_pdf_rounded;
    case 'docx':
      return Icons.description_rounded;
    case 'image':
      return Icons.image_rounded;
    case 'video':
      return Icons.videocam_rounded;
    default:
      return Icons.insert_drive_file_rounded;
  }
}

/// Edits the single note document belonging to [chapter] — creates one if
/// none exists yet.
///
/// Supports the original "one bullet per line" lists (still rendered by the
/// student `NotesDetailScreen`) *and* an optional richer Markdown body +
/// PDF/DOCX/image attachments, with a live Preview toggle.
class AdminNoteFormScreen extends StatefulWidget {
  const AdminNoteFormScreen({super.key, required this.subjectId, required this.chapter});

  final String subjectId;
  final ChapterItem chapter;

  @override
  State<AdminNoteFormScreen> createState() => _AdminNoteFormScreenState();
}

class _AdminNoteFormScreenState extends State<AdminNoteFormScreen> {
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _loaded = false;
  bool _formReady = false;
  bool _isPreview = false;
  bool _isUploadingAttachment = false;
  bool _isUploadingVideo = false;
  bool _published = true;
  String? _loadError;
  String? _noteId;
  DateTime? _updatedAt;
  late final TextEditingController _titleController = TextEditingController(
    text: widget.chapter.title,
  );
  late final TextEditingController _markdownController = TextEditingController();
  late final TextEditingController _pointsController = TextEditingController();
  late final TextEditingController _summaryController = TextEditingController();
  List<NoteAttachment> _attachments = [];
  List<PdfContentBlock> _pdfBlocks = [];
  String _videoUrl = '';
  String _videoFileName = '';
  NoteItem? _initial;

  bool get _canSave =>
      _formReady &&
      !_isSaving &&
      !_isDeleting &&
      !_isUploadingAttachment &&
      !_isUploadingVideo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _markdownController.dispose();
    _pointsController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final note = await notesRepository.getNoteForChapter(widget.chapter.id);
      if (!mounted) return;
      _applyNoteToControllers(note);
      setState(() {
        _initial = note;
        _noteId = note?.id;
        _attachments = List.of(note?.attachments ?? const []);
        _pdfBlocks = List.of(note?.pdfStructuredBlocks ?? const []);
        _published = note?.published ?? true;
        _updatedAt = note?.updatedAt;
        _videoUrl = note?.videoUrl.trim() ?? '';
        _videoFileName = _videoUrl.isNotEmpty ? _fileNameFromUrl(_videoUrl) : '';
        _loadError = null;
        _loaded = true;
        _formReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      // Controllers already exist — allow creating/saving a new note even if
      // the read failed (e.g. transient network).
      setState(() {
        _loadError = formatAdminError(e);
        _loaded = true;
        _formReady = true;
      });
      showAdminError(context, e);
    }
  }

  void _applyNoteToControllers(NoteItem? note) {
    _titleController.text =
        (note?.title.trim().isNotEmpty == true) ? note!.title : widget.chapter.title;
    _markdownController.text = note?.contentMarkdown ?? '';
    _pointsController.text = (note?.importantPoints ?? const []).join('\n');
    _summaryController.text = (note?.revisionSummary ?? const []).join('\n');
  }

  String _fileNameFromUrl(String url) {
    final path = Uri.tryParse(url)?.pathSegments;
    if (path == null || path.isEmpty) return 'Topic video.mp4';
    final raw = path.last;
    return raw.contains('_') ? raw.substring(raw.indexOf('_') + 1) : raw;
  }

  Future<void> _addAttachment({List<String>? allowedExtensions}) async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) showAdminMessage(context, 'Could not read the selected file.');
      return;
    }
    setState(() => _isUploadingAttachment = true);
    try {
      final url = await storageService.uploadBytes(
        folder: 'notes',
        fileName: file.name,
        bytes: bytes,
      );
      if (!mounted) return;
      final type = _attachmentTypeFor(file.name);
      setState(() {
        _attachments = [
          if (type == 'pdf') ..._attachments.where((a) => a.type != 'pdf'),
          if (type != 'pdf') ..._attachments,
          NoteAttachment(name: file.name, url: url, type: type),
        ];
      });

      if (type == 'pdf') {
        try {
          final blocks = await pdfStructureExtractService.extractFromPdfBytes(
            bytes: Uint8List.fromList(bytes),
            fileName: file.name,
            topicHint: widget.chapter.title,
          );
          if (mounted) setState(() => _pdfBlocks = blocks);
        } catch (e) {
          debugPrint('[NoteForm] PDF extract warning: $e');
        }
      }

      if (mounted) showAdminMessage(context, 'Uploaded ${file.name}');
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _isUploadingAttachment = false);
    }
  }

  Future<void> _pickAndUploadVideo() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['mp4'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) showAdminMessage(context, 'Could not read the selected video.');
      return;
    }

    setState(() => _isUploadingVideo = true);
    try {
      final url = await storageService.uploadBytes(
        folder: 'videos',
        fileName: file.name,
        bytes: bytes,
        contentType: 'video/mp4',
      );
      if (!mounted) return;
      final previous = _videoUrl;
      setState(() {
        _videoUrl = url;
        _videoFileName = file.name;
      });
      if (previous.isNotEmpty && previous != url) {
        await storageService.deleteByUrl(previous);
      }
      if (mounted) showAdminMessage(context, 'Uploaded ${file.name}');
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _isUploadingVideo = false);
    }
  }

  Future<void> _clearVideo() async {
    final label = _videoFileName.isEmpty ? 'this video' : _videoFileName;
    final confirmed = await confirmDelete(context, label);
    if (!confirmed) return;
    final url = _videoUrl;
    setState(() {
      _videoUrl = '';
      _videoFileName = '';
    });
    if (url.isNotEmpty) {
      await storageService.deleteByUrl(url);
    }
  }

  Future<void> _removeAttachment(NoteAttachment attachment) async {
    final confirmed = await confirmDelete(context, attachment.name);
    if (!confirmed) return;
    setState(() {
      _attachments = _attachments.where((a) => a.url != attachment.url).toList();
      if (attachment.type == 'pdf') _pdfBlocks = [];
    });
    await storageService.deleteByUrl(attachment.url);
  }

  Future<void> _save() async {
    if (!_formReady) {
      showAdminMessage(
        context,
        'Notes form is still loading. Wait a moment, then try Save again.',
      );
      return;
    }
    if (_isUploadingAttachment || _isUploadingVideo) {
      showAdminMessage(context, 'Wait for the upload to finish before saving.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final wasCreate = _noteId == null || _noteId!.isEmpty;
      final title = _titleController.text.trim().isEmpty
          ? widget.chapter.title
          : _titleController.text.trim();
      final primaryPdf =
          _attachments.where((a) => a.type == 'pdf' && a.url.isNotEmpty).firstOrNull;
      final nextPdfUrl = primaryPdf?.url ?? '';
      final savedId = await notesRepository.saveNote(
        noteId: _noteId,
        subjectId: widget.subjectId,
        chapterId: widget.chapter.id,
        title: title,
        importantPoints: LineListFieldState.linesFromController(_pointsController),
        revisionSummary: LineListFieldState.linesFromController(_summaryController),
        contentMarkdown: _markdownController.text.trim(),
        attachments: _attachments,
        pdfStructuredBlocks: _pdfBlocks,
        videoUrl: _videoUrl,
        keywords: _initial?.keywords,
        mcqs: _initial?.mcqs,
        published: _published,
        aiSummary: _initial?.aiSummary,
        tags: _initial?.tags,
      );
      if (nextPdfUrl != widget.chapter.pdfUrl) {
        await notesRepository.updateChapter(
          widget.chapter.copyWith(pdfUrl: nextPdfUrl),
        );
      }
      await auditLogRepository.log(
        action: wasCreate ? 'create' : 'update',
        module: 'Notes',
        targetLabel: title,
      );
      if (!mounted) return;
      setState(() {
        _noteId = savedId;
        _updatedAt = DateTime.now();
        _initial = NoteItem(
          id: savedId,
          subjectId: widget.subjectId,
          chapterId: widget.chapter.id,
          title: title,
          importantPoints: LineListFieldState.linesFromController(_pointsController),
          revisionSummary: LineListFieldState.linesFromController(_summaryController),
          contentMarkdown: _markdownController.text.trim(),
          attachments: _attachments,
          pdfStructuredBlocks: _pdfBlocks,
          videoUrl: _videoUrl,
          keywords: _initial?.keywords ?? const [],
          mcqs: _initial?.mcqs ?? const [],
          published: _published,
          aiSummary: _initial?.aiSummary ?? '',
          tags: _initial?.tags ?? const [],
          updatedAt: _updatedAt,
        );
      });
      showAdminMessage(
        context,
        _published
            ? (wasCreate
                ? 'Note created — visible to students now.'
                : 'Note saved — students see the update immediately.')
            : 'Note saved as Draft — hidden from students until Published.',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final id = _noteId;
    if (id == null || id.isEmpty) {
      showAdminMessage(context, 'No saved note to delete yet.');
      return;
    }
    final confirmed = await confirmDelete(context, 'Notes for ${widget.chapter.title}');
    if (!confirmed) return;
    setState(() => _isDeleting = true);
    try {
      await notesRepository.deleteNote(id);
      for (final a in _attachments) {
        await storageService.deleteByUrl(a.url);
      }
      if (_videoUrl.isNotEmpty) {
        await storageService.deleteByUrl(_videoUrl);
      }
      await auditLogRepository.log(
        action: 'delete',
        module: 'Notes',
        targetLabel: widget.chapter.title,
      );
      if (!mounted) return;
      showAdminMessage(context, 'Note deleted.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text('Notes — ${widget.chapter.title}')),
        body: const LoadingState(),
      );
    }
    final updatedLabel = _updatedAt == null
        ? 'Not saved yet'
        : 'Last updated: '
            '${_updatedAt!.day.toString().padLeft(2, '0')}/'
            '${_updatedAt!.month.toString().padLeft(2, '0')}/'
            '${_updatedAt!.year} '
            '${_updatedAt!.hour.toString().padLeft(2, '0')}:'
            '${_updatedAt!.minute.toString().padLeft(2, '0')}';

    return AdminFormScaffold(
      title: 'Notes — ${widget.chapter.title}',
      isSaving: _isSaving || _isDeleting,
      canSave: _canSave,
      onSave: _save,
      saveLabel: _isDeleting
          ? 'Deleting…'
          : !_formReady
              ? 'Loading…'
              : (_isUploadingAttachment || _isUploadingVideo)
                  ? 'Uploading…'
                  : 'Save',
      children: [
        if (_loadError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Load warning: $_loadError',
              style: TextStyle(color: Colors.red.shade800, fontSize: 12),
            ),
          ),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'e.g. मूलभूत हक्क — सविस्तर नोट्स',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          updatedLabel,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Published'),
          subtitle: Text(_published ? 'Visible to students' : 'Draft — hidden'),
          value: _published,
          onChanged: (v) => setState(() => _published = v),
        ),
        const Text(
          'One bullet point per line. Blank lines are ignored.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const AdminSectionLabel(label: 'Important Points'),
        LineListField(
          label: 'Important Points',
          initialLines: const [],
          controller: _pointsController,
          hintText: 'e.g. रेग्युलेटिंग ॲक्ट, 1773 हा ...',
          minLines: 5,
        ),
        const AdminSectionLabel(label: 'Revision Summary'),
        LineListField(
          label: 'Revision Summary',
          initialLines: const [],
          controller: _summaryController,
          hintText: 'e.g. 1773 — कंपनीच्या कारभारावर संसदीय नियंत्रणाची सुरुवात',
          minLines: 5,
        ),
        AdminSectionLabel(
          label: 'Text content (Markdown)',
          trailing: TextButton.icon(
            onPressed: () => setState(() => _isPreview = !_isPreview),
            icon: Icon(_isPreview ? Icons.edit_outlined : Icons.visibility_outlined, size: 18),
            label: Text(_isPreview ? 'Edit' : 'Preview'),
          ),
        ),
        if (_isPreview)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            child: _markdownController.text.trim().isEmpty
                ? const Text('Nothing to preview yet.', style: TextStyle(color: AppColors.textSecondary))
                : MarkdownBody(data: _markdownController.text, selectable: true),
          )
        else
          TextField(
            controller: _markdownController,
            minLines: 6,
            maxLines: 16,
            decoration: const InputDecoration(
              labelText: 'Text content',
              hintText: '## Heading\n- Bullet point\n**bold text**',
              alignLabelWithHint: true,
            ),
          ),
        const AdminSectionLabel(label: 'PDF upload (and other attachments)'),
        ..._attachments.map(
          (a) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(_iconForAttachment(a.type), color: AppColors.navy),
              title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(a.type.toUpperCase()),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.red),
                onPressed: () => _removeAttachment(a),
              ),
            ),
          ),
        ),
        if (_isUploadingAttachment)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _addAttachment(allowedExtensions: const ['pdf']),
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('Upload PDF'),
              ),
              OutlinedButton.icon(
                onPressed: () => _addAttachment(
                  allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
                ),
                icon: const Icon(Icons.image_rounded),
                label: const Text('Upload Image'),
              ),
              OutlinedButton.icon(
                onPressed: () => _addAttachment(
                  allowedExtensions: const ['doc', 'docx'],
                ),
                icon: const Icon(Icons.description_rounded),
                label: const Text('Upload DOCX'),
              ),
            ],
          ),
        const AdminSectionLabel(label: 'Video upload (MP4)'),
        Text(
          'Optional topic video stored in Firebase Storage. Saved as videoUrl on the note.',
          style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
        ),
        const SizedBox(height: 10),
        if (_videoUrl.isNotEmpty && !_isUploadingVideo)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.videocam_rounded, color: AppColors.navy),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _videoFileName.isEmpty ? 'Topic video.mp4' : _videoFileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _videoUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).hintColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Replace video',
                  onPressed: _pickAndUploadVideo,
                  icon: const Icon(Icons.upload_file_rounded, color: AppColors.navy),
                ),
                IconButton(
                  tooltip: 'Remove video',
                  onPressed: _clearVideo,
                  icon: const Icon(Icons.close_rounded, color: Colors.red),
                ),
              ],
            ),
          )
        else if (_isUploadingVideo)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                'Uploading MP4 to Firebase Storage…',
                style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
              ),
            ],
          )
        else
          OutlinedButton.icon(
            onPressed: _pickAndUploadVideo,
            icon: const Icon(Icons.videocam_rounded),
            label: const Text('Upload MP4 Video'),
          ),
        if (_noteId != null && _noteId!.isNotEmpty) ...[
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            onPressed: (_isSaving || _isDeleting) ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete note'),
          ),
        ],
      ],
    );
  }
}

extension _FirstOrNullNoteForm<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
