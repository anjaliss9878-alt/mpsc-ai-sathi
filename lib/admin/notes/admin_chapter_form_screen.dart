import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/data/subject_notes_data.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/pdf_content_block.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pdf_structure_extract_service.dart';
import 'package:mpsc_combine_ai/services/storage_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Fast Topic upload: Subject → Topic title → PDF Notes / Paste Notes → Save.
///
/// PDF notes are stored in Firebase Storage, mirrored on `chapter.pdfUrl` +
/// note attachments, and structure-extracted for AI Classroom slides.
/// Existing text-notes and Video workflows stay intact.
class AdminChapterFormScreen extends StatefulWidget {
  const AdminChapterFormScreen({super.key, required this.subjectId, this.existing});

  final String subjectId;
  final ChapterItem? existing;

  @override
  State<AdminChapterFormScreen> createState() => _AdminChapterFormScreenState();
}

class _AdminChapterFormScreenState extends State<AdminChapterFormScreen> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _orderController =
      TextEditingController(text: (widget.existing?.order ?? 0).toString());
  final _markdownController = TextEditingController();

  bool _isSaving = false;
  bool _loaded = false;
  bool _published = true;
  bool _isUploadingPdf = false;
  bool _isExtractingPdf = false;
  String? _noteId;
  String _noteTitle = '';
  String _pdfUrl = '';
  String _pdfFileName = '';
  List<NoteAttachment> _attachments = [];
  List<PdfContentBlock> _pdfBlocks = [];
  NoteItem? _initialNote;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _published = existing.published;
      _pdfUrl = existing.pdfUrl;
      if (_pdfUrl.isNotEmpty) {
        _pdfFileName = 'Topic PDF';
      }
    }
    _loadExistingNote();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _orderController.dispose();
    _markdownController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingNote() async {
    if (widget.existing == null) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final note = await notesRepository.getNoteForChapter(widget.existing!.id);
      if (!mounted) return;
      if (note != null) {
        _initialNote = note;
        _noteId = note.id;
        _noteTitle = note.title;
        _markdownController.text = note.contentMarkdown;
        _attachments = List.of(note.attachments);
        _pdfBlocks = List.of(note.pdfStructuredBlocks);
        final pdf = note.attachments.where((a) => a.type == 'pdf').firstOrNull;
        if (pdf != null) {
          _pdfUrl = pdf.url;
          _pdfFileName = pdf.name;
        } else if (_pdfUrl.isNotEmpty &&
            !_attachments.any((a) => a.url == _pdfUrl)) {
          _attachments = [
            ..._attachments,
            NoteAttachment(name: _pdfFileName, url: _pdfUrl, type: 'pdf'),
          ];
        }
      }
      setState(() => _loaded = true);
    } catch (e) {
      if (mounted) {
        setState(() => _loaded = true);
        showAdminError(context, e);
      }
    }
  }

  Future<void> _pickAndUploadPdf() async {
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
      _isUploadingPdf = true;
      _isExtractingPdf = false;
    });
    try {
      final url = await storageService.uploadBytes(
        folder: 'notes',
        fileName: file.name,
        bytes: bytes,
        contentType: 'application/pdf',
      );
      if (!mounted) return;

      final nextAttachments = [
        ..._attachments.where((a) => a.type != 'pdf'),
        NoteAttachment(name: file.name, url: url, type: 'pdf'),
      ];
      setState(() {
        _pdfUrl = url;
        _pdfFileName = file.name;
        _attachments = nextAttachments;
        _isUploadingPdf = false;
        _isExtractingPdf = true;
      });

      var blocks = const <PdfContentBlock>[];
      try {
        blocks = await pdfStructureExtractService.extractFromPdfBytes(
          bytes: Uint8List.fromList(bytes),
          fileName: file.name,
          topicHint: _titleController.text.trim(),
        );
      } catch (e) {
        debugPrint('[ChapterForm] PDF extract warning: $e');
        if (mounted) {
          showAdminMessage(
            context,
            'PDF uploaded. Structure extraction skipped: $e',
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _pdfBlocks = blocks;
        _isExtractingPdf = false;
      });
      showAdminMessage(
        context,
        blocks.isEmpty
            ? 'Uploaded ${file.name} (AI Classroom will use the PDF directly).'
            : 'Uploaded ${file.name} — extracted ${blocks.length} structured blocks.',
      );
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPdf = false;
          _isExtractingPdf = false;
        });
      }
    }
  }

  Future<void> _clearPdf() async {
    final label = _pdfFileName.isEmpty ? 'this PDF' : _pdfFileName;
    final confirmed = await confirmDelete(context, label);
    if (!confirmed) return;
    final url = _pdfUrl;
    setState(() {
      _pdfUrl = '';
      _pdfFileName = '';
      _pdfBlocks = [];
      _attachments = _attachments.where((a) => a.type != 'pdf').toList();
    });
    if (url.isNotEmpty) {
      await storageService.deleteByUrl(url);
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      showAdminMessage(context, 'Title is required.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final existing = widget.existing;
      final title = _titleController.text.trim();
      var slug = existing?.slug.trim() ?? '';
      if (slug.isEmpty) {
        final subject = await notesRepository.getSubject(widget.subjectId);
        final subjectSlug = (subject?.slug.isNotEmpty == true)
            ? subject!.slug
            : subjectSlugFromTitle(subject?.title ?? widget.subjectId);
        slug = topicSlug(subjectSlug, title, int.tryParse(_orderController.text.trim()) ?? 0);
      }

      // Preserve fields not shown in this simplified form.
      final chapter = ChapterItem(
        id: existing?.id ?? '',
        subjectId: widget.subjectId,
        title: title,
        order: int.tryParse(_orderController.text.trim()) ?? 0,
        estimatedStudyMinutes: existing?.estimatedStudyMinutes ?? 0,
        description: existing?.description ?? '',
        slug: slug,
        titleEn: existing?.titleEn ?? '',
        published: _published,
        tags: existing?.tags ?? const [],
        thumbnailUrl: existing?.thumbnailUrl ?? '',
        pdfUrl: _pdfUrl,
        aiSummary: existing?.aiSummary ?? '',
        revisionNotes: existing?.revisionNotes ?? '',
        classroomLessonId: existing?.classroomLessonId ?? '',
      );

      late final String chapterId;
      if (existing == null) {
        chapterId = await notesRepository.addChapter(chapter);
        await auditLogRepository.log(
          action: 'create',
          module: 'Topics',
          targetLabel: chapter.title,
        );
      } else {
        chapterId = existing.id;
        await notesRepository.updateChapter(
          ChapterItem(
            id: chapterId,
            subjectId: widget.subjectId,
            title: chapter.title,
            order: chapter.order,
            estimatedStudyMinutes: chapter.estimatedStudyMinutes,
            description: chapter.description,
            slug: chapter.slug,
            titleEn: chapter.titleEn,
            published: chapter.published,
            tags: chapter.tags,
            thumbnailUrl: chapter.thumbnailUrl,
            pdfUrl: chapter.pdfUrl,
            aiSummary: chapter.aiSummary,
            revisionNotes: chapter.revisionNotes,
            classroomLessonId: chapter.classroomLessonId,
          ),
        );
        await auditLogRepository.log(
          action: 'update',
          module: 'Topics',
          targetLabel: chapter.title,
        );
      }

      // Only write notes fields owned by this screen; omit the rest so
      // AdminNoteFormScreen / legacy data stay intact.
      final wasNoteCreate = _noteId == null || _noteId!.isEmpty;
      final savedNoteId = await notesRepository.saveNote(
        noteId: _noteId,
        subjectId: widget.subjectId,
        chapterId: chapterId,
        title: _noteTitle.trim().isNotEmpty ? _noteTitle.trim() : chapter.title,
        contentMarkdown: _markdownController.text,
        attachments: _attachments,
        pdfStructuredBlocks: _pdfBlocks,
        published: _published,
        // Preserve extras owned by the dedicated notes form.
        videoUrl: _initialNote?.videoUrl,
        keywords: _initialNote?.keywords,
        mcqs: _initialNote?.mcqs,
        aiSummary: _initialNote?.aiSummary,
        tags: _initialNote?.tags,
        importantPoints: _initialNote?.importantPoints,
        revisionSummary: _initialNote?.revisionSummary,
      );
      _noteId = savedNoteId;
      await auditLogRepository.log(
        action: wasNoteCreate ? 'create' : 'update',
        module: 'Notes',
        targetLabel: chapter.title,
      );

      if (mounted) {
        showAdminMessage(
          context,
          _published
              ? 'Topic saved — visible to students under this subject now.'
              : 'Topic saved as Draft — hidden from students until Published.',
        );
        Navigator.of(context).pop();
      }
    } catch (e, st) {
      debugPrint('[ChapterForm] save FAIL: $e\n$st');
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.existing == null ? 'Add Topic' : 'Edit Topic'),
        ),
        body: const LoadingState(),
      );
    }

    final editorHeight = (MediaQuery.sizeOf(context).height * 0.42).clamp(240.0, 560.0);
    final busyPdf = _isUploadingPdf || _isExtractingPdf;

    return AdminFormScaffold(
      title: widget.existing == null ? 'Add Topic' : 'Edit Topic',
      isSaving: _isSaving || busyPdf,
      onSave: _save,
      maxContentWidth: 960,
      children: [
        TextField(
          controller: _titleController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Topic title',
            hintText: 'e.g. प्रस्तावना / मूलभूत हक्क / संसद',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _orderController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Display order (lower shows first)'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Published (students can see)'),
          subtitle: Text(_published ? 'Published' : 'Draft — hidden from students'),
          value: _published,
          onChanged: (v) => setState(() => _published = v),
        ),
        const AdminSectionLabel(label: 'PDF Notes'),
        Text(
          'Upload the Topic PDF (Marathi OK). Stored in Firebase Storage. '
          'Students see the PDF on the Topic page; AI Classroom uses it as the primary source.',
          style: TextStyle(
            color: Theme.of(context).hintColor,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 10),
        if (_pdfUrl.isNotEmpty && !busyPdf)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf_rounded, color: AppColors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _pdfFileName.isEmpty ? 'Topic PDF' : _pdfFileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _pdfBlocks.isEmpty
                            ? 'PDF ready (structure will be read live in Classroom if needed)'
                            : '${_pdfBlocks.length} structured blocks extracted',
                        style: TextStyle(
                          color: Theme.of(context).hintColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Replace PDF',
                  onPressed: _pickAndUploadPdf,
                  icon: const Icon(Icons.upload_file_rounded, color: AppColors.navy),
                ),
                IconButton(
                  tooltip: 'Remove PDF',
                  onPressed: _clearPdf,
                  icon: const Icon(Icons.close_rounded, color: Colors.red),
                ),
              ],
            ),
          )
        else if (busyPdf)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                _isUploadingPdf
                    ? 'Uploading PDF to Firebase Storage…'
                    : 'Extracting headings, tables, diagrams…',
                style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
              ),
            ],
          )
        else
          OutlinedButton.icon(
            onPressed: _pickAndUploadPdf,
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: const Text('Upload Topic PDF'),
          ),
        const SizedBox(height: 18),
        const AdminSectionLabel(label: 'Notes (optional text)'),
        Text(
          'Optional paste of NotebookLM / study notes (Marathi markdown). '
          'When a PDF is present, Classroom prioritizes the PDF.',
          style: TextStyle(
            color: Theme.of(context).hintColor,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: editorHeight,
          child: TextField(
            controller: _markdownController,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            // Keep IME stable for long Devanagari paste/edit sessions.
            enableSuggestions: false,
            autocorrect: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            decoration: const InputDecoration(
              alignLabelWithHint: true,
              hintText: 'Paste optional topic notes…\n\n## शीर्षक\n- मुद्दा\n…',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(
              fontSize: 15,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
