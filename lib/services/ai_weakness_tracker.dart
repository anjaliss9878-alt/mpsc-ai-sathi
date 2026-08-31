import 'dart:async';

import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_progress_repository.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';
import 'package:mpsc_combine_ai/services/weakness_analysis.dart';

export 'package:mpsc_combine_ai/services/weakness_analysis.dart';

/// One weak/strong signal derived from tests, classroom quizzes, or both.
/// Daily Planner depends on [isWeak] / [isStrong] / ids — extra fields are
/// optional so existing planner tests stay valid.
class WeakTopicSignal {
  const WeakTopicSignal({
    required this.label,
    required this.scorePercent,
    required this.source,
    this.subjectId = '',
    this.chapterId = '',
    this.subjectTitle = '',
    this.attempted = 0,
    this.correct = 0,
    this.wrong = 0,
    this.priority = 0,
    this.band = WeaknessBand.insufficient,
    this.trend = PerformanceTrend.insufficient,
  });

  final String label;
  final double scorePercent;
  final String source;
  final String subjectId;
  final String chapterId;
  final String subjectTitle;
  final int attempted;
  final int correct;
  final int wrong;
  final int priority;
  final WeaknessBand band;
  final PerformanceTrend trend;

  bool isWeakFor(WeaknessThresholds thresholds) =>
      scorePercent < thresholds.improvingMin;

  bool isStrongFor(WeaknessThresholds thresholds) =>
      scorePercent >= thresholds.strongMin;

  bool get isWeak => isWeakFor(WeaknessThresholds.defaults);

  bool get isStrong => isStrongFor(WeaknessThresholds.defaults);
}

class WeaknessSnapshot {
  const WeaknessSnapshot({
    required this.signals,
    this.averageTestPercent,
    this.attemptsThisWeek = 0,
    this.analysis,
    this.thresholds = WeaknessThresholds.defaults,
  });

  final List<WeakTopicSignal> signals;
  final double? averageTestPercent;
  final int attemptsThisWeek;
  final WeaknessAnalysisResult? analysis;
  final WeaknessThresholds thresholds;

  List<WeakTopicSignal> get weakTopics {
    final list = signals.where((s) => s.isWeakFor(thresholds)).toList();
    list.sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;
      return a.scorePercent.compareTo(b.scorePercent);
    });
    return list;
  }

  List<WeakTopicSignal> get strongTopics =>
      signals.where((s) => s.isStrongFor(thresholds)).toList();

  bool get hasPoorRecentTests =>
      (averageTestPercent != null &&
          averageTestPercent! < thresholds.improvingMin) ||
      weakTopics.isNotEmpty;

  bool get needsWeeklyTest => attemptsThisWeek == 0;

  bool get hasPerformance =>
      analysis?.hasPerformance == true ||
      signals.any((s) => s.attempted > 0 || s.scorePercent > 0);
}

/// Scores weak/strong topics from existing test attempts + classroom quizzes
/// + Feature 2 syllabus progress. Daily Planner only calls [load].
abstract class AiWeaknessTracker {
  Future<WeaknessSnapshot> load(
    String uid, {
    SyllabusProgressSnapshot? syllabus,
    DateTime? now,
  });

  Stream<WeaknessSnapshot> watch(
    String uid, {
    DateTime? now,
  }) async* {
    yield await load(uid, now: now);
  }
}

class FirestoreAiWeaknessTracker implements AiWeaknessTracker {
  FirestoreAiWeaknessTracker({
    StudentProgressRepository? progress,
    LessonProgressRepository? classroom,
    SyllabusProgressTracker? syllabus,
    ProfileRepository? profiles,
    this.thresholds = WeaknessThresholds.defaults,
  })  : _progress = progress ?? studentProgressRepository,
        _classroom = classroom ?? lessonProgressRepository,
        _syllabus = syllabus,
        _profiles = profiles;

  final StudentProgressRepository _progress;
  final LessonProgressRepository _classroom;
  final SyllabusProgressTracker? _syllabus;
  final ProfileRepository? _profiles;
  final WeaknessThresholds thresholds;

  SyllabusProgressTracker get _syllabusTracker =>
      _syllabus ?? syllabusProgressTracker;

  @override
  Future<WeaknessSnapshot> load(
    String uid, {
    SyllabusProgressSnapshot? syllabus,
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now();
    final topics = syllabus ?? await _syllabusTracker.load(uid);
    final attempts = await _progress.getTestAttempts(uid);
    final classroom = await _classroom.getAllOnce(uid);
    var targetExam = '';
    try {
      final profile = await (_profiles ?? profileRepository).getProfile(uid);
      targetExam = profile?.targetExam ?? '';
    } catch (_) {
      targetExam = '';
    }
    return _fromSources(
      attempts: attempts,
      classroom: classroom,
      syllabus: topics,
      now: clock,
      targetExam: targetExam,
    );
  }

  @override
  Stream<WeaknessSnapshot> watch(String uid, {DateTime? now}) {
    return Stream.multi((controller) {
      List<PersistedTestAttempt>? attempts;
      List<ClassroomProgress>? classroom;
      SyllabusProgressSnapshot? syllabus;
      var targetExam = '';

      Future<void> emit() async {
        if (attempts == null || classroom == null || syllabus == null) return;
        try {
          controller.add(
            _fromSources(
              attempts: attempts!,
              classroom: classroom!,
              syllabus: syllabus!,
              now: now ?? DateTime.now(),
              targetExam: targetExam,
            ),
          );
        } catch (e, st) {
          controller.addError(e, st);
        }
      }

      final subAttempts = _progress.watchTestAttempts(uid).listen(
        (list) {
          attempts = list;
          emit();
        },
        onError: controller.addError,
      );
      final subClass = _classroom.watchAll(uid, limit: 400).listen(
        (list) {
          classroom = list;
          emit();
        },
        onError: controller.addError,
      );
      final subSyllabus = _syllabusTracker.watch(uid).listen(
        (snap) {
          syllabus = snap;
          emit();
        },
        onError: controller.addError,
      );
      final subProfile = (_profiles ?? profileRepository).watchProfile(uid).listen(
        (profile) {
          targetExam = profile?.targetExam ?? '';
          emit();
        },
        onError: (_) {
          // Profile is optional for classification.
        },
      );

      controller.onCancel = () async {
        await subAttempts.cancel();
        await subClass.cancel();
        await subSyllabus.cancel();
        await subProfile.cancel();
      };
    });
  }

  WeaknessSnapshot _fromSources({
    required List<PersistedTestAttempt> attempts,
    required List<ClassroomProgress> classroom,
    required SyllabusProgressSnapshot syllabus,
    required DateTime now,
    required String targetExam,
  }) {
    final samples = <PerformanceSample>[];
    for (final attempt in attempts) {
      if (attempt.totalQuestions <= 0 && attempt.attempted <= 0) continue;
      final match = matchSyllabusTopic(
        title: attempt.testTitle,
        topics: syllabus.topics,
      );
      final attempted =
          attempt.attempted > 0 ? attempt.attempted : attempt.totalQuestions;
      var source = attempt.kind.trim().isEmpty ? 'test' : attempt.kind.trim();
      if (source == 'test') {
        final hay = attempt.testTitle.toLowerCase();
        if (hay.contains('pyq') || hay.contains('previous year')) {
          source = 'pyq';
        }
      }
      samples.add(
        PerformanceSample(
          at: attempt.dateTime,
          attempted: attempted,
          correct: attempt.correct,
          wrong: attempt.wrong,
          timeSeconds: attempt.timeTakenSeconds,
          source: source,
          label: attempt.testTitle,
          subjectId: attempt.subjectId.isNotEmpty
              ? attempt.subjectId
              : (match?.subjectId ?? ''),
          chapterId: attempt.chapterId.isNotEmpty
              ? attempt.chapterId
              : (match?.chapterId ?? ''),
          subjectTitle: match?.subjectTitle ?? '',
        ),
      );
    }

    for (final prog in classroom) {
      if (prog.quizTotal <= 0) continue;
      SyllabusTopicProgress? match;
      for (final t in syllabus.topics) {
        if (t.chapterId == prog.chapterId) {
          match = t;
          break;
        }
      }
      samples.add(
        PerformanceSample(
          at: prog.updatedAt,
          attempted: prog.quizTotal,
          correct: prog.quizScore,
          wrong: prog.quizScore >= prog.quizTotal
              ? 0
              : prog.quizTotal - prog.quizScore,
          source: 'quiz',
          label: prog.topicName.isNotEmpty ? prog.topicName : 'Classroom quiz',
          subjectId: match?.subjectId ?? prog.subjectId,
          chapterId: prog.chapterId,
          subjectTitle: match?.subjectTitle ?? '',
        ),
      );
    }

    final analyzed = analyzeWeakness(
      WeaknessAnalysisInput(
        samples: samples,
        syllabus: syllabus,
        now: now,
        thresholds: thresholds,
        targetExam: targetExam,
      ),
    );

    final signals = [
      for (final topic in analyzed.topics)
        if (topic.hasPerformance)
          WeakTopicSignal(
            label: topic.label,
            scorePercent: topic.accuracyPercent,
            source: topic.sources.isEmpty ? 'test' : topic.sources.first,
            subjectId: topic.subjectId,
            chapterId: topic.chapterId,
            subjectTitle: topic.subjectTitle,
            attempted: topic.attempted,
            correct: topic.correct,
            wrong: topic.wrong,
            priority: topic.priority,
            band: topic.band,
            trend: topic.trend,
          ),
    ];

    double? avg;
    final testSamples = samples.where((s) => s.source == 'test').toList();
    if (testSamples.isNotEmpty) {
      avg = analyzed.overallAccuracy;
      final testAttempted =
          testSamples.fold<int>(0, (s, x) => s + x.attempted);
      final testCorrect = testSamples.fold<int>(0, (s, x) => s + x.correct);
      if (testAttempted > 0) {
        avg = weaknessAccuracyPercent(
          correct: testCorrect,
          attempted: testAttempted,
        );
      }
    } else if (analyzed.hasPerformance) {
      avg = analyzed.overallAccuracy;
    }

    return WeaknessSnapshot(
      signals: signals,
      averageTestPercent: avg,
      attemptsThisWeek: analyzed.attemptsThisWeek,
      analysis: analyzed,
      thresholds: thresholds,
    );
  }
}

final AiWeaknessTracker aiWeaknessTracker = FirestoreAiWeaknessTracker();
