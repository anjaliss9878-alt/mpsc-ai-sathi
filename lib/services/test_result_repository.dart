import 'package:mpsc_combine_ai/models/test_result.dart';

/// Stores completed test results so recent scores can be shown to the user.
///
/// Currently backed by an in-memory list (results reset on app restart).
/// The method signatures are intentionally storage-agnostic so this can be
/// swapped for Firestore/local-disk persistence later without changing any
/// calling code (e.g. `saveResult`/`getResults` could become `async` calls
/// to Firebase).
class TestResultRepository {
  TestResultRepository._internal();

  static final TestResultRepository instance =
      TestResultRepository._internal();

  final List<TestResult> _results = [];

  /// Most recent results first.
  List<TestResult> getResults() => List.unmodifiable(_results.reversed);

  void saveResult(TestResult result) {
    _results.add(result);
  }
}
