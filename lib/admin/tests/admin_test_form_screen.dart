import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/test_item.dart';
import 'package:mpsc_combine_ai/services/test_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Holds the editable text-field state for one embedded [TestQuestion].
class _QuestionForm {
  _QuestionForm({TestQuestion? from})
      : questionController = TextEditingController(text: from?.question ?? ''),
        explanationController =
            TextEditingController(text: from?.explanation ?? ''),
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

  TestQuestion toQuestion() {
    return TestQuestion(
      question: questionController.text.trim(),
      options: optionControllers.map((c) => c.text.trim()).toList(),
      correctIndex: correctIndex,
      explanation: explanationController.text.trim(),
    );
  }

  void dispose() {
    questionController.dispose();
    explanationController.dispose();
    for (final c in optionControllers) {
      c.dispose();
    }
  }
}

class AdminTestFormScreen extends StatefulWidget {
  const AdminTestFormScreen({super.key, this.existing});

  final TestItem? existing;

  @override
  State<AdminTestFormScreen> createState() => _AdminTestFormScreenState();
}

class _AdminTestFormScreenState extends State<AdminTestFormScreen> {
  late final _titleController = TextEditingController(text: widget.existing?.title ?? '');
  late final _subtitleController =
      TextEditingController(text: widget.existing?.subtitle ?? '');
  late final _durationController = TextEditingController(
    text: (((widget.existing?.durationSeconds ?? 600) / 60).round()).toString(),
  );
  late final _correctMarksController =
      TextEditingController(text: (widget.existing?.correctMarks ?? 2.0).toString());
  late final _negativeMarksController =
      TextEditingController(text: (widget.existing?.negativeMarks ?? 0.5).toString());
  late final List<_QuestionForm> _questions = widget.existing == null
      ? [_QuestionForm()]
      : widget.existing!.questions.map((q) => _QuestionForm(from: q)).toList();
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _durationController.dispose();
    _correctMarksController.dispose();
    _negativeMarksController.dispose();
    for (final q in _questions) {
      q.dispose();
    }
    super.dispose();
  }

  void _addQuestion() {
    setState(() => _questions.add(_QuestionForm()));
  }

  void _removeQuestion(int index) {
    setState(() {
      _questions[index].dispose();
      _questions.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      showAdminMessage(context, 'Title is required.');
      return;
    }
    final questions = _questions.map((q) => q.toQuestion()).toList();
    if (questions.isEmpty ||
        questions.any(
          (q) => q.question.isEmpty || q.options.any((o) => o.isEmpty),
        )) {
      showAdminMessage(context, 'Every question needs text and all 4 options filled.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final test = TestItem(
        id: widget.existing?.id ?? '',
        title: _titleController.text.trim(),
        subtitle: _subtitleController.text.trim(),
        durationSeconds: (int.tryParse(_durationController.text.trim()) ?? 10) * 60,
        correctMarks: double.tryParse(_correctMarksController.text.trim()) ?? 2.0,
        negativeMarks: double.tryParse(_negativeMarksController.text.trim()) ?? 0.5,
        questions: questions,
        order: widget.existing?.order ?? DateTime.now().millisecondsSinceEpoch,
      );
      if (widget.existing == null) {
        await testRepository.add(test);
      } else {
        await testRepository.update(test);
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
      title: widget.existing == null ? 'Add Test' : 'Edit Test',
      isSaving: _isSaving,
      onSave: _save,
      saveLabel: 'Save Test',
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Test title (e.g. Full Mock Test #1)'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _subtitleController,
          decoration: const InputDecoration(
            labelText: 'Subtitle (e.g. 100 Q • 120 min • All Subjects)',
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Duration (minutes)'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _correctMarksController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Marks / correct'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _negativeMarksController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Negative / wrong'),
              ),
            ),
          ],
        ),
        AdminSectionLabel(
          label: 'Questions (${_questions.length})',
          trailing: TextButton.icon(
            onPressed: _addQuestion,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Question'),
          ),
        ),
        ...List.generate(_questions.length, (index) {
          return _QuestionCard(
            index: index,
            form: _questions[index],
            onRemove: _questions.length > 1 ? () => _removeQuestion(index) : null,
          );
        }),
      ],
    );
  }
}

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({required this.index, required this.form, this.onRemove});

  final int index;
  final _QuestionForm form;
  final VoidCallback? onRemove;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Question ${widget.index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ),
                if (widget.onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
            TextField(
              controller: form.questionController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Question text'),
            ),
            const SizedBox(height: 10),
            ...List.generate(4, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Radio<int>(
                      value: i,
                      groupValue: form.correctIndex,
                      onChanged: (value) => setState(() => form.correctIndex = value ?? 0),
                    ),
                    Expanded(
                      child: TextField(
                        controller: form.optionControllers[i],
                        decoration: InputDecoration(labelText: 'Option ${i + 1}'),
                      ),
                    ),
                  ],
                ),
              );
            }),
            TextField(
              controller: form.explanationController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Explanation (optional)'),
            ),
          ],
        ),
      ),
    );
  }
}
