import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';

/// Single place for Weakness Tracker cut-offs. UI and planner read these
/// through [WeaknessSnapshot.thresholds] instead of scattering literals.
class WeaknessThresholds {
  const WeaknessThresholds({
    this.strongMin = 80,
    this.improvingMin = 60,
    this.weakMin = 40,
    this.trendDelta = 5,
    this.minSamplesForTrend = 2,
    this.recentWindowDays = 14,
    this.staleRevisionDays = 14,
    this.repeatedWrongSessions = 2,
    this.examImportantMinutes = 40,
  });

  static const defaults = WeaknessThresholds();

  /// Accuracy >= this ⇒ Strong.
  final double strongMin;

  /// Accuracy >= this and < [strongMin] ⇒ Improving.
  final double improvingMin;

  /// Accuracy >= this and < [improvingMin] ⇒ Weak. Below ⇒ Critical.
  final double weakMin;

  /// Minimum absolute accuracy change (percentage points) to call a trend.
  final double trendDelta;

  final int minSamplesForTrend;
  final int recentWindowDays;
  final int staleRevisionDays;
  final int repeatedWrongSessions;

  /// Chapters with at least this many planned minutes are treated as
  /// higher-weight for the target exam (existing syllabus field, not invented).
  final int examImportantMinutes;

  WeaknessBand bandFor(double accuracyPercent) {
    if (accuracyPercent >= strongMin) return WeaknessBand.strong;
    if (accuracyPercent >= improvingMin) return WeaknessBand.improving;
    if (accuracyPercent >= weakMin) return WeaknessBand.weak;
    return WeaknessBand.critical;
  }
}

enum WeaknessBand { strong, improving, weak, critical, insufficient }

extension WeaknessBandX on WeaknessBand {
  bool get isWeakLike =>
      this == WeaknessBand.weak || this == WeaknessBand.critical;

  String get label => switch (this) {
        WeaknessBand.strong => 'Strong',
        WeaknessBand.improving => 'Improving',
        WeaknessBand.weak => 'Weak',
        WeaknessBand.critical => 'Critical',
        WeaknessBand.insufficient => 'Not enough data',
      };

  String get labelMr => switch (this) {
        WeaknessBand.strong => 'मजबूत',
        WeaknessBand.improving => 'सुधारत आहे',
        WeaknessBand.weak => 'कमकुवत',
        WeaknessBand.critical => 'गंभीर',
        WeaknessBand.insufficient => 'पुरेसा डेटा नाही',
      };

  String get priorityLabel => switch (this) {
        WeaknessBand.critical => 'High',
        WeaknessBand.weak => 'Medium',
        WeaknessBand.improving => 'Low',
        WeaknessBand.strong => 'Low',
        WeaknessBand.insufficient => '—',
      };
}

enum PerformanceTrend { improving, stable, declining, insufficient }

extension PerformanceTrendX on PerformanceTrend {
  String get label => switch (this) {
        PerformanceTrend.improving => 'Improving',
        PerformanceTrend.stable => 'Stable',
        PerformanceTrend.declining => 'Declining',
        PerformanceTrend.insufficient => 'Not enough data',
      };

  String get labelMr => switch (this) {
        PerformanceTrend.improving => 'सुधारत आहे',
        PerformanceTrend.stable => 'स्थिर',
        PerformanceTrend.declining => 'घसरत आहे',
        PerformanceTrend.insufficient => 'पुरेसा डेटा नाही',
      };
}

enum WeaknessActionKind { revise, mcq, pyq, aiTeacher, test, syllabus }

class WeaknessAction {
  const WeaknessAction({required this.kind, required this.label});

  final WeaknessActionKind kind;
  final String label;
}

/// One real scored event (test attempt or classroom quiz). Never synthesized.
class PerformanceSample {
  const PerformanceSample({
    required this.at,
    required this.attempted,
    required this.correct,
    required this.wrong,
    required this.source,
    required this.label,
    this.timeSeconds = 0,
    this.subjectId = '',
    this.chapterId = '',
    this.subjectTitle = '',
  });

  final DateTime at;
  final int attempted;
  final int correct;
  final int wrong;
  final int timeSeconds;
  final String source;
  final String label;
  final String subjectId;
  final String chapterId;
  final String subjectTitle;

  double get accuracyPercent =>
      weaknessAccuracyPercent(correct: correct, attempted: attempted);
}

class TopicWeaknessReport {
  const TopicWeaknessReport({
    required this.label,
    required this.band,
    required this.trend,
    required this.priority,
    required this.attempted,
    required this.correct,
    required this.wrong,
    required this.accuracyPercent,
    required this.actions,
    this.subjectId = '',
    this.chapterId = '',
    this.subjectTitle = '',
    this.syllabusStatus,
    this.timeSeconds = 0,
    this.revisionCount = 0,
    this.lastStudiedAt,
    this.repeatedMistakes = false,
    this.examImportant = false,
    this.staleRevision = false,
    this.sources = const [],
  });

  final String label;
  final String subjectId;
  final String chapterId;
  final String subjectTitle;
  final WeaknessBand band;
  final PerformanceTrend trend;
  final int priority;
  final int attempted;
  final int correct;
  final int wrong;
  final double accuracyPercent;
  final SyllabusTopicStatus? syllabusStatus;
  final int timeSeconds;
  final int revisionCount;
  final DateTime? lastStudiedAt;
  final bool repeatedMistakes;
  final bool examImportant;
  final bool staleRevision;
  final List<String> sources;
  final List<WeaknessAction> actions;

  bool get hasPerformance => attempted > 0;
}

class SubjectWeaknessReport {
  const SubjectWeaknessReport({
    required this.subjectId,
    required this.subjectTitle,
    required this.band,
    required this.trend,
    required this.attempted,
    required this.correct,
    required this.wrong,
    required this.accuracyPercent,
    required this.topics,
    this.timeSeconds = 0,
  });

  final String subjectId;
  final String subjectTitle;
  final WeaknessBand band;
  final PerformanceTrend trend;
  final int attempted;
  final int correct;
  final int wrong;
  final double accuracyPercent;
  final int timeSeconds;
  final List<TopicWeaknessReport> topics;

  bool get hasPerformance => attempted > 0;
}

double weaknessAccuracyPercent({
  required int correct,
  required int attempted,
}) {
  if (attempted <= 0) return 0;
  return (correct / attempted) * 100;
}

PerformanceTrend weaknessTrend({
  required double? recentAccuracy,
  required double? previousAccuracy,
  required int recentSamples,
  required int previousSamples,
  WeaknessThresholds thresholds = WeaknessThresholds.defaults,
}) {
  if (recentSamples < thresholds.minSamplesForTrend ||
      previousSamples < thresholds.minSamplesForTrend ||
      recentAccuracy == null ||
      previousAccuracy == null) {
    return PerformanceTrend.insufficient;
  }
  final delta = recentAccuracy - previousAccuracy;
  if (delta >= thresholds.trendDelta) return PerformanceTrend.improving;
  if (delta <= -thresholds.trendDelta) return PerformanceTrend.declining;
  return PerformanceTrend.stable;
}

int weaknessPriority({
  required WeaknessBand band,
  required bool repeatedMistakes,
  required PerformanceTrend trend,
  required bool incompleteSyllabus,
  required bool staleRevision,
  required bool examImportant,
}) {
  var score = switch (band) {
    WeaknessBand.critical => 40,
    WeaknessBand.weak => 25,
    WeaknessBand.improving => 8,
    WeaknessBand.strong => 0,
    WeaknessBand.insufficient => 0,
  };
  if (repeatedMistakes) score += 12;
  if (trend == PerformanceTrend.declining) score += 15;
  if (incompleteSyllabus) score += 10;
  if (staleRevision) score += 10;
  if (examImportant) score += 8;
  if (score < 0) return 0;
  if (score > 100) return 100;
  return score;
}

List<WeaknessAction> weaknessActionsFor({
  required WeaknessBand band,
  required SyllabusTopicStatus? syllabusStatus,
  required String topicTitle,
}) {
  final title = topicTitle.trim().isEmpty ? 'this topic' : topicTitle.trim();
  final incomplete = syllabusStatus != SyllabusTopicStatus.completed;
  final actions = <WeaknessAction>[];

  if (incomplete) {
    actions.add(
      WeaknessAction(kind: WeaknessActionKind.syllabus, label: 'Complete $title'),
    );
    actions.add(
      WeaknessAction(
        kind: WeaknessActionKind.aiTeacher,
        label: 'Open AI Teacher explanation',
      ),
    );
  } else {
    actions.add(
      WeaknessAction(kind: WeaknessActionKind.revise, label: 'Revise $title'),
    );
  }

  if (band == WeaknessBand.critical || band == WeaknessBand.weak) {
    actions.add(
      const WeaknessAction(
        kind: WeaknessActionKind.mcq,
        label: 'Practice targeted MCQs',
      ),
    );
    actions.add(
      const WeaknessAction(
        kind: WeaknessActionKind.pyq,
        label: 'Attempt related PYQs',
      ),
    );
    actions.add(
      const WeaknessAction(
        kind: WeaknessActionKind.test,
        label: 'Take a short revision test',
      ),
    );
    if (!incomplete) {
      actions.add(
        const WeaknessAction(
          kind: WeaknessActionKind.aiTeacher,
          label: 'Open AI Teacher explanation',
        ),
      );
    }
  } else if (band == WeaknessBand.improving) {
    actions.add(
      const WeaknessAction(
        kind: WeaknessActionKind.mcq,
        label: 'Continue MCQ practice',
      ),
    );
  } else if (band == WeaknessBand.strong) {
    actions.add(
      WeaknessAction(kind: WeaknessActionKind.revise, label: 'Light revision: $title'),
    );
  }
  return actions;
}

class WeaknessAnalysisInput {
  const WeaknessAnalysisInput({
    required this.samples,
    required this.syllabus,
    required this.now,
    this.thresholds = WeaknessThresholds.defaults,
    this.targetExam = '',
  });

  final List<PerformanceSample> samples;
  final SyllabusProgressSnapshot syllabus;
  final DateTime now;
  final WeaknessThresholds thresholds;
  final String targetExam;
}

class WeaknessAnalysisResult {
  const WeaknessAnalysisResult({
    required this.topics,
    required this.subjects,
    required this.overallAttempted,
    required this.overallCorrect,
    required this.overallWrong,
    required this.overallAccuracy,
    required this.overallTrend,
    required this.timeSpentSeconds,
    required this.attemptsThisWeek,
    required this.thresholds,
  });

  final List<TopicWeaknessReport> topics;
  final List<SubjectWeaknessReport> subjects;
  final int overallAttempted;
  final int overallCorrect;
  final int overallWrong;
  final double overallAccuracy;
  final PerformanceTrend overallTrend;
  final int timeSpentSeconds;
  final int attemptsThisWeek;
  final WeaknessThresholds thresholds;

  bool get hasPerformance => overallAttempted > 0;

  List<TopicWeaknessReport> get priorityWeakAreas => topics
      .where((t) => t.hasPerformance && t.band.isWeakLike)
      .toList()
    ..sort((a, b) => b.priority.compareTo(a.priority));

  List<TopicWeaknessReport> get weakIncomplete => topics
      .where(
        (t) =>
            t.hasPerformance &&
            t.band.isWeakLike &&
            t.syllabusStatus != null &&
            t.syllabusStatus != SyllabusTopicStatus.completed,
      )
      .toList();

  List<TopicWeaknessReport> get weakCompleted => topics
      .where(
        (t) =>
            t.hasPerformance &&
            t.band.isWeakLike &&
            t.syllabusStatus == SyllabusTopicStatus.completed,
      )
      .toList();

  List<TopicWeaknessReport> get strongCompleted => topics
      .where(
        (t) =>
            t.hasPerformance &&
            t.band == WeaknessBand.strong &&
            t.syllabusStatus == SyllabusTopicStatus.completed,
      )
      .toList();
}

WeaknessAnalysisResult analyzeWeakness(WeaknessAnalysisInput input) {
  final t = input.thresholds;
  final now = input.now;
  final recentStart = now.subtract(Duration(days: t.recentWindowDays));
  final previousStart =
      now.subtract(Duration(days: t.recentWindowDays * 2));
  final weekStart = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));

  final byChapter = <String, List<PerformanceSample>>{};
  final bySubject = <String, List<PerformanceSample>>{};
  final subjectTitles = <String, String>{};

  for (final sample in input.samples) {
    if (sample.attempted <= 0) continue;
    if (sample.chapterId.isNotEmpty) {
      byChapter.putIfAbsent(sample.chapterId, () => []).add(sample);
    }
    final subjectKey = sample.subjectId.isNotEmpty
        ? sample.subjectId
        : (sample.subjectTitle.isNotEmpty
            ? 'title:${sample.subjectTitle.toLowerCase()}'
            : '');
    if (subjectKey.isNotEmpty) {
      bySubject.putIfAbsent(subjectKey, () => []).add(sample);
      subjectTitles[subjectKey] = sample.subjectTitle.isNotEmpty
          ? sample.subjectTitle
          : sample.label;
    }
  }

  for (final topic in input.syllabus.topics) {
    subjectTitles[topic.subjectId] = topic.subjectTitle;
  }

  TopicWeaknessReport buildTopic({
    required String key,
    required String label,
    required String subjectId,
    required String subjectTitle,
    required String chapterId,
    required List<PerformanceSample> samples,
    SyllabusTopicProgress? syllabusTopic,
  }) {
    final attempted = samples.fold<int>(0, (s, x) => s + x.attempted);
    final correct = samples.fold<int>(0, (s, x) => s + x.correct);
    final wrong = samples.fold<int>(0, (s, x) => s + x.wrong);
    final time = samples.fold<int>(0, (s, x) => s + x.timeSeconds);
    final accuracy = weaknessAccuracyPercent(
      correct: correct,
      attempted: attempted,
    );
    final band = attempted <= 0 ? WeaknessBand.insufficient : t.bandFor(accuracy);

    final recent = samples.where((s) => !s.at.isBefore(recentStart)).toList();
    final previous = samples
        .where((s) => s.at.isBefore(recentStart) && !s.at.isBefore(previousStart))
        .toList();
    final trend = weaknessTrend(
      recentAccuracy: _sampleAccuracy(recent),
      previousAccuracy: _sampleAccuracy(previous),
      recentSamples: recent.length,
      previousSamples: previous.length,
      thresholds: t,
    );

    final weakSessions = samples
        .where((s) => s.accuracyPercent < t.improvingMin)
        .length;
    final repeated = weakSessions >= t.repeatedWrongSessions && band.isWeakLike;

    final lastStudied = syllabusTopic?.lastStudiedAt;
    final daysSince = lastStudied == null
        ? null
        : now.difference(lastStudied).inDays;
    final stale = daysSince != null && daysSince >= t.staleRevisionDays;

    final examImportant = _examImportant(
      syllabusTopic: syllabusTopic,
      targetExam: input.targetExam,
      minutesThreshold: t.examImportantMinutes,
    );
    final incomplete = syllabusTopic != null &&
        syllabusTopic.status != SyllabusTopicStatus.completed;
    final priority = weaknessPriority(
      band: band,
      repeatedMistakes: repeated,
      trend: trend,
      incompleteSyllabus: incomplete,
      staleRevision: stale,
      examImportant: examImportant,
    );
    final sources = samples.map((s) => s.source).toSet().toList();
    return TopicWeaknessReport(
      label: label,
      subjectId: subjectId,
      chapterId: chapterId,
      subjectTitle: subjectTitle,
      band: band,
      trend: trend,
      priority: priority,
      attempted: attempted,
      correct: correct,
      wrong: wrong,
      accuracyPercent: accuracy,
      syllabusStatus: syllabusTopic?.status,
      timeSeconds: time + (syllabusTopic?.studyMinutes ?? 0) * 60,
      revisionCount: syllabusTopic?.revisionCount ?? 0,
      lastStudiedAt: lastStudied,
      repeatedMistakes: repeated,
      examImportant: examImportant,
      staleRevision: stale,
      sources: sources,
      actions: weaknessActionsFor(
        band: band,
        syllabusStatus: syllabusTopic?.status,
        topicTitle: label,
      ),
    );
  }

  final topics = <TopicWeaknessReport>[];
  final seenChapters = <String>{};

  for (final topic in input.syllabus.topics) {
    final samples = byChapter[topic.chapterId] ?? const <PerformanceSample>[];
    if (samples.isEmpty) continue;
    seenChapters.add(topic.chapterId);
    topics.add(
      buildTopic(
        key: topic.chapterId,
        label: topic.chapterTitle,
        subjectId: topic.subjectId,
        subjectTitle: topic.subjectTitle,
        chapterId: topic.chapterId,
        samples: samples,
        syllabusTopic: topic,
      ),
    );
  }

  for (final entry in byChapter.entries) {
    if (seenChapters.contains(entry.key)) continue;
    final samples = entry.value;
    final first = samples.first;
    topics.add(
      buildTopic(
        key: entry.key,
        label: first.label,
        subjectId: first.subjectId,
        subjectTitle: first.subjectTitle,
        chapterId: entry.key,
        samples: samples,
      ),
    );
  }

  topics.sort((a, b) => b.priority.compareTo(a.priority));

  final subjects = <SubjectWeaknessReport>[];
  final subjectKeys = {
    ...bySubject.keys,
    ...input.syllabus.subjects.map((s) => s.subject.id),
  };
  for (final key in subjectKeys) {
    final samples = bySubject[key] ?? const <PerformanceSample>[];
    final topicRows = topics.where((t) {
      if (t.subjectId.isNotEmpty && t.subjectId == key) return true;
      return false;
    }).toList();
    final attempted = samples.fold<int>(0, (s, x) => s + x.attempted);
    if (attempted <= 0 && topicRows.every((t) => !t.hasPerformance)) continue;
    final correct = samples.fold<int>(0, (s, x) => s + x.correct);
    final wrong = samples.fold<int>(0, (s, x) => s + x.wrong);
    final time = samples.fold<int>(0, (s, x) => s + x.timeSeconds);
    final accuracy = weaknessAccuracyPercent(
      correct: correct,
      attempted: attempted,
    );
    final band =
        attempted <= 0 ? WeaknessBand.insufficient : t.bandFor(accuracy);
    final recent = samples.where((s) => !s.at.isBefore(recentStart)).toList();
    final previous = samples
        .where((s) => s.at.isBefore(recentStart) && !s.at.isBefore(previousStart))
        .toList();
    final title = subjectTitles[key]?.isNotEmpty == true
        ? subjectTitles[key]!
        : (topicRows.isNotEmpty ? topicRows.first.subjectTitle : key);
    subjects.add(
      SubjectWeaknessReport(
        subjectId: key.startsWith('title:') ? '' : key,
        subjectTitle: title,
        band: band,
        trend: weaknessTrend(
          recentAccuracy: _sampleAccuracy(recent),
          previousAccuracy: _sampleAccuracy(previous),
          recentSamples: recent.length,
          previousSamples: previous.length,
          thresholds: t,
        ),
        attempted: attempted,
        correct: correct,
        wrong: wrong,
        accuracyPercent: accuracy,
        timeSeconds: time,
        topics: topicRows,
      ),
    );
  }
  subjects.sort((a, b) => a.accuracyPercent.compareTo(b.accuracyPercent));

  final allSamples = input.samples.where((s) => s.attempted > 0).toList();
  final overallAttempted = allSamples.fold<int>(0, (s, x) => s + x.attempted);
  final overallCorrect = allSamples.fold<int>(0, (s, x) => s + x.correct);
  final overallWrong = allSamples.fold<int>(0, (s, x) => s + x.wrong);
  final overallTime = allSamples.fold<int>(0, (s, x) => s + x.timeSeconds);
  final recentAll = allSamples.where((s) => !s.at.isBefore(recentStart)).toList();
  final previousAll = allSamples
      .where((s) => s.at.isBefore(recentStart) && !s.at.isBefore(previousStart))
      .toList();
  final testLike = allSamples.where((s) => s.source == 'test').toList();
  final attemptsThisWeek =
      testLike.where((s) => !s.at.isBefore(weekStart)).length;

  return WeaknessAnalysisResult(
    topics: topics,
    subjects: subjects,
    overallAttempted: overallAttempted,
    overallCorrect: overallCorrect,
    overallWrong: overallWrong,
    overallAccuracy: weaknessAccuracyPercent(
      correct: overallCorrect,
      attempted: overallAttempted,
    ),
    overallTrend: weaknessTrend(
      recentAccuracy: _sampleAccuracy(recentAll),
      previousAccuracy: _sampleAccuracy(previousAll),
      recentSamples: recentAll.length,
      previousSamples: previousAll.length,
      thresholds: t,
    ),
    timeSpentSeconds: overallTime,
    attemptsThisWeek: attemptsThisWeek,
    thresholds: t,
  );
}

double? _sampleAccuracy(List<PerformanceSample> samples) {
  if (samples.isEmpty) return null;
  final attempted = samples.fold<int>(0, (s, x) => s + x.attempted);
  final correct = samples.fold<int>(0, (s, x) => s + x.correct);
  if (attempted <= 0) return null;
  return weaknessAccuracyPercent(correct: correct, attempted: attempted);
}

bool _examImportant({
  required SyllabusTopicProgress? syllabusTopic,
  required String targetExam,
  required int minutesThreshold,
}) {
  if (syllabusTopic == null) return false;
  final tags = syllabusTopic.chapter.tags.map((x) => x.toLowerCase()).toList();
  if (tags.any((x) =>
      x.contains('important') ||
      x.contains('high-yield') ||
      x.contains('highyield') ||
      x.contains('महत्त्व'))) {
    return true;
  }
  final exam = targetExam.trim().toLowerCase();
  if (exam.isNotEmpty &&
      tags.any((x) => x.contains(exam) || exam.contains(x))) {
    return true;
  }
  return syllabusTopic.chapter.estimatedStudyMinutes >= minutesThreshold;
}

SyllabusTopicProgress? matchSyllabusTopic({
  required String title,
  required List<SyllabusTopicProgress> topics,
}) {
  final hay = title.toLowerCase().trim();
  if (hay.isEmpty || topics.isEmpty) return null;
  for (final t in topics) {
    if (t.chapterTitle.isNotEmpty &&
        hay.contains(t.chapterTitle.toLowerCase())) {
      return t;
    }
  }
  for (final t in topics) {
    if (t.subjectTitle.isNotEmpty &&
        hay.contains(t.subjectTitle.toLowerCase())) {
      return t;
    }
  }
  return null;
}
