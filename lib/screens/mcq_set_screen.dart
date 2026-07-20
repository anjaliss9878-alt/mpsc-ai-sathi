import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Lets a student work through every question in one MCQ set, selecting an
/// answer and instantly revealing whether it's correct plus the
/// explanation — a lighter-weight flow than the full timed CBT engine,
/// appropriate for topic-wise practice.
class McqSetScreen extends StatefulWidget {
  const McqSetScreen({
    super.key,
    required this.setTitle,
    required this.questions,
  });

  final String setTitle;
  final List<McqItem> questions;

  @override
  State<McqSetScreen> createState() => _McqSetScreenState();
}

class _McqSetScreenState extends State<McqSetScreen> {
  late final List<int?> _selected = List.filled(widget.questions.length, null);
  int _current = 0;

  int get _attempted => _selected.where((s) => s != null).length;
  int get _correct {
    var count = 0;
    for (var i = 0; i < widget.questions.length; i++) {
      if (_selected[i] != null && _selected[i] == widget.questions[i].correctIndex) {
        count++;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.questions[_current];
    final selected = _selected[_current];
    final hasAnswered = selected != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.setTitle, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_current + 1) / widget.questions.length,
              minHeight: 4,
              backgroundColor: AppColors.navy.withValues(alpha: 0.08),
              color: AppColors.orange,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Question ${_current + 1}/${widget.questions.length}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  Text(
                    'Attempted: $_attempted · Correct: $_correct',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    question.question,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 16),
                  ...List.generate(question.options.length, (i) {
                    final isCorrectOption = i == question.correctIndex;
                    final isSelectedOption = i == selected;
                    Color? tileColor;
                    if (hasAnswered) {
                      if (isCorrectOption) {
                        tileColor = Colors.green.withValues(alpha: 0.12);
                      } else if (isSelectedOption) {
                        tileColor = Colors.red.withValues(alpha: 0.1);
                      }
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: tileColor ?? Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: hasAnswered
                              ? null
                              : () => setState(() => _selected[_current] = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: hasAnswered && isCorrectOption
                                    ? Colors.green
                                    : AppColors.navy.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    question.options[i],
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (hasAnswered && isCorrectOption)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.green,
                                    size: 20,
                                  )
                                else if (hasAnswered && isSelectedOption)
                                  const Icon(
                                    Icons.cancel_rounded,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  if (hasAnswered && question.explanation.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.navy.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.lightbulb_outline_rounded,
                                size: 16,
                                color: AppColors.orange,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Explanation',
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.orange,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            question.explanation,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                  height: 1.4,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _current == 0
                          ? null
                          : () => setState(() => _current--),
                      child: const Text('Previous'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _current == widget.questions.length - 1
                          ? () => Navigator.of(context).pop()
                          : () => setState(() => _current++),
                      child: Text(
                        _current == widget.questions.length - 1
                            ? 'Finish'
                            : 'Next',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
