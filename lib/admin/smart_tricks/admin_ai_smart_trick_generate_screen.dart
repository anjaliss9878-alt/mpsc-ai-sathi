import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_index_picker.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/services/admin_ai_study_generator.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/smart_trick_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Optional AI draft generator. Uses existing Gemini / RAG — never publishes.
class AdminAiSmartTrickGenerateScreen extends StatefulWidget {
  const AdminAiSmartTrickGenerateScreen({super.key});

  @override
  State<AdminAiSmartTrickGenerateScreen> createState() =>
      _AdminAiSmartTrickGenerateScreenState();
}

class _AdminAiSmartTrickGenerateScreenState
    extends State<AdminAiSmartTrickGenerateScreen> {
  ContentIndexSelection _index = const ContentIndexSelection();
  int _count = 3;
  bool _busy = false;
  String? _error;

  Future<void> _generate() async {
    if (!_index.isComplete) {
      showAdminMessage(context, 'Select subject, chapter and topic.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final drafts = await AdminAiStudyGenerator().generateSmartTricks(
        subjectTitle: _index.subjectTitle,
        chapterTitle: _index.chapterTitle,
        topicTitle: _index.topicTitle,
        count: _count,
        examId: _index.examId.isEmpty ? kDefaultExamId : _index.examId,
        targetGroup: targetGroupToString(_index.targetGroup),
        subjectId: _index.subjectId,
        chapterId: _index.chapterId,
        topicId: _index.topicId,
      );
      if (drafts.isEmpty) {
        setState(
          () => _error =
              'AI returned no smart tricks. Try again or write them manually.',
        );
        return;
      }
      for (final trick in drafts) {
        await smartTrickRepository.add(trick);
      }
      await auditLogRepository.log(
        action: 'ai-generate',
        module: 'Smart Tricks',
        targetLabel: _index.topicTitle,
        details: '${drafts.length} draft smart trick(s) — not published',
      );
      if (!mounted) return;
      showAdminMessage(
        context,
        '${drafts.length} AI smart tricks saved as DRAFT. Review before publishing.',
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
      title: 'Generate Smart Tricks with AI',
      isSaving: _busy,
      onSave: _generate,
      saveLabel: 'Generate as DRAFT',
      children: [
        const Text(
          'Uses the existing Gemini / RAG path and approved knowledge where '
          'available. Tricks are saved as Draft and stay hidden until you publish.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const AdminSectionLabel(label: 'Content index'),
        ContentIndexPicker(
          initial: _index,
          onChanged: (v) => _index = v,
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          value: _count,
          decoration: const InputDecoration(labelText: 'Number of smart tricks'),
          items: [
            for (final n in [1, 3, 5])
              DropdownMenuItem(value: n, child: Text('$n')),
          ],
          onChanged: (v) => setState(() => _count = v ?? 3),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }
}
