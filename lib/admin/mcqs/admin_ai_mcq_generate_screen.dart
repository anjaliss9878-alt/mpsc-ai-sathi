import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_index_picker.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/services/admin_ai_mcq_generator.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Optional AI draft generator. Uses existing Gemini / RAG — never publishes.
class AdminAiMcqGenerateScreen extends StatefulWidget {
  const AdminAiMcqGenerateScreen({super.key});

  @override
  State<AdminAiMcqGenerateScreen> createState() =>
      _AdminAiMcqGenerateScreenState();
}

class _AdminAiMcqGenerateScreenState extends State<AdminAiMcqGenerateScreen> {
  ContentIndexSelection _index = const ContentIndexSelection();
  final _setTitle = TextEditingController(text: 'AI Draft Set');
  String _difficulty = 'Medium';
  int _count = 5;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _setTitle.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (!_index.isComplete) {
      showAdminMessage(context, 'Select subject, chapter and topic.');
      return;
    }
    if (_setTitle.text.trim().isEmpty) {
      showAdminMessage(context, 'Set title is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final drafts = await AdminAiMcqGenerator().generate(
        setTitle: _setTitle.text.trim(),
        subjectTitle: _index.subjectTitle,
        chapterTitle: _index.chapterTitle,
        topicTitle: _index.topicTitle,
        difficulty: _difficulty,
        count: _count,
        examId: _index.examId.isEmpty ? kDefaultExamId : _index.examId,
        targetGroup: targetGroupToString(_index.targetGroup),
        subjectId: _index.subjectId,
        chapterId: _index.chapterId,
        topicId: _index.topicId,
      );
      if (drafts.isEmpty) {
        setState(() => _error = 'AI returned no questions. Try again or write them manually.');
        return;
      }
      for (final q in drafts) {
        await mcqRepository.add(q);
      }
      await auditLogRepository.log(
        action: 'ai-generate',
        module: 'MCQs',
        targetLabel: _setTitle.text.trim(),
        details: '${drafts.length} draft question(s) — not published',
      );
      if (!mounted) return;
      showAdminMessage(
        context,
        '${drafts.length} AI MCQs saved as DRAFT. Review before publishing.',
      );
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminFormScaffold(
      title: 'Generate MCQs with AI',
      isSaving: _busy,
      onSave: _generate,
      saveLabel: 'Generate as DRAFT',
      children: [
        const Text(
          'Uses the existing Gemini / RAG path. Questions are saved as Draft '
          'and stay hidden from students until you review and publish.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const AdminSectionLabel(label: 'Content index'),
        ContentIndexPicker(
          initial: _index,
          onChanged: (v) => _index = v,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _setTitle,
          decoration: const InputDecoration(labelText: 'MCQ set title'),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          value: _difficulty,
          decoration: const InputDecoration(labelText: 'Difficulty'),
          items: const [
            DropdownMenuItem(value: 'Easy', child: Text('Easy')),
            DropdownMenuItem(value: 'Medium', child: Text('Medium')),
            DropdownMenuItem(value: 'Hard', child: Text('Hard')),
          ],
          onChanged: (v) => setState(() => _difficulty = v ?? 'Medium'),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          value: _count,
          decoration: const InputDecoration(labelText: 'Number of questions'),
          items: [
            for (final n in [3, 5, 8, 10])
              DropdownMenuItem(value: n, child: Text('$n')),
          ],
          onChanged: (v) => setState(() => _count = v ?? 5),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }
}
