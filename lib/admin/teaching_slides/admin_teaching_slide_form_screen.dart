import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/models/teaching_slide_deck_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/storage_service.dart';
import 'package:mpsc_combine_ai/services/teaching_slide_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/teaching_slide_viewer.dart';

class AdminTeachingSlideFormScreen extends StatefulWidget {
  const AdminTeachingSlideFormScreen({super.key, this.existing});

  final TeachingSlideDeckItem? existing;

  @override
  State<AdminTeachingSlideFormScreen> createState() =>
      _AdminTeachingSlideFormScreenState();
}

class _AdminTeachingSlideFormScreenState extends State<AdminTeachingSlideFormScreen> {
  late final _titleController = TextEditingController(text: widget.existing?.title ?? '');
  late String _subjectId = widget.existing?.subjectId ?? '';
  late String _chapterId = widget.existing?.chapterId ?? '';
  late List<TeachingSlide> _slides = List.of(widget.existing?.slides ?? const []);
  bool _isSaving = false;
  bool _isUploading = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _addSlide(String type) async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: type == 'pdf' ? FileType.custom : FileType.image,
      allowedExtensions: type == 'pdf' ? const ['pdf'] : null,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    setState(() => _isUploading = true);
    try {
      final url = await storageService.uploadBytes(
        folder: 'teachingSlides',
        fileName: file.name,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() => _slides = [..._slides, TeachingSlide(url: url, type: type)]);
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _removeSlide(int index) async {
    final confirmed = await confirmDelete(context, 'Slide ${index + 1}');
    if (!confirmed) return;
    final slide = _slides[index];
    setState(() => _slides = List.of(_slides)..removeAt(index));
    await storageService.deleteByUrl(slide.url);
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      showAdminMessage(context, 'Title is required.');
      return;
    }
    if (_slides.isEmpty) {
      showAdminMessage(context, 'Add at least one slide.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final item = TeachingSlideDeckItem(
        id: widget.existing?.id ?? '',
        title: _titleController.text.trim(),
        subjectId: _subjectId,
        chapterId: _chapterId,
        slides: _slides,
        order: widget.existing?.order ?? DateTime.now().millisecondsSinceEpoch,
      );
      if (widget.existing == null) {
        await teachingSlideRepository.add(item);
        await auditLogRepository.log(action: 'create', module: 'Teaching Slides', targetLabel: item.title);
      } else {
        await teachingSlideRepository.update(item);
        await auditLogRepository.log(action: 'update', module: 'Teaching Slides', targetLabel: item.title);
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
      title: widget.existing == null ? 'Add Slide Deck' : 'Edit Slide Deck',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Deck title (e.g. Polity — Chapter 3 Slides)'),
        ),
        const AdminSectionLabel(label: 'Subject (optional)'),
        StreamBuilder<List<SubjectItem>>(
          stream: notesRepository.watchSubjects(),
          builder: (context, snapshot) {
            final subjects = snapshot.data ?? const <SubjectItem>[];
            final validValue = subjects.any((s) => s.id == _subjectId) ? _subjectId : null;
            return DropdownButtonFormField<String>(
              initialValue: validValue,
              decoration: const InputDecoration(labelText: 'Subject'),
              items: subjects
                  .map((s) => DropdownMenuItem(value: s.id, child: Text(s.title)))
                  .toList(),
              onChanged: (value) => setState(() {
                _subjectId = value ?? '';
                _chapterId = '';
              }),
            );
          },
        ),
        if (_subjectId.isNotEmpty) ...[
          const AdminSectionLabel(label: 'Chapter (optional)'),
          StreamBuilder<List<ChapterItem>>(
            stream: notesRepository.watchChapters(_subjectId),
            builder: (context, snapshot) {
              final chapters = snapshot.data ?? const <ChapterItem>[];
              final validValue = chapters.any((c) => c.id == _chapterId) ? _chapterId : null;
              return DropdownButtonFormField<String>(
                initialValue: validValue,
                decoration: const InputDecoration(labelText: 'Chapter'),
                items: chapters
                    .map((c) => DropdownMenuItem(value: c.id, child: Text(c.title)))
                    .toList(),
                onChanged: (value) => setState(() => _chapterId = value ?? ''),
              );
            },
          ),
        ],
        AdminSectionLabel(
          label: 'Slides (${_slides.length})',
          trailing: _slides.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () => showTeachingSlideViewer(
                    context,
                    title: _titleController.text.trim().isEmpty ? 'Preview' : _titleController.text,
                    slides: _slides,
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Preview'),
                ),
        ),
        if (_slides.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _slides.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                final reordered = List.of(_slides);
                if (newIndex > oldIndex) newIndex -= 1;
                final moved = reordered.removeAt(oldIndex);
                reordered.insert(newIndex, moved);
                _slides = reordered;
              });
            },
            itemBuilder: (context, index) {
              final slide = _slides[index];
              return Card(
                key: ValueKey('$index-${slide.url}'),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: slide.type == 'pdf'
                      ? const Icon(Icons.picture_as_pdf_rounded, color: AppColors.navy)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            slide.url,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(Icons.image_rounded),
                          ),
                        ),
                  title: Text('Slide ${index + 1} · ${slide.type}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.red),
                    onPressed: () => _removeSlide(index),
                  ),
                ),
              );
            },
          ),
        if (_isUploading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          )
        else
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => _addSlide('image'),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Add Image'),
              ),
              OutlinedButton.icon(
                onPressed: () => _addSlide('pdf'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Add PDF'),
              ),
            ],
          ),
      ],
    );
  }
}
