import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/data/subject_notes_data.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';

/// Fast Subject create/edit: Marathi name, English name, order, published.
///
/// Slug / subtitle / cover / icon stay in Firestore but are not edited here.
/// New subjects get an auto slug from the English name (ASCII-friendly).
class AdminSubjectFormScreen extends StatefulWidget {
  const AdminSubjectFormScreen({super.key, this.existing});

  final SubjectItem? existing;

  @override
  State<AdminSubjectFormScreen> createState() => _AdminSubjectFormScreenState();
}

class _AdminSubjectFormScreenState extends State<AdminSubjectFormScreen> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _nameEnController =
      TextEditingController(text: widget.existing?.nameEn ?? '');
  late final TextEditingController _orderController =
      TextEditingController(text: (widget.existing?.order ?? 0).toString());
  late bool _published = widget.existing?.published ?? true;
  late String _examId = widget.existing?.examId.isNotEmpty == true
      ? widget.existing!.examId
      : kDefaultExamId;
  List<ExamItem> _exams = const [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExams();
  }

  Future<void> _loadExams() async {
    final exams = await notesRepository.ensureDefaultExam().then((_) {
      return notesRepository.getExamsOnce();
    });
    if (!mounted) return;
    setState(() => _exams = exams);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _nameEnController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  /// Prefer English name for a stable ASCII slug; fall back to Marathi title.
  String _autoSlug({required String nameEn, required String titleMr}) {
    final fromEn = subjectSlugFromTitle(nameEn);
    if (nameEn.trim().isNotEmpty && fromEn.isNotEmpty && !fromEn.startsWith('subject-')) {
      return fromEn;
    }
    return subjectSlugFromTitle(titleMr);
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      showAdminMessage(context, 'Subject name (Marathi) is required.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final existing = widget.existing;
      final title = _titleController.text.trim();
      final nameEn = _nameEnController.text.trim();

      // Never rewrite an existing slug — keeps seed/import keys stable.
      final slug = (existing?.slug.trim().isNotEmpty == true)
          ? existing!.slug.trim()
          : _autoSlug(nameEn: nameEn, titleMr: title);

      final subject = SubjectItem(
        id: existing?.id ?? '',
        title: title,
        subtitle: existing?.subtitle ?? '',
        iconName: existing?.iconName ?? 'menu_book',
        order: int.tryParse(_orderController.text.trim()) ?? 0,
        imageUrl: existing?.imageUrl ?? '',
        slug: slug,
        nameEn: nameEn,
        examId: _examId,
        published: _published,
      );

      if (existing == null) {
        await notesRepository.addSubject(subject);
        await auditLogRepository.log(
          action: 'create',
          module: 'Subjects',
          targetLabel: subject.title,
        );
      } else {
        await notesRepository.updateSubject(subject);
        await auditLogRepository.log(
          action: 'update',
          module: 'Subjects',
          targetLabel: subject.title,
        );
      }
      if (mounted) {
        showAdminMessage(
          context,
          _published
              ? 'Subject saved — open it to add Chapters.'
              : 'Subject saved as Draft — hidden from students until Published.',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminFormScaffold(
      title: widget.existing == null ? 'Add Subject' : 'Edit Subject',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        DropdownButtonFormField<String>(
          value: _exams.any((e) => e.id == _examId) ? _examId : kDefaultExamId,
          decoration: const InputDecoration(labelText: 'Exam'),
          items: [
            for (final exam in _exams.isEmpty
                ? [ExamItem.mpscCombine()]
                : _exams)
              DropdownMenuItem(value: exam.id, child: Text(exam.title)),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _examId = v);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _titleController,
          textInputAction: TextInputAction.next,
          autofocus: widget.existing == null,
          decoration: const InputDecoration(
            labelText: 'Subject name (Marathi)',
            hintText: 'e.g. राज्यशास्त्र',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameEnController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'English name',
            hintText: 'e.g. Polity',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _orderController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_isSaving) _save();
          },
          decoration: const InputDecoration(
            labelText: 'Display order',
            hintText: 'Lower shows first',
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Published'),
          subtitle: Text(_published ? 'Visible to students' : 'Draft — hidden from students'),
          value: _published,
          onChanged: (v) => setState(() => _published = v),
        ),
      ],
    );
  }
}
