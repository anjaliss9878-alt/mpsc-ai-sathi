import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/line_list_field.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/pdf_content_block.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/media_bytes_cache.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/note_rag_indexer.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pdf_structure_extract_service.dart';
import 'package:mpsc_combine_ai/services/storage_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/firebase_storage_url.dart';
import 'package:mpsc_combine_ai/utils/pdf_meta.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';
import 'package:mpsc_combine_ai/widgets/topic_pdf_viewer.dart';

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

/// PDF-first note editor. Hierarchy selectors reuse `exams` / `subjects` /
/// `chapters`. Students still read `notes` via the existing detail screen.
class AdminNoteFormScreen extends StatefulWidget {
  const AdminNoteFormScreen({
    super.key,
    this.subjectId = '',
    this.chapter,
    this.parentChapter,
    this.subjectTitle = '',
    this.examId = '',
    this.existingNote,
  });

  final String subjectId;
  final ChapterItem? chapter;
  final ChapterItem? parentChapter;
  final String subjectTitle;
  final String examId;
  final NoteItem? existingNote;

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
  bool _isIndexing = false;
  String _uploadStatus = 'Idle';
  String? _loadError;
  String? _noteId;
  DateTime? _updatedAt;
  NoteWorkflowStatus _status = NoteWorkflowStatus.draft;
  NoteRagStatus _ragStatus = NoteRagStatus.notIndexed;
  String _ragError = '';
  String _ragSourceId = '';

  String _examId = kDefaultExamId;
  String _subjectId = '';
  String _chapterId = '';
  String _topicId = '';
  String _subjectTitle = '';
  String _chapterTitle = '';

  List<ExamItem> _exams = const [];
  List<SubjectItem> _subjects = const [];
  List<ChapterItem> _rootChapters = const [];
  List<ChapterItem> _topics = const [];

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController =
      TextEditingController();
  late final TextEditingController _tagsController = TextEditingController();
  late final TextEditingController _sourceController = TextEditingController();
  late final TextEditingController _markdownController = TextEditingController();
  late final TextEditingController _pointsController = TextEditingController();
  late final TextEditingController _summaryController = TextEditingController();

  String _language = 'mr';
  String _difficulty = 'Medium';
  List<NoteAttachment> _attachments = [];
  List<PdfContentBlock> _pdfBlocks = [];
  String _pdfStoragePath = '';
  String _pdfFileName = '';
  int _pdfFileSize = 0;
  int _pdfPageCount = 0;
  Uint8List? _pdfBytes;
  String _videoUrl = '';
  String _videoFileName = '';
  NoteItem? _initial;

  static String kMpscDefaultExamFromExam() => ExamItem.mpscCombine().title;

  bool get _canSave =>
      _formReady &&
      !_isSaving &&
      !_isDeleting &&
      !_isUploadingAttachment &&
      !_isUploadingVideo &&
      _subjectId.isNotEmpty &&
      _chapterId.isNotEmpty;

  String get _leafId => _topicId.isNotEmpty ? _topicId : _chapterId;

  NoteAttachment? get _pdf {
    for (final a in _attachments) {
      if (a.type == 'pdf' && a.url.isNotEmpty) return a;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _examId = widget.examId.isNotEmpty ? widget.examId : kDefaultExamId;
    _subjectId = widget.subjectId;
    _subjectTitle = widget.subjectTitle;
    final parent = widget.parentChapter;
    final node = widget.chapter;
    if (parent != null && node != null) {
      _chapterId = parent.id;
      _chapterTitle = parent.title;
      _topicId = node.id;
    } else if (node != null) {
      if (node.parentChapterId.isNotEmpty) {
        _chapterId = node.parentChapterId;
        _topicId = node.id;
      } else {
        _chapterId = node.id;
        _chapterTitle = node.title;
        _topicId = node.id;
      }
    }
    _titleController = TextEditingController(
      text: widget.existingNote?.title.isNotEmpty == true
          ? widget.existingNote!.title
          : (node?.title ?? ''),
    );
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    _sourceController.dispose();
    _markdownController.dispose();
    _pointsController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await notesRepository.ensureDefaultExam();
      final exams = await notesRepository.getExamsOnce();
      final subjects = await notesRepository.getSubjectsOnce();
      NoteItem? note = widget.existingNote;
      if (note == null && widget.chapter != null) {
        note = await notesRepository.getNoteForChapter(widget.chapter!.id);
      }
      if (_subjectTitle.isEmpty && _subjectId.isNotEmpty) {
        final subject = await notesRepository.getSubject(_subjectId);
        _subjectTitle = subject?.title ?? _subjectId;
        if (_examId.isEmpty) _examId = subject?.examId ?? kDefaultExamId;
      }
      if (note != null) {
        _applyNote(note);
      }
      if (_subjectId.isNotEmpty) {
        _rootChapters = await notesRepository.getChaptersOnce(_subjectId);
        _rootChapters = _rootChapters
            .where((c) => c.parentChapterId.isEmpty)
            .toList();
      }
      if (_chapterId.isNotEmpty) {
        _topics = await notesRepository.getChildChaptersOnce(_chapterId);
        if (_chapterTitle.isEmpty) {
          for (final c in _rootChapters) {
            if (c.id == _chapterId) {
              _chapterTitle = c.title;
              break;
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _exams = exams;
        _subjects = subjects;
        _loadError = null;
        _loaded = true;
        _formReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = formatAdminError(e);
        _loaded = true;
        _formReady = true;
      });
      showAdminError(context, e);
    }
  }

  void _applyNote(NoteItem note) {
    _initial = note;
    _noteId = note.id;
    _status = note.status;
    _ragStatus = note.ragStatus;
    _ragError = note.ragError;
    _ragSourceId = note.ragSourceId;
    _updatedAt = note.updatedAt;
    if (note.examId.isNotEmpty) _examId = note.examId;
    if (note.subjectId.isNotEmpty) _subjectId = note.subjectId;
    if (note.chapterId.isNotEmpty) _chapterId = note.chapterId;
    if (note.topicId.isNotEmpty) _topicId = note.topicId;
    _titleController.text =
        note.title.trim().isNotEmpty ? note.title : _titleController.text;
    _descriptionController.text = note.description;
    _tagsController.text = note.tags.join(', ');
    _sourceController.text = note.source;
    _markdownController.text = note.contentMarkdown;
    _pointsController.text = note.importantPoints.join('\n');
    _summaryController.text = note.revisionSummary.join('\n');
    if (note.language.isNotEmpty) _language = note.language;
    if (note.difficulty.isNotEmpty) _difficulty = note.difficulty;
    _attachments = List.of(note.attachments);
    _pdfBlocks = List.of(note.pdfStructuredBlocks);
    _pdfStoragePath = note.pdfStoragePath;
    _pdfFileName = note.pdfFileName;
    _pdfFileSize = note.pdfFileSize;
    _pdfPageCount = note.pdfPageCount;
    _videoUrl = note.videoUrl;
    _videoFileName = _fileNameFromUrl(_videoUrl);
    if (note.pdfUrl.isNotEmpty &&
        !_attachments.any((a) => a.url == note.pdfUrl)) {
      _attachments = [
        ..._attachments,
        NoteAttachment(
          name: _pdfFileName.isNotEmpty ? _pdfFileName : 'notes.pdf',
          url: note.pdfUrl,
          type: 'pdf',
        ),
      ];
    }
    if (_pdf != null) _uploadStatus = 'Uploaded';
    _pdfBytes = null;
  }

  String _fileNameFromUrl(String url) {
    if (url.isEmpty) return '';
    final path = Uri.tryParse(url)?.pathSegments;
    if (path == null || path.isEmpty) return '';
    final raw = path.last;
    return raw.contains('_') ? raw.substring(raw.indexOf('_') + 1) : raw;
  }

  Future<void> _onExamChanged(String examId) async {
    setState(() {
      _examId = examId;
      _subjectId = '';
      _chapterId = '';
      _topicId = '';
      _rootChapters = const [];
      _topics = const [];
    });
  }

  Future<void> _onSubjectChanged(String subjectId) async {
    final subject = _subjects.where((s) => s.id == subjectId).firstOrNull;
    final chapters = await notesRepository.getChaptersOnce(subjectId);
    if (!mounted) return;
    setState(() {
      _subjectId = subjectId;
      _subjectTitle = subject?.title ?? '';
      _chapterId = '';
      _topicId = '';
      _rootChapters = chapters.where((c) => c.parentChapterId.isEmpty).toList();
      _topics = const [];
    });
  }

  Future<void> _onChapterChanged(String chapterId) async {
    String title = '';
    for (final c in _rootChapters) {
      if (c.id == chapterId) title = c.title;
    }
    final topics = await notesRepository.getChildChaptersOnce(chapterId);
    if (!mounted) return;
    setState(() {
      _chapterId = chapterId;
      _chapterTitle = title;
      _topics = topics;
      _topicId = topics.isEmpty ? chapterId : '';
    });
  }

  Future<void> _pickPdf({bool replace = false}) async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) showAdminMessage(context, 'Could not read the selected PDF.');
      return;
    }
    setState(() {
      _isUploadingAttachment = true;
      _uploadStatus = 'Uploading';
    });
    try {
      final uploaded = await storageService.uploadBytesDetailed(
        folder: 'notes',
        fileName: file.name,
        bytes: bytes,
        contentType: 'application/pdf',
      );
      if (!mounted) return;
      mediaBytesCache.write(uploaded.url, Uint8List.fromList(bytes));
      mediaBytesCache.write(uploaded.path, Uint8List.fromList(bytes));
      final previous = _attachments.where((a) => a.type == 'pdf').toList();
      setState(() {
        _attachments = [
          ..._attachments.where((a) => a.type != 'pdf'),
          NoteAttachment(name: file.name, url: uploaded.url, type: 'pdf'),
        ];
        _pdfStoragePath = uploaded.path;
        _pdfFileName = file.name;
        _pdfFileSize = uploaded.byteCount;
        _pdfPageCount = pdfPageCountFromBytes(Uint8List.fromList(bytes)) ?? 0;
        _pdfBytes = Uint8List.fromList(bytes);
        _uploadStatus = 'Uploaded';
        _ragStatus = NoteRagStatus.notIndexed;
      });
      for (final p in previous) {
        if (p.url.isNotEmpty && p.url != uploaded.url) {
          await storageService.deleteByUrl(p.url);
        }
      }
      try {
        final blocks = await pdfStructureExtractService.extractFromPdfBytes(
          bytes: Uint8List.fromList(bytes),
          fileName: file.name,
          topicHint: _titleController.text.trim(),
        );
        if (mounted) setState(() => _pdfBlocks = blocks);
      } catch (e) {
        debugPrint('[NoteForm] PDF extract warning: $e');
      }
      if (mounted) {
        showAdminMessage(
          context,
          replace ? 'Replaced PDF: ${file.name}' : 'Uploaded ${file.name}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadStatus = 'Failed');
        showAdminError(context, e);
      }
    } finally {
      if (mounted) setState(() => _isUploadingAttachment = false);
    }
  }

  Future<void> _addOtherAttachment({required List<String> allowed}) async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: allowed,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    setState(() => _isUploadingAttachment = true);
    try {
      final type = _attachmentTypeFor(file.name);
      final url = await storageService.uploadBytes(
        folder: 'notes',
        fileName: file.name,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() {
        _attachments = [
          ..._attachments,
          NoteAttachment(name: file.name, url: url, type: type),
        ];
      });
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _isUploadingAttachment = false);
    }
  }

  Future<void> _removeAttachment(NoteAttachment attachment) async {
    final confirmed = await confirmDelete(context, attachment.name);
    if (!confirmed) return;
    setState(() {
      _attachments = _attachments.where((a) => a.url != attachment.url).toList();
      if (attachment.type == 'pdf') {
        _pdfBlocks = [];
        _pdfStoragePath = '';
        _pdfFileName = '';
        _pdfFileSize = 0;
        _pdfPageCount = 0;
        _pdfBytes = null;
        _uploadStatus = 'Idle';
      }
    });
    await storageService.deleteByUrl(attachment.url);
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
    if (bytes == null || bytes.isEmpty) return;
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
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _isUploadingVideo = false);
    }
  }

  List<String> _tags() {
    return _tagsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<NoteItem?> _persist(NoteWorkflowStatus status) async {
    if (!_canSave) {
      showAdminMessage(context, 'Select Exam, Subject, Chapter (and Topic).');
      return null;
    }
    setState(() => _isSaving = true);
    try {
      final wasCreate = _noteId == null || _noteId!.isEmpty;
      final title = _titleController.text.trim().isEmpty
          ? (_topics.where((t) => t.id == _topicId).firstOrNull?.title ??
              _chapterTitle)
          : _titleController.text.trim();
      final groupingChapterId = _chapterId;
      final topicId = _leafId;
      final savedId = await notesRepository.saveNote(
        noteId: _noteId,
        examId: _examId,
        subjectId: _subjectId,
        chapterId: groupingChapterId,
        topicId: topicId,
        title: title,
        description: _descriptionController.text.trim(),
        language: _language,
        difficulty: _difficulty,
        source: _sourceController.text.trim(),
        importantPoints: LineListFieldState.linesFromController(_pointsController),
        revisionSummary: LineListFieldState.linesFromController(_summaryController),
        contentMarkdown: _markdownController.text.trim(),
        attachments: _attachments,
        pdfStructuredBlocks: _pdfBlocks,
        pdfStoragePath: _pdfStoragePath,
        pdfFileName: _pdfFileName,
        pdfFileSize: _pdfFileSize,
        pdfPageCount: _pdfPageCount,
        videoUrl: _videoUrl,
        keywords: _initial?.keywords,
        mcqs: _initial?.mcqs,
        status: status,
        ragStatus: _ragStatus,
        ragSourceId: _ragSourceId,
        ragError: _ragError,
        aiSummary: _initial?.aiSummary,
        tags: _tags(),
      );
      final pdfUrl = _pdf?.url ?? '';
      if (pdfUrl.isNotEmpty && topicId.isNotEmpty) {
        final leaf = await notesRepository.getChapter(topicId);
        if (leaf != null && leaf.pdfUrl != pdfUrl) {
          await notesRepository.updateChapter(leaf.copyWith(pdfUrl: pdfUrl));
        }
      }
      await auditLogRepository.log(
        action: wasCreate ? 'create' : 'update',
        module: 'Notes',
        targetLabel: title,
      );
      final saved = await notesRepository.getNote(savedId);
      if (!mounted) return saved;
      setState(() {
        _noteId = savedId;
        _status = status;
        _updatedAt = DateTime.now();
        _initial = saved;
      });
      return saved;
    } catch (e) {
      if (mounted) showAdminError(context, e);
      return null;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveDraft() async {
    final saved = await _persist(NoteWorkflowStatus.draft);
    if (saved != null && mounted) {
      showAdminMessage(context, 'Draft saved — hidden from students.');
    }
  }

  Future<void> _submitReview() async {
    final saved = await _persist(NoteWorkflowStatus.underReview);
    if (saved != null && mounted) {
      showAdminMessage(context, 'Submitted for review.');
    }
  }

  Future<void> _approve() async {
    final saved = await _persist(NoteWorkflowStatus.approved);
    if (saved != null && mounted) {
      showAdminMessage(context, 'Approved. Publish when ready for students.');
    }
  }

  Future<void> _publish() async {
    final saved = await _persist(NoteWorkflowStatus.published);
    if (saved == null) return;
    if (saved.pdfUrl.isNotEmpty) {
      await _runRag(saved, force: false);
    }
    if (mounted) {
      showAdminMessage(
        context,
        'Published — students see the original PDF. RAG indexed if a PDF is attached.',
      );
    }
  }

  Future<void> _unpublish() async {
    final saved = await _persist(NoteWorkflowStatus.unpublished);
    if (saved == null) return;
    try {
      await noteRagIndexer.syncPublished(saved);
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
    if (mounted) {
      showAdminMessage(context, 'Unpublished — hidden from students and student RAG.');
    }
  }

  Future<void> _runRag(NoteItem note, {required bool force}) async {
    setState(() => _isIndexing = true);
    try {
      final updated = force
          ? await noteRagIndexer.retry(
              note,
              subjectTitle: _subjectTitle,
              chapterTitle: _chapterTitle,
              examTitle: _examTitleFor(),
            )
          : await noteRagIndexer.indexNote(
              note,
              subjectTitle: _subjectTitle,
              chapterTitle: _chapterTitle,
              examTitle: _examTitleFor(),
            );
      if (!mounted) return;
      setState(() {
        _ragStatus = updated.ragStatus;
        _ragError = updated.ragError;
        _ragSourceId = updated.ragSourceId;
        _initial = updated;
        if (updated.language.isNotEmpty) _language = updated.language;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _ragStatus = NoteRagStatus.failed;
          _ragError = e.toString();
        });
        showAdminError(context, e);
      }
    } finally {
      if (mounted) setState(() => _isIndexing = false);
    }
  }

  String _examTitleFor() {
    for (final e in _exams) {
      if (e.id == _examId) return e.title;
    }
    return kMpscDefaultExamFromExam();
  }

  Future<void> _delete() async {
    final id = _noteId;
    if (id == null || id.isEmpty) {
      showAdminMessage(context, 'No saved note to delete yet.');
      return;
    }
    final confirmed = await confirmDelete(
      context,
      _titleController.text.trim().isEmpty ? 'this note' : _titleController.text.trim(),
    );
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
        targetLabel: _titleController.text.trim(),
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
      return const Scaffold(
        body: LoadingState(),
      );
    }
    final updatedLabel = _updatedAt == null
        ? 'Not saved yet'
        : 'Last updated: '
            '${_updatedAt!.day.toString().padLeft(2, '0')}/'
            '${_updatedAt!.month.toString().padLeft(2, '0')}/'
            '${_updatedAt!.year}';
    final pdf = _pdf;
    final examItems = _exams.isEmpty ? [ExamItem.mpscCombine()] : _exams;
    final subjectItems = _subjects
        .where((s) => s.examId == _examId || s.examId.isEmpty)
        .toList();
    final topicItems = _topics.isEmpty && _chapterId.isNotEmpty
        ? [
            ChapterItem(
              id: _chapterId,
              subjectId: _subjectId,
              title: '$_chapterTitle (use chapter as topic)',
              order: 0,
            ),
          ]
        : _topics;

    return AdminFormScaffold(
      title: 'Notes — PDF',
      isSaving: _isSaving || _isDeleting || _isIndexing,
      canSave: _canSave,
      saveLabel: 'Save Draft',
      onSave: _saveDraft,
      maxContentWidth: 860,
      children: [
        if (_loadError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Load warning: $_loadError',
              style: TextStyle(color: Colors.red.shade800, fontSize: 12),
            ),
          ),
        Text(
          'Status: ${noteWorkflowStatusLabel(_status)} · $updatedLabel',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const AdminSectionLabel(label: 'Content index'),
        DropdownButtonFormField<String>(
          value: examItems.any((e) => e.id == _examId) ? _examId : examItems.first.id,
          decoration: const InputDecoration(labelText: 'Exam'),
          items: [
            for (final e in examItems)
              DropdownMenuItem(value: e.id, child: Text(e.title)),
          ],
          onChanged: (v) {
            if (v != null) _onExamChanged(v);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: subjectItems.any((s) => s.id == _subjectId) ? _subjectId : null,
          decoration: const InputDecoration(labelText: 'Subject'),
          items: [
            for (final s in subjectItems)
              DropdownMenuItem(value: s.id, child: Text(s.title)),
          ],
          onChanged: (v) {
            if (v != null) _onSubjectChanged(v);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _rootChapters.any((c) => c.id == _chapterId) ? _chapterId : null,
          decoration: const InputDecoration(labelText: 'Chapter'),
          items: [
            for (final c in _rootChapters)
              DropdownMenuItem(value: c.id, child: Text(c.title)),
          ],
          onChanged: (v) {
            if (v != null) _onChapterChanged(v);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: topicItems.any((t) => t.id == _topicId) ? _topicId : null,
          decoration: const InputDecoration(labelText: 'Topic'),
          items: [
            for (final t in topicItems)
              DropdownMenuItem(value: t.id, child: Text(t.title)),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _topicId = v);
          },
        ),
        const AdminSectionLabel(label: 'Note details'),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'e.g. मूलभूत हक्क — सविस्तर नोट्स',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Description',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _language,
          decoration: const InputDecoration(labelText: 'Language'),
          items: const [
            DropdownMenuItem(value: 'mr', child: Text('Marathi')),
            DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(value: 'mr-en', child: Text('Bilingual (Marathi + English)')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _language = v);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _difficulty,
          decoration: const InputDecoration(labelText: 'Difficulty'),
          items: const [
            DropdownMenuItem(value: 'Easy', child: Text('Easy')),
            DropdownMenuItem(value: 'Medium', child: Text('Medium')),
            DropdownMenuItem(value: 'Hard', child: Text('Hard')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _difficulty = v);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tagsController,
          decoration: const InputDecoration(
            labelText: 'Tags',
            hintText: 'polity, constitution, article 14',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _sourceController,
          decoration: const InputDecoration(
            labelText: 'Source / Reference',
            hintText: 'e.g. M. Laxmikanth / NCERT / official PDF',
          ),
        ),
        const AdminSectionLabel(label: 'Original PDF'),
        Text(
          'Students receive this exact file. Marathi fonts, tables, diagrams and '
          'page layout are not rewritten.',
          style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
        ),
        const SizedBox(height: 10),
        if (pdf != null) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.orange),
              title: Text(
                _pdfFileName.isNotEmpty ? _pdfFileName : pdf.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (_pdfFileSize > 0) formatFileSize(_pdfFileSize),
                  if (_pdfPageCount > 0) '$_pdfPageCount pages',
                  'Upload: $_uploadStatus',
                  'PDF URL: ${isValidFirebaseDownloadUrl(pdf.url) ? 'valid' : 'invalid'}',
                  'RAG: ${noteRagStatusAdminLabel(_ragStatus)}',
                  if (_ragStatus == NoteRagStatus.failed && _ragError.isNotEmpty)
                    _ragError,
                ].join(' · '),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TopicPdfViewer(
            url: pdf.url,
            storagePath: _pdfStoragePath,
            initialBytes: _pdfBytes,
            showDetailedErrors: true,
            fileName: _pdfFileName.isNotEmpty ? _pdfFileName : pdf.name,
            title: 'PDF Preview',
            height: 280,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _isUploadingAttachment ? null : () => _pickPdf(replace: true),
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Replace PDF'),
              ),
              OutlinedButton.icon(
                onPressed: () => _removeAttachment(pdf),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Remove PDF'),
              ),
            ],
          ),
        ] else if (_isUploadingAttachment)
          const LinearProgressIndicator()
        else
          OutlinedButton.icon(
            onPressed: _pickPdf,
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: const Text('Upload PDF'),
          ),
        if (_ragError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_ragError, style: TextStyle(color: Colors.red.shade800, fontSize: 12)),
          ),
        const AdminSectionLabel(label: 'Workflow'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(onPressed: _canSave ? _submitReview : null, child: const Text('Submit for Review')),
            OutlinedButton(onPressed: _canSave ? _approve : null, child: const Text('Approve')),
            FilledButton(onPressed: _canSave ? _publish : null, child: const Text('Publish')),
            OutlinedButton(onPressed: _canSave ? _unpublish : null, child: const Text('Unpublish')),
            if (_ragStatus == NoteRagStatus.failed || _ragStatus == NoteRagStatus.notIndexed)
              OutlinedButton.icon(
                onPressed: (_initial == null || _isIndexing)
                    ? null
                    : () => _runRag(_initial!, force: true),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_ragStatus == NoteRagStatus.failed ? 'RAG Retry' : 'RAG Index'),
              ),
          ],
        ),
        const AdminSectionLabel(label: 'Other attachments (optional)'),
        ..._attachments.where((a) => a.type != 'pdf').map(
          (a) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(_iconForAttachment(a.type), color: AppColors.navy),
              title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.red),
                onPressed: () => _removeAttachment(a),
              ),
            ),
          ),
        ),
        Wrap(
          spacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () => _addOtherAttachment(
                allowed: const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
              ),
              icon: const Icon(Icons.image_rounded),
              label: const Text('Upload Image'),
            ),
            OutlinedButton.icon(
              onPressed: () => _addOtherAttachment(allowed: const ['doc', 'docx']),
              icon: const Icon(Icons.description_rounded),
              label: const Text('Upload DOCX'),
            ),
          ],
        ),
        const AdminSectionLabel(label: 'Video upload (MP4)'),
        if (_videoUrl.isNotEmpty && !_isUploadingVideo)
          ListTile(
            leading: const Icon(Icons.videocam_rounded),
            title: Text(_videoFileName.isEmpty ? 'Topic video.mp4' : _videoFileName),
            trailing: IconButton(
              onPressed: _pickAndUploadVideo,
              icon: const Icon(Icons.upload_file_rounded),
            ),
          )
        else if (_isUploadingVideo)
          const LinearProgressIndicator()
        else
          OutlinedButton.icon(
            onPressed: _pickAndUploadVideo,
            icon: const Icon(Icons.videocam_rounded),
            label: const Text('Upload MP4 Video'),
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
