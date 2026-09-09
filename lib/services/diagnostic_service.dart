import 'package:mpsc_combine_ai/data/diagnostic_questions.dart';
import 'package:mpsc_combine_ai/data/student_curriculum.dart';
import 'package:mpsc_combine_ai/data/student_onboarding.dart';
import 'package:mpsc_combine_ai/models/test_result.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/weakness_analysis.dart';

class DiagnosticAreaResult {
  const DiagnosticAreaResult({
    required this.areaId,
    required this.title,
    required this.attempted,
    required this.correct,
    required this.percent,
    required this.band,
    this.subjectId = '',
    this.chapterId = '',
  });

  final String areaId;
  final String title;
  final int attempted;
  final int correct;
  final double percent;
  final WeaknessBand band;
  final String subjectId;
  final String chapterId;

  String get mappingLine {
    final chapter = groupBChapterForArea(areaId);
    final topic = (chapter?.title ?? '').trim();
    if (topic.isEmpty) return '$title (${percent.round()}%)';
    return '$title → $topic (${percent.round()}%)';
  }

  Map<String, dynamic> toMap() => {
        'areaId': areaId,
        'title': title,
        'attempted': attempted,
        'correct': correct,
        'percent': percent,
        'band': band.name,
        'subjectId': subjectId,
        'chapterId': chapterId,
      };

  factory DiagnosticAreaResult.fromMap(Map<String, dynamic> map) {
    return DiagnosticAreaResult(
      areaId: map['areaId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      attempted: (map['attempted'] as num?)?.toInt() ?? 0,
      correct: (map['correct'] as num?)?.toInt() ?? 0,
      percent: (map['percent'] as num?)?.toDouble() ?? 0,
      band: WeaknessBand.values.firstWhere(
        (b) => b.name == (map['band'] as String? ?? ''),
        orElse: () => WeaknessThresholds.defaults.bandFor(
          (map['percent'] as num?)?.toDouble() ?? 0,
        ),
      ),
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
    );
  }
}

class DiagnosticAttemptResult {
  const DiagnosticAttemptResult({
    required this.attemptId,
    required this.targetExam,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.scorePercentage,
    required this.completedAt,
    required this.areaResults,
    required this.questionResults,
  });

  final String attemptId;
  final String targetExam;
  final int totalQuestions;
  final int correctAnswers;
  final double scorePercentage;
  final DateTime completedAt;
  final List<DiagnosticAreaResult> areaResults;
  final List<QuestionResult> questionResults;

  List<DiagnosticAreaResult> get weakAreas => areaResults
      .where((a) => a.band == WeaknessBand.weak || a.band == WeaknessBand.critical)
      .toList();

  List<DiagnosticAreaResult> get improvingAreas =>
      areaResults.where((a) => a.band == WeaknessBand.improving).toList();

  List<DiagnosticAreaResult> get strongAreas =>
      areaResults.where((a) => a.band == WeaknessBand.strong).toList();
}

List<String> diagnosticImprovementLines({
  required DiagnosticAttemptResult previous,
  required DiagnosticAttemptResult current,
}) {
  final prev = {for (final a in previous.areaResults) a.areaId: a};
  final lines = <String>[];
  for (final a in current.areaResults) {
    final old = prev[a.areaId];
    if (old == null) continue;
    final arrow = a.percent >= old.percent ? '↑' : '↓';
    lines.add(
      '${a.title}: ${old.percent.round()}% → ${a.percent.round()}% $arrow',
    );
  }
  return lines;
}

class DiagnosticService {
  DiagnosticService({
    StudentProgressRepository? progress,
    this.thresholds = WeaknessThresholds.defaults,
  }) : _progressOverride = progress;

  final StudentProgressRepository? _progressOverride;
  final WeaknessThresholds thresholds;

  StudentProgressRepository get _progress =>
      _progressOverride ?? studentProgressRepository;

  List<DiagnosticQuestion> questionsForExam(String targetExam) {
    if (isGroupBCombinedTargetExam(targetExam) || targetExam.trim().isEmpty) {
      return groupBDiagnosticQuestions();
    }
    return groupBDiagnosticQuestions();
  }

  DiagnosticAttemptResult score({
    required String attemptId,
    required String targetExam,
    required List<DiagnosticQuestion> questions,
    required List<int?> selected,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final questionResults = <QuestionResult>[];
    final byArea = <String, List<int>>{};
    var correct = 0;
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      final sel = i < selected.length ? selected[i] : null;
      final isCorrect = sel != null && sel == q.correctIndex;
      if (isCorrect) correct++;
      questionResults.add(
        QuestionResult(
          question: q.question,
          options: q.options,
          correctIndex: q.correctIndex,
          selectedIndex: sel,
          explanation: q.explanation,
        ),
      );
      byArea.putIfAbsent(q.areaId, () => [0, 0]);
      byArea[q.areaId]![0]++;
      if (isCorrect) byArea[q.areaId]![1]++;
    }

    final areaResults = <DiagnosticAreaResult>[];
    for (final entry in byArea.entries) {
      final attempted = entry.value[0];
      final areaCorrect = entry.value[1];
      final percent = attempted == 0 ? 0.0 : (areaCorrect / attempted) * 100;
      final chapter = groupBChapterForArea(entry.key);
      areaResults.add(
        DiagnosticAreaResult(
          areaId: entry.key,
          title: syllabusAreaTitle(entry.key),
          attempted: attempted,
          correct: areaCorrect,
          percent: percent,
          band: thresholds.bandFor(percent),
          subjectId: chapter?.subjectId ?? '',
          chapterId: chapter?.id ?? '',
        ),
      );
    }

    final total = questions.length;
    return DiagnosticAttemptResult(
      attemptId: attemptId,
      targetExam: targetExam,
      totalQuestions: total,
      correctAnswers: correct,
      scorePercentage: total == 0 ? 0 : (correct / total) * 100,
      completedAt: clock,
      areaResults: areaResults,
      questionResults: questionResults,
    );
  }

  /// Saves the diagnostic attempt and seeds existing weakness data via
  /// `testAttempts` (kind: diagnostic — not PYQ).
  Future<void> persist(String uid, DiagnosticAttemptResult result) async {
    final owner = uid.trim();
    if (owner.isEmpty) {
      throw StateError(
        'Firebase Auth UID is required to save the diagnostic.',
      );
    }
    await _progress.saveDiagnosticAttempt(
      owner,
      {
        'targetExam': result.targetExam,
        'totalQuestions': result.totalQuestions,
        'correctAnswers': result.correctAnswers,
        'scorePercentage': result.scorePercentage,
        'completedAt': result.completedAt.toIso8601String(),
        'kind': 'diagnostic',
        'areaResults': result.areaResults.map((a) => a.toMap()).toList(),
        'strongAreas': result.strongAreas.map((a) => a.areaId).toList(),
        'improvingAreas': result.improvingAreas.map((a) => a.areaId).toList(),
        'weakAreas': result.weakAreas.map((a) => a.areaId).toList(),
      },
      attemptId: result.attemptId,
    );

    var attempted = 0;
    var wrong = 0;
    for (final q in result.questionResults) {
      if (q.isAttempted) attempted++;
      if (q.isAttempted && !q.isCorrect) wrong++;
    }

    await _progress.saveTestAttempt(
      owner,
      TestResult(
        testTitle: 'Diagnostic Test',
        dateTime: result.completedAt,
        totalQuestions: result.totalQuestions,
        attempted: attempted,
        correct: result.correctAnswers,
        wrong: wrong,
        score: result.correctAnswers.toDouble(),
        maxScore: result.totalQuestions.toDouble(),
        percentage: result.scorePercentage,
        timeTakenSeconds: 0,
        questionResults: result.questionResults,
      ),
      testId: result.attemptId,
      attemptId: 'diag_${result.attemptId}',
      kind: 'diagnostic',
    );

    for (final area in result.areaResults) {
      final areaWrong = area.attempted - area.correct;
      await _progress.saveTestAttempt(
        owner,
        TestResult(
          testTitle: 'Diagnostic · ${area.title}',
          dateTime: result.completedAt,
          totalQuestions: area.attempted,
          attempted: area.attempted,
          correct: area.correct,
          wrong: areaWrong < 0 ? 0 : areaWrong,
          score: area.correct.toDouble(),
          maxScore: area.attempted.toDouble(),
          percentage: area.percent,
          timeTakenSeconds: 0,
          questionResults: const [],
        ),
        testId: result.attemptId,
        attemptId: 'diag_${result.attemptId}_${area.areaId}',
        kind: 'diagnostic',
        subjectId: area.subjectId,
        chapterId: area.chapterId,
        areaId: area.areaId,
      );
    }
  }

  DiagnosticAttemptResult? parseStored(Map<String, dynamic>? data) {
    if (data == null) return null;
    final areas = <DiagnosticAreaResult>[];
    final rawAreas = data['areaResults'];
    if (rawAreas is List) {
      for (final item in rawAreas) {
        if (item is Map) {
          areas.add(
            DiagnosticAreaResult.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return DiagnosticAttemptResult(
      attemptId: data['id'] as String? ?? '',
      targetExam: data['targetExam'] as String? ?? '',
      totalQuestions: (data['totalQuestions'] as num?)?.toInt() ?? 0,
      correctAnswers: (data['correctAnswers'] as num?)?.toInt() ?? 0,
      scorePercentage: (data['scorePercentage'] as num?)?.toDouble() ?? 0,
      completedAt:
          DateTime.tryParse(data['completedAt'] as String? ?? '') ??
              DateTime.now(),
      areaResults: areas,
      questionResults: const [],
    );
  }
}

final DiagnosticService diagnosticService = DiagnosticService();
