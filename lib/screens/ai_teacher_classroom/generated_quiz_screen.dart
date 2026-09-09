import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/test_result.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/test_result_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Runs the AI-generated MCQs for a lesson — architecture step: "Generate
/// MCQs". One question at a time, tap an option to reveal whether it was
/// correct (with the AI's explanation), then move to the next question; a
/// final score card is shown at the end.
class GeneratedQuizScreen extends StatefulWidget {
  const GeneratedQuizScreen({
    super.key,
    required this.topicName,
    required this.mcqs,
    this.subjectId = '',
    this.chapterId = '',
  });

  final String topicName;
  final List<GeneratedMcq> mcqs;
  final String subjectId;
  final String chapterId;

  @override
  State<GeneratedQuizScreen> createState() => _GeneratedQuizScreenState();
}

class _GeneratedQuizScreenState extends State<GeneratedQuizScreen> {
  int _index = 0;
  int _score = 0;
  int? _selected;
  bool _revealed = false;
  late List<int?> _answers;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _answers = List<int?>.filled(widget.mcqs.length, null);
  }

  void _select(int optionIndex) {
    if (_revealed) return;
    setState(() {
      _selected = optionIndex;
      _revealed = true;
      _answers[_index] = optionIndex;
      if (optionIndex == widget.mcqs[_index].correctIndex) _score++;
    });
  }

  void _next() {
    if (_index >= widget.mcqs.length - 1) {
      _persist();
      setState(() => _index = widget.mcqs.length);
      return;
    }
    setState(() {
      _index++;
      _selected = _answers[_index];
      _revealed = _answers[_index] != null;
    });
  }

  Future<void> _persist() async {
    if (_saved) return;
    _saved = true;
    await TestResultRepository.instance.savePracticeAttempt(
      title: widget.topicName,
      kind: 'mcq',
      subjectId: widget.subjectId,
      chapterId: widget.chapterId,
      questionResults: [
        for (var i = 0; i < widget.mcqs.length; i++)
          QuestionResult(
            question: widget.mcqs[i].question,
            options: widget.mcqs[i].options,
            correctIndex: widget.mcqs[i].correctIndex,
            selectedIndex: _answers[i],
            explanation: widget.mcqs[i].explanation,
          ),
      ],
    );
  }

  void _restart() {
    setState(() {
      _index = 0;
      _score = 0;
      _selected = null;
      _revealed = false;
      _answers = List<int?>.filled(widget.mcqs.length, null);
      _saved = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFinished = _index >= widget.mcqs.length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Quiz · ${widget.topicName}', style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: widget.mcqs.isEmpty
            ? const Center(child: Text('No quiz questions available for this lesson yet.'))
            : isFinished
                ? _buildResult(context)
                : _buildQuestion(context),
      ),
    );
  }

  Widget _buildQuestion(BuildContext context) {
    final mcq = widget.mcqs[_index];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Question ${_index + 1} of ${widget.mcqs.length}',
            style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            mcq.question,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 18),
          ...List.generate(mcq.options.length, (i) {
            final isCorrect = i == mcq.correctIndex;
            final isSelected = i == _selected;
            Color borderColor = AppColors.navy.withValues(alpha: 0.15);
            Color? fillColor;
            if (_revealed) {
              if (isCorrect) {
                borderColor = Colors.green;
                fillColor = Colors.green.withValues(alpha: 0.08);
              } else if (isSelected) {
                borderColor = Colors.red;
                fillColor = Colors.red.withValues(alpha: 0.08);
              }
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _select(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(mcq.options[i], style: const TextStyle(fontSize: 14.5)),
                      ),
                      if (_revealed && isCorrect)
                        const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                      if (_revealed && isSelected && !isCorrect)
                        const Icon(Icons.cancel_rounded, color: Colors.red, size: 20),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (_revealed)
            Container(
              margin: const EdgeInsets.only(top: 6, bottom: 18),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    (_selected == mcq.correctIndex)
                        ? Icons.check_circle_rounded
                        : Icons.info_rounded,
                    color: (_selected == mcq.correctIndex) ? Colors.green : AppColors.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      mcq.explanationFor(_selected ?? -1),
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          if (_revealed)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(backgroundColor: AppColors.orange, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(_index == widget.mcqs.length - 1 ? 'See Result' : 'Next Question'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final total = widget.mcqs.length;
    final percent = total == 0 ? 0 : ((_score / total) * 100).round();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded, color: AppColors.orange, size: 56),
            const SizedBox(height: 16),
            Text('You scored $_score / $total', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('$percent% correct', style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: _restart,
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text('Retry Quiz'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_score),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
                  child: const Text('Back to Lesson'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
