import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/generated_notes_screen.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/generated_quiz_screen.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// The three action cards below the timeline: Summary / Quiz / Notes — all
/// backed by the current [lesson]'s AI-generated content (architecture
/// steps: "Generate MCQs" + "Generate Notes"). Opens a real quiz/notes
/// screen once a lesson has been generated.
class SummaryQuizNotesCards extends StatelessWidget {
  const SummaryQuizNotesCards({
    super.key,
    required this.lesson,
    required this.isWide,
  });

  final GeneratedLesson lesson;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _ActionCard(
        icon: Icons.fact_check_rounded,
        iconColor: AppColors.navy,
        title: 'Summary',
        description: lesson.summary.trim().isNotEmpty
            ? lesson.summary
            : 'No summary generated for this lesson yet.',
        buttonLabel: 'View Summary',
        onPressed: () => _showSummary(context),
      ),
      _ActionCard(
        icon: Icons.quiz_rounded,
        iconColor: AppColors.orange,
        title: 'Quick Quiz',
        description: '${lesson.mcqs.length} question${lesson.mcqs.length == 1 ? '' : 's'} based on this lesson.',
        buttonLabel: 'Start Quiz',
        onPressed: lesson.mcqs.isEmpty ? null : () => _openQuiz(context),
      ),
      _ActionCard(
        icon: Icons.sticky_note_2_rounded,
        iconColor: Colors.teal,
        title: 'Class Notes',
        description: '${lesson.notes.length} key point${lesson.notes.length == 1 ? '' : 's'} saved from this class.',
        buttonLabel: 'View Notes',
        onPressed: lesson.notes.isEmpty ? null : () => _openNotes(context),
      ),
    ];

    if (isWide) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            Expanded(child: cards[i]),
            if (i != cards.length - 1) const SizedBox(width: 14),
          ],
        ],
      );
    }

    return Column(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          cards[i],
          if (i != cards.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }

  void _showSummary(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(lesson.topicName),
        content: SingleChildScrollView(
          child: Text(
            lesson.summary.trim().isNotEmpty ? lesson.summary : 'No summary generated for this lesson yet.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  void _openQuiz(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GeneratedQuizScreen(topicName: lesson.topicName, mcqs: lesson.mcqs),
      ),
    );
  }

  void _openNotes(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GeneratedNotesScreen(
          topicName: lesson.topicName,
          summary: lesson.summary,
          notes: lesson.notes,
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: onPressed, child: Text(buttonLabel)),
            ),
          ],
        ),
      ),
    );
  }
}
