import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_index_picker.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/rag_processing_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';
import 'package:mpsc_combine_ai/services/storage_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

class AdminRagSourceFormScreen extends StatefulWidget {
  const AdminRagSourceFormScreen({super.key, this.existing});

  final RagSource? existing;

  @override
  State<AdminRagSourceFormScreen> createState() =>
      _AdminRagSourceFormScreenState();
}

class _AdminRagSourceFormScreenState extends State<AdminRagSourceFormScreen> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _subject =
      TextEditingController(text: widget.existing?.subject ?? '');
  late final _subjectId =
      TextEditingController(text: widget.existing?.subjectId ?? '');
  late final _chapter =
      TextEditingController(text: widget.existing?.chapter ?? '');
  late final _chapterId =
      TextEditingController(text: widget.existing?.chapterId ?? '');
  late final _exam = TextEditingController(
    text: widget.existing?.exam.isNotEmpty == true
        ? widget.existing!.exam
        : kMpscDefaultExam,
  );
  late final _linkedId =
      TextEditingController(text: widget.existing?.linkedId ?? '');
  late final _text = TextEditingController();
  late RagSourceType _type = widget.existing?.sourceType ?? RagSourceType.pdf;
  late RagDomain _domain = widget.existing?.domain ?? RagDomain.notes;
  late ContentIndexSelection _index = ContentIndexSelection(
    examId: widget.existing?.examId.isNotEmpty == true
        ? widget.existing!.examId
        : kDefaultExamId,
    subjectId: widget.existing?.subjectId ?? '',
    chapterId: widget.existing?.chapterId ?? '',
    topicId: widget.existing?.topicId ?? '',
    subjectTitle: widget.existing?.subject ?? '',
    chapterTitle: widget.existing?.chapter ?? '',
  );
  late bool _published = widget.existing?.published ?? false;
  late String _fileUrl = widget.existing?.fileUrl ?? '';
  String _fileName = '';
  late bool _ownsFile = widget.existing?.ownsFile ?? false;
  bool _saving = false;
  bool _uploading = false;
  double _progress = 0;

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    _subjectId.dispose();
    _chapter.dispose();
    _chapterId.dispose();
    _exam.dispose();
    _linkedId.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
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
      _uploading = true;
      _progress = 0;
    });
    try {
      final url = await storageService.uploadBytes(
        folder: 'ragSources',
        fileName: file.name,
        bytes: bytes,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p.fraction);
        },
      );
      if (!mounted) return;
      setState(() {
        _fileUrl = url;
        _fileName = file.name;
        _ownsFile = true;
        if (_title.text.trim().isEmpty) {
          _title.text = file.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        }
      });
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showAdminMessage(context, 'Title is required.');
      return;
    }
    if (_type == RagSourceType.pdf && _fileUrl.trim().isEmpty) {
      showAdminMessage(context, 'Upload a PDF before saving.');
      return;
    }
    if (_type == RagSourceType.text && _text.text.trim().isEmpty) {
      showAdminMessage(context, 'Paste the source text before saving.');
      return;
    }
    if ((_type == RagSourceType.notes ||
            _type == RagSourceType.pyq ||
            _type == RagSourceType.currentAffairs ||
            _type == RagSourceType.chapter) &&
        _linkedId.text.trim().isEmpty &&
        _chapterId.text.trim().isEmpty) {
      showAdminMessage(
        context,
        'Enter the existing Firestore document id (or chapterId) to index.',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final uid = authService.currentUser?.uid ?? '';
      final now = DateTime.now();
      final subjectId =
          _index.subjectId.isNotEmpty ? _index.subjectId : _subjectId.text.trim();
      final chapterId =
          _index.chapterId.isNotEmpty ? _index.chapterId : _chapterId.text.trim();
      final draft = RagSource(
        id: widget.existing?.id ?? '',
        title: _title.text.trim(),
        subject: _index.subjectTitle.isNotEmpty
            ? _index.subjectTitle
            : _subject.text.trim(),
        subjectId: subjectId,
        chapter: _index.chapterTitle.isNotEmpty
            ? _index.chapterTitle
            : _chapter.text.trim(),
        chapterId: chapterId,
        exam: _exam.text.trim().isEmpty ? kMpscDefaultExam : _exam.text.trim(),
        fileUrl: _fileUrl.trim(),
        storagePath: '',
        uploadedBy: widget.existing?.uploadedBy.isNotEmpty == true
            ? widget.existing!.uploadedBy
            : uid,
        createdAt: widget.existing?.createdAt ?? now,
        updatedAt: now,
        status: RagSourceStatus.processing,
        published: _published,
        sourceType: _type,
        linkedCollection: _linkedCollection(_type),
        linkedId: _linkedId.text.trim(),
        ownsFile: _ownsFile,
        examId: _index.examId.isNotEmpty ? _index.examId : kDefaultExamId,
        topicId: _index.topicId,
        contentType: _contentTypeFor(_type, _domain),
        ragDomain: ragDomainToString(_domain),
      );

      final id = draft.id.isEmpty
          ? await ragSourceRepository.create(draft)
          : draft.id;
      if (draft.id.isNotEmpty) {
        await ragSourceRepository.update(draft);
      }

      await ragProcessingService.processSource(
        id,
        inlineText: _type == RagSourceType.text ? _text.text : null,
        force: widget.existing != null,
      );

      await auditLogRepository.log(
        action: widget.existing == null ? 'create' : 'update',
        module: 'RAG Management',
        targetLabel: _title.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAdminError(context, RagException.fromError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _contentTypeFor(RagSourceType type, RagDomain domain) {
    switch (domain) {
      case RagDomain.pyq:
        return kPyqContentType;
      case RagDomain.syllabus:
        return kSyllabusContentType;
      case RagDomain.currentAffairs:
        return kCurrentAffairsContentType;
      case RagDomain.aiTeacher:
        return kAiLessonContentType;
      case RagDomain.studentPerformance:
        return kStudentPerformanceContentType;
      case RagDomain.notes:
        return type == RagSourceType.pdf ? kNotesPdfContentType : 'notes';
    }
  }

  RagDomain _defaultDomain(RagSourceType type) {
    switch (type) {
      case RagSourceType.pyq:
        return RagDomain.pyq;
      case RagSourceType.currentAffairs:
        return RagDomain.currentAffairs;
      case RagSourceType.chapter:
        return RagDomain.syllabus;
      case RagSourceType.notes:
      case RagSourceType.pdf:
      case RagSourceType.text:
        return RagDomain.notes;
    }
  }

  String _linkedCollection(RagSourceType type) {
    switch (type) {
      case RagSourceType.notes:
        return 'notes';
      case RagSourceType.pyq:
        return 'pyqs';
      case RagSourceType.currentAffairs:
        return 'currentAffairs';
      case RagSourceType.chapter:
        return 'chapters';
      case RagSourceType.pdf:
      case RagSourceType.text:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminFormScaffold(
      title: widget.existing == null ? 'Add knowledge source' : 'Edit knowledge source',
      isSaving: _saving || _uploading,
      canSave: !_uploading,
      saveLabel: _saving ? 'Processing…' : 'Save & process',
      onSave: _save,
      children: [
        const Text(
          'Processing extracts text, chunks it, and generates embeddings on the '
          'secure backend. The source stays Failed until that finishes.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const AdminSectionLabel(label: 'Content index'),
        ContentIndexPicker(
          initial: _index,
          onChanged: (v) {
            setState(() {
              _index = v;
              if (v.subjectTitle.isNotEmpty) _subject.text = v.subjectTitle;
              if (v.subjectId.isNotEmpty) _subjectId.text = v.subjectId;
              if (v.chapterTitle.isNotEmpty) _chapter.text = v.chapterTitle;
              if (v.chapterId.isNotEmpty) _chapterId.text = v.chapterId;
            });
          },
        ),
        const AdminSectionLabel(label: 'Source'),
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<RagSourceType>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: [
            for (final t in RagSourceType.values)
              DropdownMenuItem(value: t, child: Text(ragSourceTypeLabel(t))),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _type = v;
              _domain = _defaultDomain(v);
            });
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<RagDomain>(
          key: ValueKey(_domain),
          initialValue: _domain,
          decoration: const InputDecoration(labelText: 'RAG Domain'),
          items: [
            for (final d in RagDomain.values)
              DropdownMenuItem(value: d, child: Text(ragDomainLabel(d))),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _domain = v);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _exam,
          decoration: const InputDecoration(labelText: 'Exam'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _subject,
          decoration: const InputDecoration(labelText: 'Subject'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _subjectId,
          decoration: const InputDecoration(
            labelText: 'Subject id (optional, from Admin Subjects)',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _chapter,
          decoration: const InputDecoration(labelText: 'Chapter'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _chapterId,
          decoration: const InputDecoration(
            labelText: 'Chapter id (optional)',
          ),
        ),
        if (_type == RagSourceType.pdf) ...[
          const AdminSectionLabel(label: 'PDF'),
          if (_fileUrl.isNotEmpty)
            Text(
              _fileName.isEmpty ? 'PDF uploaded' : _fileName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          if (_uploading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: _pickPdf,
              icon: const Icon(Icons.upload_file_rounded),
              label: Text(_fileUrl.isEmpty ? 'Upload PDF' : 'Replace PDF'),
            ),
        ],
        if (_type == RagSourceType.text) ...[
          const AdminSectionLabel(label: 'Text'),
          TextField(
            controller: _text,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              hintText: 'Paste MPSC notes or study text…',
            ),
          ),
        ],
        if (_type == RagSourceType.notes ||
            _type == RagSourceType.pyq ||
            _type == RagSourceType.currentAffairs ||
            _type == RagSourceType.chapter) ...[
          const AdminSectionLabel(label: 'Existing document'),
          Text(
            'Indexes the existing Firestore document. Original Notes / PYQ / CA '
            'records are not copied or deleted.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _linkedId,
            decoration: const InputDecoration(
              labelText: 'Linked document id',
            ),
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Published'),
          subtitle: const Text(
            'Students can retrieve this source only when it is published and Ready.',
          ),
          value: _published,
          onChanged: (v) => setState(() => _published = v),
        ),
      ],
    );
  }
}
