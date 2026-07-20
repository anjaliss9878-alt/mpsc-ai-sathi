import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';

const List<String> _difficulties = ['Easy', 'Medium', 'Hard'];

class AdminMcqFormScreen extends StatefulWidget {
  const AdminMcqFormScreen({super.key, this.existing});

  final McqItem? existing;

  @override
  State<AdminMcqFormScreen> createState() => _AdminMcqFormScreenState();
}

class _AdminMcqFormScreenState extends State<AdminMcqFormScreen> {
  late final _setTitleController =
      TextEditingController(text: widget.existing?.setTitle ?? '');
  late final _subjectController =
      TextEditingController(text: widget.existing?.subject ?? '');
  late final _questionController =
      TextEditingController(text: widget.existing?.question ?? '');
  late final _explanationController =
      TextEditingController(text: widget.existing?.explanation ?? '');
  late final List<TextEditingController> _optionControllers = List.generate(
    4,
    (i) => TextEditingController(
      text: (widget.existing?.options.length ?? 0) > i
          ? widget.existing!.options[i]
          : '',
    ),
  );
  late String _difficulty = widget.existing?.difficulty ?? 'Medium';
  late int _correctIndex = widget.existing?.correctIndex ?? 0;
  bool _isSaving = false;

  @override
  void dispose() {
    _setTitleController.dispose();
    _subjectController.dispose();
    _questionController.dispose();
    _explanationController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final options = _optionControllers.map((c) => c.text.trim()).toList();
    if (_questionController.text.trim().isEmpty ||
        _setTitleController.text.trim().isEmpty ||
        options.any((o) => o.isEmpty)) {
      showAdminMessage(context, 'Set title, question and all 4 options are required.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final item = McqItem(
        id: widget.existing?.id ?? '',
        setTitle: _setTitleController.text.trim(),
        subject: _subjectController.text.trim(),
        difficulty: _difficulty,
        question: _questionController.text.trim(),
        options: options,
        correctIndex: _correctIndex,
        explanation: _explanationController.text.trim(),
        order: widget.existing?.order ?? DateTime.now().millisecondsSinceEpoch,
      );
      if (widget.existing == null) {
        await mcqRepository.add(item);
      } else {
        await mcqRepository.update(item);
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
      title: widget.existing == null ? 'Add MCQ' : 'Edit MCQ',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        TextField(
          controller: _setTitleController,
          decoration: const InputDecoration(
            labelText: 'Set title (groups questions together)',
            hintText: 'e.g. Polity MCQs — Set 1',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _subjectController,
          decoration: const InputDecoration(labelText: 'Subject (e.g. Polity)'),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _difficulty,
          decoration: const InputDecoration(labelText: 'Difficulty'),
          items: _difficulties
              .map((d) => DropdownMenuItem(value: d, child: Text(d)))
              .toList(),
          onChanged: (value) => setState(() => _difficulty = value ?? 'Medium'),
        ),
        const AdminSectionLabel(label: 'Question'),
        TextField(
          controller: _questionController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Question text'),
        ),
        const AdminSectionLabel(label: 'Options (select the correct one)'),
        ...List.generate(4, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Radio<int>(
                  value: i,
                  groupValue: _correctIndex,
                  onChanged: (value) => setState(() => _correctIndex = value ?? 0),
                ),
                Expanded(
                  child: TextField(
                    controller: _optionControllers[i],
                    decoration: InputDecoration(labelText: 'Option ${i + 1}'),
                  ),
                ),
              ],
            ),
          );
        }),
        const AdminSectionLabel(label: 'Explanation (optional)'),
        TextField(
          controller: _explanationController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Explanation'),
        ),
      ],
    );
  }
}
