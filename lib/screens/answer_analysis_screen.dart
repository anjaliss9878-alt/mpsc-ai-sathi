import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/test_result.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

enum _QuestionStatus { correct, wrong, skipped }

class AnswerAnalysisScreen extends StatelessWidget {
  const AnswerAnalysisScreen({super.key, required this.result});

  final TestResult result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Answer Analysis')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: result.questionResults.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return _AnalysisCard(
              index: index,
              questionResult: result.questionResults[index],
            );
          },
        ),
      ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({required this.index, required this.questionResult});

  final int index;
  final QuestionResult questionResult;

  @override
  Widget build(BuildContext context) {
    final status = !questionResult.isAttempted
        ? _QuestionStatus.skipped
        : questionResult.isCorrect
            ? _QuestionStatus.correct
            : _QuestionStatus.wrong;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Q${index + 1}. ${questionResult.question}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(questionResult.options.length, (optIndex) {
              return _OptionRow(
                text: questionResult.options[optIndex],
                isCorrectOpt: optIndex == questionResult.correctIndex,
                isSelectedOpt: optIndex == questionResult.selectedIndex,
              );
            }),
            if (questionResult.explanation != null &&
                questionResult.explanation!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: AppColors.orange,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        questionResult.explanation!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final _QuestionStatus status;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;
    late final IconData icon;
    switch (status) {
      case _QuestionStatus.correct:
        color = Colors.green;
        label = 'Correct';
        icon = Icons.check_circle_rounded;
      case _QuestionStatus.wrong:
        color = Colors.red;
        label = 'Wrong';
        icon = Icons.cancel_rounded;
      case _QuestionStatus.skipped:
        color = AppColors.textSecondary;
        label = 'Skipped';
        icon = Icons.remove_circle_outline_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.text,
    required this.isCorrectOpt,
    required this.isSelectedOpt,
  });

  final String text;
  final bool isCorrectOpt;
  final bool isSelectedOpt;

  @override
  Widget build(BuildContext context) {
    Color background = Colors.transparent;
    Color borderColor = AppColors.textSecondary.withValues(alpha: 0.15);
    IconData? icon;
    Color? iconColor;

    if (isCorrectOpt) {
      background = Colors.green.withValues(alpha: 0.08);
      borderColor = Colors.green.withValues(alpha: 0.4);
      icon = Icons.check_circle_rounded;
      iconColor = Colors.green;
    }
    if (isSelectedOpt && !isCorrectOpt) {
      background = Colors.red.withValues(alpha: 0.08);
      borderColor = Colors.red.withValues(alpha: 0.4);
      icon = Icons.cancel_rounded;
      iconColor = Colors.red;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (isSelectedOpt) ...[
            const SizedBox(width: 6),
            const Text(
              'Your answer',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (icon != null) ...[
            const SizedBox(width: 6),
            Icon(icon, size: 16, color: iconColor),
          ],
        ],
      ),
    );
  }
}
