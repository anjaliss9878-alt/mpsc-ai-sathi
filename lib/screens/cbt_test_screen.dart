import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/test_item.dart';
import 'package:mpsc_combine_ai/models/test_result.dart';
import 'package:mpsc_combine_ai/screens/result_screen.dart';
import 'package:mpsc_combine_ai/services/test_result_repository.dart';

/// Full-screen timed CBT/mock test attempt.
///
/// Questions, duration and the marking scheme all come from [test] (loaded
/// from Firestore by [MockTestsScreen]) instead of being hardcoded, so any
/// test added/edited from the Admin Panel is immediately attemptable here.
class CbtTestScreen extends StatefulWidget {
  const CbtTestScreen({super.key, required this.test});

  final TestItem test;

  @override
  State<CbtTestScreen> createState() => _CbtTestScreenState();
}

class _CbtTestScreenState extends State<CbtTestScreen> {
  int currentQuestion = 0;
  late int remainingSeconds = widget.test.durationSeconds;
  Timer? timer;

  late final List<int?> selectedAnswers =
      List.filled(widget.test.questions.length, null);

  List<TestQuestion> get questions => widget.test.questions;

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  void startTimer() {
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds > 0) {
        setState(() {
          remainingSeconds--;
        });
      } else {
        timer.cancel();
        submitTest();
      }
    });
  }

  String get timerText {
    final m = remainingSeconds ~/ 60;
    final s = remainingSeconds % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  void nextQuestion() {
    if (currentQuestion < questions.length - 1) {
      setState(() {
        currentQuestion++;
      });
    }
  }

  void previousQuestion() {
    if (currentQuestion > 0) {
      setState(() {
        currentQuestion--;
      });
    }
  }

  void submitTest() {
    timer?.cancel();

    final timeTakenSeconds = widget.test.durationSeconds - remainingSeconds;

    final questionResults = List.generate(questions.length, (i) {
      final q = questions[i];
      return QuestionResult(
        question: q.question,
        options: q.options,
        correctIndex: q.correctIndex,
        selectedIndex: selectedAnswers[i],
        explanation: q.explanation,
      );
    });

    final attempted = questionResults.where((q) => q.isAttempted).length;
    final correct = questionResults.where((q) => q.isCorrect).length;
    final wrong = attempted - correct;
    final correctMarks = widget.test.correctMarks;
    final negativeMarks = widget.test.negativeMarks;
    final maxScore = questions.length * correctMarks;
    final score = (correct * correctMarks) - (wrong * negativeMarks);
    final percentage = maxScore == 0 ? 0.0 : (score / maxScore) * 100;

    final result = TestResult(
      testTitle: widget.test.title,
      dateTime: DateTime.now(),
      totalQuestions: questions.length,
      attempted: attempted,
      correct: correct,
      wrong: wrong,
      score: score,
      maxScore: maxScore,
      percentage: percentage,
      timeTakenSeconds: timeTakenSeconds,
      questionResults: questionResults,
    );

    TestResultRepository.instance.saveResult(result);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ResultScreen(result: result, test: widget.test),
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.test.title)),
        body: const Center(child: Text('This test has no questions yet.')),
      );
    }

    final question = questions[currentQuestion];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exit test?'),
            content: const Text('Your progress in this attempt will be lost.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
        if (shouldExit ?? false) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.test.title, overflow: TextOverflow.ellipsis),
          actions: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  timerText,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Question ${currentQuestion + 1}/${questions.length}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                question.question,
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  children: question.options.asMap().entries.map(
                    (e) => RadioListTile<int>(
                      title: Text(e.value),
                      value: e.key,
                      groupValue: selectedAnswers[currentQuestion],
                      onChanged: (value) {
                        setState(() {
                          selectedAnswers[currentQuestion] = value;
                        });
                      },
                    ),
                  ).toList(),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    onPressed: currentQuestion == 0 ? null : previousQuestion,
                    child: const Text("Previous"),
                  ),
                  currentQuestion == questions.length - 1
                      ? ElevatedButton(
                          onPressed: submitTest,
                          child: const Text("Submit"),
                        )
                      : ElevatedButton(
                          onPressed: nextQuestion,
                          child: const Text("Next"),
                        ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
