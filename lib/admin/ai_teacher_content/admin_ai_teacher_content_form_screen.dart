import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_index_picker.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_preview.dart';
import 'package:mpsc_combine_ai/admin/widgets/line_list_field.dart';
import 'package:mpsc_combine_ai/models/ai_teacher_content_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_content_repository.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/content_knowledge_indexer.dart';

/// Holds editable state for one [GeneratedSlide] inside the form.
class _SlideForm {
  _SlideForm({GeneratedSlide? from})
      : titleController = TextEditingController(text: from?.title ?? ''),
        highlightLabelController = TextEditingController(text: from?.highlightLabel ?? ''),
        bulletsKey = GlobalKey<LineListFieldState>(),
        initialBullets = from?.bullets ?? const [],
        highlightType = from?.highlightType ?? SlideHighlightType.none;

  final TextEditingController titleController;
  final TextEditingController highlightLabelController;
  final GlobalKey<LineListFieldState> bulletsKey;
  final List<String> initialBullets;
  SlideHighlightType highlightType;

  GeneratedSlide toSlide() => GeneratedSlide(
        title: titleController.text.trim(),
        bullets: bulletsKey.currentState?.lines ?? initialBullets,
        highlightType: highlightType,
        highlightLabel: highlightLabelController.text.trim(),
      );

  void dispose() {
    titleController.dispose();
    highlightLabelController.dispose();
  }
}

/// Holds editable state for one [GeneratedMcq] inside the form.
class _QuizForm {
  _QuizForm({GeneratedMcq? from})
      : questionController = TextEditingController(text: from?.question ?? ''),
        explanationController = TextEditingController(text: from?.explanation ?? ''),
        optionControllers = List.generate(
          4,
          (i) => TextEditingController(
            text: (from?.options.length ?? 0) > i ? from!.options[i] : '',
          ),
        ),
        correctIndex = from?.correctIndex ?? 0;

  final TextEditingController questionController;
  final TextEditingController explanationController;
  final List<TextEditingController> optionControllers;
  int correctIndex;

  GeneratedMcq toMcq() => GeneratedMcq(
        question: questionController.text.trim(),
        options: optionControllers.map((c) => c.text.trim()).toList(),
        correctIndex: correctIndex,
        explanation: explanationController.text.trim(),
      );

  void dispose() {
    questionController.dispose();
    explanationController.dispose();
    for (final c in optionControllers) {
      c.dispose();
    }
  }
}

/// Admin editor for one AI Teacher lesson (title, summary, keywords, AI
/// prompt, teaching script, slides, quiz, notes) — every field the AI
/// Teacher Classroom pipeline needs to narrate it exactly like a
/// Gemini-generated lesson.
class AdminAiTeacherContentFormScreen extends StatefulWidget {
  const AdminAiTeacherContentFormScreen({super.key, this.existing});

  final AiTeacherContentItem? existing;

  @override
  State<AdminAiTeacherContentFormScreen> createState() =>
      _AdminAiTeacherContentFormScreenState();
}

class _AdminAiTeacherContentFormScreenState
    extends State<AdminAiTeacherContentFormScreen> {
  late final _titleController = TextEditingController(text: widget.existing?.lessonTitle ?? '');
  late final _subjectController =
      TextEditingController(text: widget.existing?.subjectName ?? '');
  late final _summaryController = TextEditingController(text: widget.existing?.summary ?? '');
  late final _keywordsController =
      TextEditingController(text: (widget.existing?.keywords ?? const []).join(', '));
  late final _aiPromptController = TextEditingController(text: widget.existing?.aiPrompt ?? '');
  final _scriptKey = GlobalKey<LineListFieldState>();
  final _notesKey = GlobalKey<LineListFieldState>();
  late final List<_SlideForm> _slides = (widget.existing?.slides ?? const [])
      .map((s) => _SlideForm(from: s))
      .toList();
  late final List<_QuizForm> _quiz = (widget.existing?.quiz ?? const [])
      .map((q) => _QuizForm(from: q))
      .toList();
  late NoteWorkflowStatus _status =
      widget.existing?.status ?? NoteWorkflowStatus.draft;
  late ContentIndexSelection _index = ContentIndexSelection(
    examId: widget.existing?.examId.isNotEmpty == true
        ? widget.existing!.examId
        : kDefaultExamId,
    targetGroup: targetGroupFromString(widget.existing?.targetGroup),
    subjectId: widget.existing?.subjectId ?? '',
    chapterId: widget.existing?.chapterId ?? '',
    topicId: widget.existing?.topicId ?? '',
    subjectTitle: widget.existing?.subjectName ?? '',
  );
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _subjectController.dispose();
    _summaryController.dispose();
    _keywordsController.dispose();
    _aiPromptController.dispose();
    for (final s in _slides) {
      s.dispose();
    }
    for (final q in _quiz) {
      q.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      showAdminMessage(context, 'Lesson title is required.');
      return;
    }
    if (_keywordsController.text.trim().isEmpty) {
      showAdminMessage(
        context,
        'At least one keyword is required — this is how the AI Teacher '
        'matches a student question to this lesson.',
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final item = AiTeacherContentItem(
        id: widget.existing?.id ?? '',
        lessonTitle: _titleController.text.trim(),
        subjectName: _index.subjectTitle.isNotEmpty
            ? _index.subjectTitle
            : _subjectController.text.trim(),
        summary: _summaryController.text.trim(),
        keywords: _keywordsController.text
            .split(',')
            .map((k) => k.trim())
            .where((k) => k.isNotEmpty)
            .toList(),
        aiPrompt: _aiPromptController.text.trim(),
        teachingScript: _scriptKey.currentState?.lines ?? const [],
        slides: _slides.map((s) => s.toSlide()).toList(),
        quiz: _quiz.map((q) => q.toMcq()).toList(),
        notes: _notesKey.currentState?.lines ?? const [],
        order: widget.existing?.order ?? DateTime.now().millisecondsSinceEpoch,
        examId: _index.examId,
        targetGroup: targetGroupToString(_index.targetGroup),
        subjectId: _index.subjectId,
        chapterId: _index.chapterId,
        topicId: _index.topicId,
        published: contentWorkflowPublishedFlag(_status),
        status: _status,
        createdAt: widget.existing?.createdAt,
      );
      String id = item.id;
      if (widget.existing == null) {
        id = await aiTeacherContentRepository.add(item);
        await auditLogRepository.log(
          action: 'create',
          module: 'AI Teacher Content',
          targetLabel: item.lessonTitle,
        );
      } else {
        await aiTeacherContentRepository.update(item);
        await auditLogRepository.log(
          action: 'update',
          module: 'AI Teacher Content',
          targetLabel: item.lessonTitle,
        );
      }
      try {
        await contentKnowledgeIndexer.syncAiLesson(
          AiTeacherContentItem(
            id: id,
            lessonTitle: item.lessonTitle,
            subjectName: item.subjectName,
            summary: item.summary,
            keywords: item.keywords,
            aiPrompt: item.aiPrompt,
            teachingScript: item.teachingScript,
            slides: item.slides,
            quiz: item.quiz,
            notes: item.notes,
            order: item.order,
            examId: item.examId,
            targetGroup: item.targetGroup,
            subjectId: item.subjectId,
            chapterId: item.chapterId,
            topicId: item.topicId,
            published: item.published,
            status: item.status,
          ),
        );
      } catch (_) {}
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
      title: widget.existing == null ? 'Add AI Teacher Lesson' : 'Edit AI Teacher Lesson',
      isSaving: _isSaving,
      onSave: _save,
      saveLabel: _status == NoteWorkflowStatus.published
          ? 'Save & Publish'
          : 'Save Draft',
      children: [
        const AdminSectionLabel(label: 'Content index'),
        ContentIndexPicker(
          initial: _index,
          onChanged: (v) => _index = v,
        ),
        const SizedBox(height: 14),
        WorkflowStatusDropdown(
          value: _status,
          onChanged: (v) => setState(() => _status = v),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Lesson title'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _subjectController,
          decoration: const InputDecoration(labelText: 'Subject (e.g. Polity · Chapter 4)'),
        ),
        const AdminSectionLabel(label: 'Keywords (required)'),
        TextField(
          controller: _keywordsController,
          decoration: const InputDecoration(
            labelText: 'Comma separated keywords',
            hintText: 'e.g. संसद, parliament, lok sabha, rajya sabha',
          ),
        ),
        const Text(
          'A student question matching any of these keywords plays this '
          'lesson instantly instead of calling Gemini.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const AdminSectionLabel(label: 'AI Prompt (optional, for your own reference)'),
        TextField(
          controller: _aiPromptController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Prompt used to draft this lesson elsewhere',
          ),
        ),
        const AdminSectionLabel(label: 'Lesson Summary'),
        TextField(
          controller: _summaryController,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Summary shown after the lesson'),
        ),
        const AdminSectionLabel(label: 'Teaching Script (spoken, one line per segment)'),
        LineListField(
          key: _scriptKey,
          label: 'Teaching script',
          initialLines: widget.existing?.teachingScript ?? const [],
          hintText: 'Each line is spoken (and subtitled) one at a time.',
          minLines: 5,
        ),
        AdminSectionLabel(
          label: 'Slides (${_slides.length})',
          trailing: TextButton.icon(
            onPressed: () => setState(() => _slides.add(_SlideForm())),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add slide'),
          ),
        ),
        ...List.generate(_slides.length, (i) => _buildSlideCard(i)),
        AdminSectionLabel(
          label: 'Quiz (${_quiz.length})',
          trailing: TextButton.icon(
            onPressed: () => setState(() => _quiz.add(_QuizForm())),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add question'),
          ),
        ),
        ...List.generate(_quiz.length, (i) => _buildQuizCard(i)),
        const AdminSectionLabel(label: 'Notes (one point per line)'),
        LineListField(
          key: _notesKey,
          label: 'Notes',
          initialLines: widget.existing?.notes ?? const [],
          hintText: 'Key points shown in "View Notes".',
          minLines: 4,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => showAiLessonPreview(
            context,
            AiTeacherContentItem(
              id: widget.existing?.id ?? '',
              lessonTitle: _titleController.text.trim(),
              subjectName: _subjectController.text.trim(),
              summary: _summaryController.text.trim(),
              keywords: _keywordsController.text
                  .split(',')
                  .map((k) => k.trim())
                  .where((k) => k.isNotEmpty)
                  .toList(),
              aiPrompt: _aiPromptController.text.trim(),
              teachingScript: _scriptKey.currentState?.lines ?? const [],
              slides: _slides.map((s) => s.toSlide()).toList(),
              quiz: _quiz.map((q) => q.toMcq()).toList(),
              notes: _notesKey.currentState?.lines ?? const [],
              order: widget.existing?.order ?? 0,
              examId: _index.examId,
              targetGroup: targetGroupToString(_index.targetGroup),
              subjectId: _index.subjectId,
              chapterId: _index.chapterId,
              topicId: _index.topicId,
              status: _status,
              published: contentWorkflowPublishedFlag(_status),
            ),
          ),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Preview'),
        ),
      ],
    );
  }

  Widget _buildSlideCard(int index) {
    final slide = _slides[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Slide ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  onPressed: () async {
                    final confirmed = await confirmDelete(context, 'Slide ${index + 1}');
                    if (!confirmed) return;
                    setState(() {
                      _slides[index].dispose();
                      _slides.removeAt(index);
                    });
                  },
                ),
              ],
            ),
            TextField(
              controller: slide.titleController,
              decoration: const InputDecoration(labelText: 'Slide title'),
            ),
            const SizedBox(height: 10),
            LineListField(
              key: slide.bulletsKey,
              label: 'Bullets',
              initialLines: slide.initialBullets,
              hintText: 'One bullet per line',
              minLines: 3,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<SlideHighlightType>(
                    initialValue: slide.highlightType,
                    decoration: const InputDecoration(labelText: 'Highlight'),
                    items: SlideHighlightType.values
                        .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                        .toList(),
                    onChanged: (v) => setState(() => slide.highlightType = v ?? SlideHighlightType.none),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: slide.highlightLabelController,
                    decoration: const InputDecoration(labelText: 'Highlight label'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizCard(int index) {
    final quiz = _quiz[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Question ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  onPressed: () async {
                    final confirmed = await confirmDelete(context, 'Question ${index + 1}');
                    if (!confirmed) return;
                    setState(() {
                      _quiz[index].dispose();
                      _quiz.removeAt(index);
                    });
                  },
                ),
              ],
            ),
            TextField(
              controller: quiz.questionController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Question text'),
            ),
            const SizedBox(height: 10),
            ...List.generate(4, (optIndex) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Radio<int>(
                      value: optIndex,
                      groupValue: quiz.correctIndex,
                      onChanged: (v) => setState(() => quiz.correctIndex = v ?? 0),
                    ),
                    Expanded(
                      child: TextField(
                        controller: quiz.optionControllers[optIndex],
                        decoration: InputDecoration(labelText: 'Option ${optIndex + 1}'),
                      ),
                    ),
                  ],
                ),
              );
            }),
            TextField(
              controller: quiz.explanationController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Explanation (optional)'),
            ),
          ],
        ),
      ),
    );
  }
}