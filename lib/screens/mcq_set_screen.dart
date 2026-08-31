import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/chat_message.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/models/test_result.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_service.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Topic-wise MCQ practice: timer, explanation, bookmark, retry wrong,
/// and optional Gemini AI explanation.
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
  late List<McqItem> _questions;
  late List<int?> _selected;
  int _current = 0;
  final Set<String> _bookmarked = {};
  bool _timerEnabled = true;
  int _secondsLeft = 0;
  Timer? _timer;
  bool _aiLoading = false;
  String? _aiExplanation;
  bool _scorePersisted = false;

  int get _attempted => _selected.where((s) => s != null).length;
  int get _correct {
    var count = 0;
    for (var i = 0; i < _questions.length; i++) {
      if (_selected[i] != null &&
          _selected[i] == _questions[i].correctIndex) {
        count++;
      }
    }
    return count;
  }

  List<int> get _wrongIndexes {
    final out = <int>[];
    for (var i = 0; i < _questions.length; i++) {
      final sel = _selected[i];
      if (sel != null && sel != _questions[i].correctIndex) {
        out.add(i);
      }
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _questions = List.of(widget.questions);
    _selected = List.filled(_questions.length, null);
    _resetTimerForCurrent();
    _trackProgress();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetTimerForCurrent() {
    _timer?.cancel();
    if (!_timerEnabled || _questions.isEmpty) return;
    // ~45s per question, min 30.
    _secondsLeft = 45;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() {
          _secondsLeft = 0;
          // Auto-lock unanswered question as wrong (no selection).
          if (_selected[_current] == null) {
            _selected[_current] = -1; // marked attempted-wrong (no option)
          }
        });
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  Future<void> _trackProgress() async {
    final uid = authService.currentUser?.uid;
    if (uid == null) return;
    try {
      await studentProgressRepository.markGoalTask(
        uid: uid,
        task: 'mcqs',
        done: true,
        sessionType: 'mcq',
        sessionTitle: widget.setTitle,
      );
      await studentProgressRepository.upsertContinueSession(
        uid: uid,
        id: 'mcq_${widget.setTitle.hashCode}',
        type: 'mcq',
        title: widget.setTitle,
        subtitle: '${_questions.length} questions',
        progress: 0.1,
      );
    } catch (_) {}
  }

  Future<void> _toggleBookmark() async {
    final uid = authService.currentUser?.uid;
    final q = _questions[_current];
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to bookmark questions.')),
      );
      return;
    }
    try {
      await studentProgressRepository.toggleBookmark(
        uid: uid,
        id: 'mcq_${q.id}',
        type: 'mcq',
        title: q.question,
        subtitle: widget.setTitle,
        refId: q.id,
        meta: {'setTitle': widget.setTitle},
      );
      setState(() {
        if (_bookmarked.contains(q.id)) {
          _bookmarked.remove(q.id);
        } else {
          _bookmarked.add(q.id);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bookmark failed: $e')),
      );
    }
  }

  Future<void> _askAiExplanation() async {
    final q = _questions[_current];
    setState(() {
      _aiLoading = true;
      _aiExplanation = null;
    });
    try {
      final reply = await aiTeacherService.sendMessage(
        history: const <ChatMessage>[],
        userMessage:
            'Explain this MPSC MCQ briefly for revision.\nQuestion: ${q.question}\n'
            'Options: ${q.options.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('; ')}\n'
            'Correct option index (0-based): ${q.correctIndex}\n'
            'Given explanation: ${q.explanation}',
        extraContext: 'Student is practicing set "${widget.setTitle}".',
      );
      if (!mounted) return;
      setState(() => _aiExplanation = reply);
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiExplanation = 'AI explanation unavailable: $e');
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  void _retryWrongOnly() {
    final wrong = _wrongIndexes;
    if (wrong.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No wrong answers to retry.')),
      );
      return;
    }
    setState(() {
      _questions = [for (final i in wrong) _questions[i]];
      _selected = List.filled(_questions.length, null);
      _current = 0;
      _aiExplanation = null;
    });
    _resetTimerForCurrent();
  }

  void _retryAll() {
    setState(() {
      _questions = List.of(widget.questions);
      _selected = List.filled(_questions.length, null);
      _current = 0;
      _aiExplanation = null;
    });
    _resetTimerForCurrent();
  }

  void _goTo(int index) {
    setState(() {
      _current = index;
      _aiExplanation = null;
    });
    _resetTimerForCurrent();
  }

  Future<void> _persistPracticeScore() async {
    if (_scorePersisted || _attempted <= 0) return;
    _scorePersisted = true;
    final uid = authService.currentUser?.uid;
    if (uid == null) return;
    final first = _questions.isNotEmpty ? _questions.first : null;
    final wrong = _wrongIndexes.length;
    final result = TestResult(
      testTitle: widget.setTitle,
      dateTime: DateTime.now(),
      totalQuestions: _questions.length,
      attempted: _attempted,
      correct: _correct,
      wrong: wrong,
      score: _correct.toDouble(),
      maxScore: _questions.length.toDouble(),
      percentage: _questions.isEmpty ? 0 : (_correct / _questions.length) * 100,
      timeTakenSeconds: 0,
      questionResults: [
        for (var i = 0; i < _questions.length; i++)
          QuestionResult(
            question: _questions[i].question,
            options: _questions[i].options,
            correctIndex: _questions[i].correctIndex,
            selectedIndex: _selected[i] == -1 ? null : _selected[i],
            explanation: _questions[i].explanation,
          ),
      ],
    );
    try {
      await studentProgressRepository.saveTestAttempt(
        uid,
        result,
        testId: 'mcq_${widget.setTitle.hashCode}',
        kind: 'mcq',
        subjectId: first?.subjectId ?? '',
        chapterId: first?.chapterId ?? '',
      );
    } catch (_) {}
  }

  void _showScoreAndReview() {
    _timer?.cancel();
    _persistPracticeScore();
    final wrong = _wrongIndexes;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Score: $_correct / ${_questions.length}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Attempted: $_attempted · Wrong: ${wrong.length}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                if (wrong.isEmpty)
                  const Text('Great job — no wrong answers to review!')
                else ...[
                  const Text(
                    'Wrong-answer review',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      itemCount: wrong.length,
                      itemBuilder: (context, i) {
                        final qi = wrong[i];
                        final q = _questions[qi];
                        final sel = _selected[qi];
                        final your = (sel != null &&
                                sel >= 0 &&
                                sel < q.options.length)
                            ? q.options[sel]
                            : '(no answer)';
                        return Card(
                          child: ListTile(
                            title: Text(
                              q.question,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'Your: $your\nCorrect: ${q.options[q.correctIndex]}'
                              '${q.explanation.isNotEmpty ? '\n${q.explanation}' : ''}',
                            ),
                            isThreeLine: true,
                            onTap: () {
                              Navigator.pop(ctx);
                              _goTo(qi);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _retryWrongOnly();
                        },
                        child: const Text('Retry wrong'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _retryAll();
                        },
                        child: const Text('Retry all'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.setTitle)),
        body: const Center(child: Text('No questions in this set.')),
      );
    }

    final question = _questions[_current];
    final selected = _selected[_current];
    final hasAnswered = selected != null;
    final bookmarked = _bookmarked.contains(question.id);
    final mm = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final ss = (_secondsLeft % 60).toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.setTitle, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _timerEnabled ? 'Disable timer' : 'Enable timer',
            onPressed: () {
              setState(() => _timerEnabled = !_timerEnabled);
              if (_timerEnabled) {
                _resetTimerForCurrent();
              } else {
                _timer?.cancel();
              }
            },
            icon: Icon(
              _timerEnabled ? Icons.timer_rounded : Icons.timer_off_rounded,
            ),
          ),
          IconButton(
            tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark question',
            onPressed: _toggleBookmark,
            icon: Icon(
              bookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_current + 1) / _questions.length,
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
                    'Question ${_current + 1}/${_questions.length}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  Row(
                    children: [
                      if (_timerEnabled) ...[
                        Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: _secondsLeft <= 10
                              ? Colors.red
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$mm:$ss',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _secondsLeft <= 10
                                ? Colors.red
                                : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Text(
                        '✓ $_correct · $_attempted done',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
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
                    final isSelectedOption = selected == i;
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
                              : () {
                                  _timer?.cancel();
                                  setState(() => _selected[_current] = i);
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.navy.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(child: Text(question.options[i])),
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
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.orange,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            question.explanation,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                  height: 1.4,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (hasAnswered) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _aiLoading ? null : _askAiExplanation,
                      icon: _aiLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.psychology_rounded),
                      label: Text(
                        _aiLoading ? 'Asking AI…' : 'Ask AI explanation',
                      ),
                    ),
                    if (_aiExplanation != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _aiExplanation!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
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
                      onPressed:
                          _current == 0 ? null : () => _goTo(_current - 1),
                      child: const Text('Previous'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _current == _questions.length - 1
                          ? _showScoreAndReview
                          : () => _goTo(_current + 1),
                      child: Text(
                        _current == _questions.length - 1 ? 'Finish' : 'Next',
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
