import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/ai_teacher_content_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/current_affair_item.dart';
import 'package:mpsc_combine_ai/models/flashcard_item.dart';
import 'package:mpsc_combine_ai/models/job_alert.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/models/smart_trick_item.dart';
import 'package:mpsc_combine_ai/models/test_item.dart';
import 'package:mpsc_combine_ai/utils/correct_answer.dart';
import 'package:mpsc_combine_ai/utils/date_format.dart';

Future<void> showNotePreview(BuildContext context, NoteItem note) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(note.title.isEmpty ? 'Note preview' : note.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: ${contentWorkflowStatusLabel(note.status)}'),
              Text('RAG: ${noteRagStatusLabel(note.ragStatus)}'),
              if (note.pdfFileName.isNotEmpty) Text('PDF: ${note.pdfFileName}'),
              if (note.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(note.description),
              ],
              if (note.importantPoints.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final p in note.importantPoints.take(8)) Text('• $p'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> showJobAlertPreview(BuildContext context, JobAlert item) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(item.title.isEmpty ? 'Job alert preview' : item.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.published ? 'Published' : 'Unpublished'),
              Text('${item.organization} · ${item.post}'),
              if (item.lastDate.isNotEmpty) Text('Last date: ${item.lastDate}'),
              const SizedBox(height: 8),
              Text(item.description),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> showPyqPreview(BuildContext context, PyqItem item) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(item.title.isEmpty ? 'PYQ preview' : item.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: ${contentWorkflowStatusLabel(item.status)}'),
              Text('Target: ${targetGroupLabel(targetGroupFromString(item.targetGroup))}'),
              if (item.year != null) Text('Year: ${item.year}'),
              const SizedBox(height: 8),
              if (item.question.isNotEmpty) Text(item.question),
              if (item.options.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (var i = 0; i < item.options.length; i++)
                  Text(
                    '${correctAnswerLetter(i)}. ${item.options[i]}'
                    '${i == item.correctIndex ? '  ✓' : ''}',
                  ),
              ],
              if (item.answer.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Answer: ${item.answer}'),
              ],
              if (item.explanation.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.explanation),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> showMcqPreview(BuildContext context, McqItem item) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(item.setTitle.isEmpty ? 'MCQ preview' : item.setTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: ${contentWorkflowStatusLabel(item.status)}'),
              Text(item.question),
              const SizedBox(height: 8),
              for (var i = 0; i < item.options.length; i++)
                Text(
                  '${correctAnswerLetter(i)}. ${item.options[i]}'
                  '${i == item.correctIndex ? '  ✓' : ''}',
                ),
              if (item.explanation.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.explanation),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> showTestPreview(BuildContext context, TestItem test) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(test.title.isEmpty ? 'Test preview' : test.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: ${contentWorkflowStatusLabel(test.status)}'),
              Text(
                '${test.questions.length} Q · ${test.durationSeconds ~/ 60} min · '
                '+${test.correctMarks}/-${test.negativeMarks}',
              ),
              if (test.instructions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(test.instructions),
              ],
              const SizedBox(height: 12),
              for (var i = 0; i < test.questions.length; i++) ...[
                Text(
                  'Q${i + 1}. ${test.questions[i].question}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                for (var o = 0; o < test.questions[i].options.length; o++)
                  Text(
                    '${correctAnswerLetter(o)}. ${test.questions[i].options[o]}'
                    '${o == test.questions[i].correctIndex ? '  ✓' : ''}',
                  ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> showFlashcardPreview(BuildContext context, FlashcardItem item) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(item.title.isEmpty ? 'Flashcard preview' : item.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: ${contentWorkflowStatusLabel(item.status)}'),
              Text('Target: ${targetGroupLabel(targetGroupFromString(item.targetGroup))}'),
              Text('Difficulty: ${item.difficulty}'),
              const SizedBox(height: 8),
              Text('Front: ${item.front}'),
              const SizedBox(height: 8),
              Text('Back: ${item.back}'),
              if (item.explanation.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.explanation),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> showSmartTrickPreview(BuildContext context, SmartTrickItem item) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(item.title.isEmpty ? 'Smart Trick preview' : item.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: ${contentWorkflowStatusLabel(item.status)}'),
              Text('Target: ${targetGroupLabel(targetGroupFromString(item.targetGroup))}'),
              const SizedBox(height: 8),
              Text('Concept: ${item.concept}'),
              const SizedBox(height: 8),
              Text('Trick: ${item.memoryTrick}'),
              if (item.explanation.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.explanation),
              ],
              if (item.example.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Example: ${item.example}'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> showCurrentAffairPreview(
  BuildContext context,
  CurrentAffairItem item,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(item.title.isEmpty ? 'Current Affairs preview' : item.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: ${contentWorkflowStatusLabel(item.status)}'),
              Text('${formatShortDate(item.date)} · ${item.category}'),
              Text('Target: ${targetGroupLabel(targetGroupFromString(item.targetGroup))}'),
              const SizedBox(height: 8),
              Text(item.description),
              if (item.detailedExplanation.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.detailedExplanation),
              ],
              if (item.source.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Source: ${item.source}'),
              ],
              if (item.hasQuiz) ...[
                const SizedBox(height: 8),
                Text('Quiz: ${item.quizQuestion}'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> showAiLessonPreview(
  BuildContext context,
  AiTeacherContentItem item,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(item.lessonTitle.isEmpty ? 'AI Lesson preview' : item.lessonTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: ${contentWorkflowStatusLabel(item.status)}'),
              Text('Target: ${targetGroupLabel(targetGroupFromString(item.targetGroup))}'),
              if (item.summary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.summary),
              ],
              const SizedBox(height: 8),
              Text('Keywords: ${item.keywords.join(', ')}'),
              if (item.teachingScript.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.teachingScript.take(6).join('\n')),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class WorkflowStatusDropdown extends StatelessWidget {
  const WorkflowStatusDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final NoteWorkflowStatus value;
  final ValueChanged<NoteWorkflowStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<NoteWorkflowStatus>(
      value: value,
      decoration: const InputDecoration(labelText: 'Status'),
      items: [
        for (final s in NoteWorkflowStatus.values)
          DropdownMenuItem(
            value: s,
            child: Text(contentWorkflowStatusLabel(s)),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
