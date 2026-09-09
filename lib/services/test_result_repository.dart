import 'package:mpsc_combine_ai/models/test_result.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';

/// Stores completed test results in memory for the current session and
/// persists them to Firestore (`students/{uid}/testAttempts`) when signed in.
class TestResultRepository {
  TestResultRepository._internal();

  static final TestResultRepository instance = TestResultRepository._internal();

  final List<TestResult> _results = [];

  /// Most recent results first (session cache).
  List<TestResult> getResults() => List.unmodifiable(_results.reversed);

  Future<void> saveResult(
    TestResult result, {
    String? testId,
    String kind = 'test',
    String subjectId = '',
    String chapterId = '',
  }) async {
    _results.add(result);
    final uid = authService.currentUser?.uid;
    if (uid == null) return;
    try {
      await studentProgressRepository.saveTestAttempt(
        uid,
        result,
        testId: testId,
        kind: kind,
        subjectId: subjectId,
        chapterId: chapterId,
      );
      await studentProgressRepository.markGoalTask(
        uid: uid,
        task: 'test',
        done: true,
        sessionType: 'test',
        sessionTitle: result.testTitle,
      );
      await studentProgressRepository.upsertContinueSession(
        uid: uid,
        id: 'test_${testId ?? result.testTitle.hashCode}',
        type: 'test',
        title: result.testTitle,
        subtitle: '${result.percentage.toStringAsFixed(0)}% scored',
        progress: (result.percentage / 100).clamp(0.0, 1.0),
        payload: {'testId': testId ?? ''},
      );
    } catch (_) {
      // Session result still available in-memory even if sync fails.
    }
  }

  /// Persists a practice / PYQ attempt for the signed-in student.
  Future<void> savePracticeAttempt({
    required String title,
    required List<QuestionResult> questionResults,
    String kind = 'mcq',
    String subjectId = '',
    String chapterId = '',
  }) async {
    if (questionResults.isEmpty) return;
    final attempted = questionResults.where((q) => q.isAttempted).length;
    if (attempted <= 0) return;
    final correct = questionResults.where((q) => q.isCorrect).length;
    final wrong = attempted - correct;
    await saveResult(
      TestResult(
        testTitle: title,
        dateTime: DateTime.now(),
        totalQuestions: questionResults.length,
        attempted: attempted,
        correct: correct,
        wrong: wrong,
        score: correct.toDouble(),
        maxScore: questionResults.length.toDouble(),
        percentage:
            questionResults.isEmpty ? 0 : (correct / questionResults.length) * 100,
        timeTakenSeconds: 0,
        questionResults: questionResults,
      ),
      kind: kind,
      subjectId: subjectId,
      chapterId: chapterId,
    );
  }
}
