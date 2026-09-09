import 'package:mpsc_combine_ai/data/student_onboarding.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/daily_study_plan.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/ai_weakness_tracker.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';

class PlannerPrefs {
  const PlannerPrefs({
    required this.targetExam,
    required this.examDate,
    required this.dailyHours,
    this.assignedSubjectIds = const [],
    this.preparationDurationDays = 0,
    this.preparationStage = '',
    this.preferredLanguage = '',
  });

  final String targetExam;
  final String examDate;
  final double dailyHours;
  final List<String> assignedSubjectIds;
  final int preparationDurationDays;
  final String preparationStage;
  final String preferredLanguage;
}

/// Adaptive MPSC day plan: full syllabus, diagnostic priority, carry-forward,
/// spaced revision, and MCQ/PYQ mix. Deterministic — no extra AI call.
class AdaptiveStudyPlanBuilder {
  const AdaptiveStudyPlanBuilder();

  DailyStudyPlan build({
    required String uid,
    required PlannerPrefs prefs,
    required String dateKey,
    required SyllabusProgressSnapshot syllabus,
    required WeaknessSnapshot weakness,
    List<DailyStudyPlan> recentPlans = const [],
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final totalMinutes = (prefs.dailyHours * 60).round().clamp(30, 12 * 60);
    final notes = <String>[];
    var workingSyllabus = _withWeaknessTopics(syllabus, weakness);

    final hasPersonalSignals = workingSyllabus.hasSyllabus ||
        weakness.hasPerformance ||
        weakness.weakTopics.isNotEmpty ||
        weakness.strongTopics.isNotEmpty ||
        _openFromHistory(recentPlans, dateKey).isNotEmpty;
    if (!hasPersonalSignals) {
      return DailyStudyPlan(
        dateKey: dateKey,
        uid: uid,
        targetExam: prefs.targetExam,
        examDate: prefs.examDate,
        dailyHours: prefs.dailyHours,
        tasks: const [],
        adaptationNotes: const [
          'Not enough student data to personalize a plan. Set your target exam, complete syllabus topics, or attempt a test, quiz, or MCQ set first.',
        ],
        generatedAt: clock,
      );
    }

    final horizon = resolvedPreparationDays(
      examDate: prefs.examDate,
      preparationDurationDays: prefs.preparationDurationDays,
      now: clock,
    );
    final remainingTopics = workingSyllabus.incomplete.length;
    final completedTopics = workingSyllabus.completedTopics;
    final totalTopics = workingSyllabus.totalTopics;
    final percent = workingSyllabus.overallPercent;
    final track = _trackStatus(
      remainingTopics: remainingTopics,
      daysRemaining: horizon,
      dailyHours: prefs.dailyHours,
    );
    final dayNumber = _dayNumber(recentPlans, dateKey);

    final areaScores = _areaScores(workingSyllabus, weakness);
    final ranked = _rankTopics(workingSyllabus, weakness, areaScores, recentPlans, dateKey);

    final tasks = <DailyPlanTask>[];
    var seq = 0;
    var used = 0;

    DailyPlanTask add({
      required DailyPlanTaskType type,
      required String subject,
      required String topic,
      required int minutes,
      String subjectId = '',
      String chapterId = '',
      int study = 0,
      int revision = 0,
      int practice = 0,
      String reason = '',
      int priority = 0,
      DailyPlanTaskStatus status = DailyPlanTaskStatus.pending,
    }) {
      seq++;
      final task = DailyPlanTask(
        id: '${dateKey}_$seq',
        type: type,
        subject: subject,
        topic: topic,
        durationMinutes: minutes,
        subjectId: subjectId,
        chapterId: chapterId,
        studyMinutes: study,
        revisionMinutes: revision,
        practiceMinutes: practice,
        reason: reason,
        priority: priority,
        status: status,
      );
      tasks.add(task);
      used += minutes;
      return task;
    }

    final carried = _openFromHistory(recentPlans, dateKey);
    var carriedCount = 0;
    for (final old in carried) {
      if (used + old.durationMinutes > totalMinutes + 20) break;
      add(
        type: old.type,
        subject: old.subject,
        topic: old.topic,
        minutes: old.durationMinutes,
        subjectId: old.subjectId,
        chapterId: old.chapterId,
        study: old.studyMinutes,
        revision: old.revisionMinutes,
        practice: old.practiceMinutes,
        reason: 'Carried forward from ${old.id.split('_').first}',
        priority: old.priority + 15,
        status: DailyPlanTaskStatus.carriedForward,
      );
      carriedCount++;
    }

    final weakSignals = weakness.weakTopics;
    final strongSignals = weakness.strongTopics;
    final weakPick = weakSignals.isEmpty ? null : weakSignals.first;
    WeakTopicSignal? strongPick;
    for (final s in strongSignals) {
      if (weakPick == null || s.chapterId != weakPick.chapterId) {
        strongPick = s;
        break;
      }
    }

    for (final w in weakSignals.take(3)) {
      notes.add(
        'Weak: ${w.subjectTitle.isEmpty ? w.label : '${w.subjectTitle} → ${w.label}'} '
        '(${w.scorePercent.round()}%) — extra study, MCQs, and PYQs.',
      );
    }
    for (final s in strongSignals.take(2)) {
      notes.add(
        'Strong: ${s.subjectTitle.isEmpty ? s.label : s.subjectTitle} '
        '(${s.scorePercent.round()}%) — maintenance + spaced revision.',
      );
    }
    if (workingSyllabus.hasSyllabus) {
      notes.add(
        'Syllabus Progress: ${percent.round()}% · '
        'Topics Completed: $completedTopics / $totalTopics · '
        'Days Remaining: $horizon · ${track == 'behind' ? 'Behind Schedule' : track == 'at_risk' ? 'At Risk' : 'On Track'}.',
      );
    }
    if (!syllabus.hasSyllabus) {
      notes.add(
        'Published syllabus topics were not found. The plan uses your recorded weak topics until Admin Notes are published.',
      );
    }

    final scheduledIds = <String>{
      for (final t in tasks)
        if (t.chapterId.isNotEmpty) t.chapterId,
    };

    final studyBudget = (totalMinutes * (weakPick != null && weakPick.isWeak ? 0.48 : 0.42))
        .round();
    var studyUsed = 0;
    final todayStudy = <SyllabusTopicProgress>[];

    void addStudy(SyllabusTopicProgress topic) {
      if (scheduledIds.contains(topic.chapterId)) return;
      if (studyUsed >= studyBudget || used >= totalMinutes - 35) return;
      final areaScore = areaScores[topic.plannerAreaId];
      final minutes = _studyMinutesFor(areaScore, prefs.dailyHours);
      if (used + minutes > totalMinutes - 20) return;
      add(
        type: DailyPlanTaskType.study,
        subject: topic.plannerSubjectTitle,
        topic: topic.chapterTitle,
        minutes: minutes,
        subjectId: topic.subjectId,
        chapterId: topic.chapterId,
        study: minutes,
        reason: topic.status == SyllabusTopicStatus.pending
            ? 'Pending syllabus'
            : 'Continue in-progress topic',
        priority: _priorityFor(areaScore),
      );
      scheduledIds.add(topic.chapterId);
      todayStudy.add(topic);
      studyUsed += minutes;
    }

    final byArea = <String, List<SyllabusTopicProgress>>{};
    for (final t in ranked) {
      if (!t.isIncomplete) continue;
      byArea.putIfAbsent(t.plannerAreaId, () => []).add(t);
    }
    final areaKeys = byArea.keys.toList()
      ..sort((a, b) {
        final sa = areaScores[a] ?? 55;
        final sb = areaScores[b] ?? 55;
        return sa.compareTo(sb);
      });

    SyllabusTopicProgress? takeArea(String area) {
      final list = byArea[area];
      if (list == null) return null;
      for (final t in list) {
        if (!scheduledIds.contains(t.chapterId)) return t;
      }
      return null;
    }

    if (areaKeys.isNotEmpty) {
      final first = takeArea(areaKeys.first);
      if (first != null) addStudy(first);
    }
    final langId = dayNumber.isOdd ? 'marathi' : 'english';
    final language = takeArea(langId) ??
        takeArea(langId == 'marathi' ? 'english' : 'marathi');
    if (language != null) addStudy(language);
    final ca = takeArea('current_affairs');
    if (ca != null) addStudy(ca);
    if (areaKeys.length > 1) {
      final second = takeArea(areaKeys[1]);
      if (second != null) addStudy(second);
    }
    if (areaKeys.isNotEmpty) {
      final pct = areaScores[areaKeys.first];
      if (pct != null && pct < 50) {
        final extra = takeArea(areaKeys.first);
        if (extra != null) addStudy(extra);
      }
    }
    for (var i = areaKeys.length - 1; i >= 0; i--) {
      if (todayStudy.length >= 5) break;
      final t = takeArea(areaKeys[i]);
      if (t != null) {
        addStudy(t);
        break;
      }
    }

    if (todayStudy.isEmpty) {
      final fallback = ranked.isNotEmpty
          ? ranked.first
          : (workingSyllabus.topics.isEmpty ? null : workingSyllabus.topics.first);
      if (fallback != null && used + 30 <= totalMinutes) {
        add(
          type: DailyPlanTaskType.study,
          subject: fallback.plannerSubjectTitle,
          topic: fallback.chapterTitle,
          minutes: ((totalMinutes * 0.35).round()).clamp(15, 90),
          subjectId: fallback.subjectId,
          chapterId: fallback.chapterId,
          study: ((totalMinutes * 0.35).round()).clamp(15, 90),
          reason: 'Pending syllabus',
          priority: 20,
        );
        todayStudy.add(fallback);
      }
    }

    SyllabusTopicProgress? topicFor(WeakTopicSignal? signal) {
      if (signal == null) return null;
      for (final t in workingSyllabus.topics) {
        if (signal.chapterId.isNotEmpty && t.chapterId == signal.chapterId) {
          return t;
        }
      }
      for (final t in workingSyllabus.topics) {
        if (signal.subjectId.isNotEmpty &&
            t.subjectId == signal.subjectId &&
            t.isIncomplete) {
          return t;
        }
      }
      return _topicFromWeakness(signal);
    }

    final weakTopic = topicFor(weakPick) ??
        (todayStudy.isEmpty ? null : todayStudy.first);
    final weakIsWeak = weakPick != null && weakPick.isWeak;
    final weakPriority = weakPick?.priority ?? 0;

    var mcqMin = _chunk(totalMinutes * (weakIsWeak ? 0.22 : 0.14));
    var pyqMin = _chunk(totalMinutes * (weakIsWeak ? 0.12 : 0.08));
    var revisionMin = _chunk(totalMinutes * (weakIsWeak ? 0.14 : 0.18));
    var testMin = weakness.needsWeeklyTest
        ? _chunk(totalMinutes * 0.08).clamp(10, 25)
        : (weakness.hasPoorRecentTests ? 15 : 15);

    if (strongPick != null && strongPick.isStrong && !weakIsWeak) {
      notes.add(
        'Strong: ${strongPick.label} — lighter revision as accuracy has improved.',
      );
      final cut = _chunk(revisionMin * 0.2);
      revisionMin = (revisionMin - cut).clamp(10, totalMinutes);
    }
    if (weakness.hasPoorRecentTests) {
      notes.add('Recent test scores are low — extra practice was added.');
      mcqMin += 10;
    }
    if (weakness.needsWeeklyTest) {
      notes.add('No test this week — a short quiz/test block was added.');
    } else {
      testMin = testMin.clamp(0, 15);
    }

    if (mcqMin >= 10 && used + mcqMin <= totalMinutes + 15) {
      final mcqTopic = weakIsWeak ? (weakTopic ?? (todayStudy.isEmpty ? null : todayStudy.first)) : (todayStudy.isEmpty ? weakTopic : todayStudy.first);
      add(
        type: DailyPlanTaskType.practiceMcq,
        subject: mcqTopic?.plannerSubjectTitle ?? weakPick?.subjectTitle ?? 'GS',
        topic: mcqTopic?.chapterTitle ?? weakPick?.label ?? 'MPSC MCQ',
        minutes: mcqMin,
        subjectId: mcqTopic?.subjectId ?? weakPick?.subjectId ?? '',
        chapterId: mcqTopic?.chapterId ?? weakPick?.chapterId ?? '',
        practice: mcqMin,
        reason: weakIsWeak ? 'Targeted MCQs for a weak topic' : 'Daily practice',
        priority: weakIsWeak ? 45 + weakPriority : 15,
      );
    }

    if (pyqMin >= 10 && used + pyqMin <= totalMinutes + 15) {
      final pyqTopic = weakIsWeak ? (weakTopic ?? (todayStudy.isEmpty ? null : todayStudy.first)) : (todayStudy.isEmpty ? weakTopic : todayStudy.first);
      add(
        type: DailyPlanTaskType.pyq,
        subject: pyqTopic?.plannerSubjectTitle ?? prefs.targetExam,
        topic: pyqTopic?.chapterTitle ?? 'Previous year questions',
        minutes: pyqMin,
        subjectId: pyqTopic?.subjectId ?? weakPick?.subjectId ?? '',
        chapterId: pyqTopic?.chapterId ?? weakPick?.chapterId ?? '',
        practice: pyqMin,
        reason: weakIsWeak ? 'Related PYQs for a weak topic' : 'PYQ practice',
        priority: weakIsWeak ? 40 + weakPriority : 12,
      );
    }

    final dueRevision = _spacedDue(workingSyllabus, clock, scheduledIds);
    if (revisionMin >= 10 && used + revisionMin <= totalMinutes + 10) {
      final rev = weakIsWeak
          ? (weakTopic ?? (todayStudy.isEmpty ? null : todayStudy.first))
          : (dueRevision ?? (todayStudy.isEmpty ? null : todayStudy.first) ?? topicFor(strongPick));
      if (rev != null || weakIsWeak) {
        add(
          type: DailyPlanTaskType.revision,
          subject: rev?.plannerSubjectTitle ?? weakPick?.subjectTitle ?? 'GS',
          topic: rev?.chapterTitle ?? weakPick?.label ?? 'Revision',
          minutes: revisionMin,
          subjectId: rev?.subjectId ?? weakPick?.subjectId ?? '',
          chapterId: rev?.chapterId ?? weakPick?.chapterId ?? '',
          revision: revisionMin,
          reason: weakIsWeak
              ? 'Weak topic revision'
              : (dueRevision != null ? 'Spaced revision' : 'Today\'s topics'),
          priority: weakIsWeak ? 50 + weakPriority : 10,
        );
      }
    }

    if (testMin >= 10 &&
        (weakness.needsWeeklyTest || weakness.hasPoorRecentTests) &&
        used + testMin <= totalMinutes + 10) {
      final testTopic = todayStudy.isEmpty ? weakTopic : todayStudy.first;
      add(
        type: DailyPlanTaskType.testQuiz,
        subject: testTopic?.plannerSubjectTitle ?? prefs.targetExam,
        topic: testTopic?.chapterTitle ?? 'Mock / topic quiz',
        minutes: testMin,
        subjectId: testTopic?.subjectId ?? '',
        chapterId: testTopic?.chapterId ?? '',
        practice: testMin,
        reason: weakness.needsWeeklyTest ? 'Weekly test' : 'Quiz practice',
        priority: 8,
      );
    } else if (testMin >= 10 && used + 15 <= totalMinutes && !weakness.needsWeeklyTest) {
      final testTopic = todayStudy.isEmpty ? weakTopic : todayStudy.first;
      add(
        type: DailyPlanTaskType.testQuiz,
        subject: testTopic?.plannerSubjectTitle ?? prefs.targetExam,
        topic: testTopic?.chapterTitle ?? 'Mock / topic quiz',
        minutes: 15,
        subjectId: testTopic?.subjectId ?? '',
        chapterId: testTopic?.chapterId ?? '',
        practice: 15,
        reason: 'Quiz practice',
        priority: 8,
      );
    }

    if (tasks.isEmpty && workingSyllabus.topics.isNotEmpty) {
      final t = workingSyllabus.pending.isNotEmpty
          ? workingSyllabus.pending.first
          : workingSyllabus.topics.first;
      add(
        type: DailyPlanTaskType.study,
        subject: t.plannerSubjectTitle,
        topic: t.chapterTitle,
        minutes: totalMinutes,
        subjectId: t.subjectId,
        chapterId: t.chapterId,
        study: totalMinutes,
        reason: 'Pending syllabus',
      );
    }

    return DailyStudyPlan(
      dateKey: dateKey,
      uid: uid,
      targetExam: prefs.targetExam,
      examDate: prefs.examDate,
      dailyHours: prefs.dailyHours,
      tasks: tasks,
      adaptationNotes: notes,
      generatedAt: clock,
      dayNumber: dayNumber,
      horizonDays: horizon,
      syllabusPercent: percent,
      topicsCompleted: completedTopics,
      topicsTotal: totalTopics,
      daysRemaining: horizon,
      trackStatus: track,
      carriedForwardCount: carriedCount,
    );
  }

  List<DailyStudyPlan> previewHorizon({
    required String uid,
    required PlannerPrefs prefs,
    required SyllabusProgressSnapshot syllabus,
    required WeaknessSnapshot weakness,
    required DateTime start,
    int days = 7,
    List<DailyStudyPlan> recentPlans = const [],
  }) {
    final out = <DailyStudyPlan>[];
    var history = [...recentPlans];
    var remaining = syllabus;
    for (var i = 0; i < days; i++) {
      final day = start.add(Duration(days: i));
      final key = DailyStudyPlan.dateKeyFor(day);
      final plan = build(
        uid: uid,
        prefs: prefs,
        dateKey: key,
        syllabus: remaining,
        weakness: weakness,
        recentPlans: history,
        now: day,
      );
      out.add(plan);
      history = [plan, ...history];
      remaining = _markStudied(remaining, plan);
    }
    return out;
  }

  WeeklyPlannerProgress weeklyReview({
    required List<DailyStudyPlan> plans,
    required DateTime now,
    SyllabusProgressSnapshot? syllabus,
    WeaknessSnapshot? weakness,
  }) {
    final keys = <String>{
      for (var i = 0; i < 7; i++)
        DailyStudyPlan.dateKeyFor(now.subtract(Duration(days: i))),
    };
    var completed = 0;
    var total = 0;
    var days = 0;
    var mcq = 0;
    var pyq = 0;
    var missed = 0;
    for (final plan in plans) {
      if (!keys.contains(plan.dateKey)) continue;
      days++;
      total += plan.actionableCount;
      completed += plan.completedCount;
      for (final t in plan.tasks) {
        if (t.isDone && t.type == DailyPlanTaskType.practiceMcq) mcq++;
        if (t.isDone && t.type == DailyPlanTaskType.pyq) pyq++;
        if (t.status == DailyPlanTaskStatus.skipped || t.isCarriedForward) {
          missed++;
        }
      }
    }
    final weakList = weakness?.weakTopics ?? <WeakTopicSignal>[];
    final strongList = weakness?.strongTopics ?? <WeakTopicSignal>[];
    final weak = [
      for (final s in weakList)
        if (s.subjectTitle.isNotEmpty) s.subjectTitle else s.label,
    ].toSet().take(5).toList();
    final strong = [
      for (final s in strongList)
        if (s.subjectTitle.isNotEmpty) s.subjectTitle else s.label,
    ].toSet().take(5).toList();
    return WeeklyPlannerProgress(
      completedTasks: completed,
      totalTasks: total,
      daysWithPlan: days,
      mcqCompleted: mcq,
      pyqCompleted: pyq,
      missedTasks: missed,
      weakSubjects: weak,
      strongSubjects: strong,
      nextPriorities: weak,
      syllabusPercent: syllabus?.overallPercent ?? 0,
      topicsCompleted: syllabus?.completedTopics ?? 0,
    );
  }

  Map<String, double> _areaScores(
    SyllabusProgressSnapshot syllabus,
    WeaknessSnapshot weakness,
  ) {
    final sums = <String, List<double>>{};
    for (final s in weakness.signals) {
      var area = '';
      for (final t in syllabus.topics) {
        if (s.chapterId.isNotEmpty && t.chapterId == s.chapterId) {
          area = t.plannerAreaId;
          break;
        }
      }
      if (area.isEmpty) {
        area = s.subjectTitle.trim().isEmpty
            ? s.subjectId
            : s.subjectTitle.toLowerCase().replaceAll(' ', '_');
      }
      sums.putIfAbsent(area, () => []).add(s.scorePercent);
    }
    return {
      for (final e in sums.entries)
        e.key: e.value.reduce((a, b) => a + b) / e.value.length,
    };
  }

  List<SyllabusTopicProgress> _rankTopics(
    SyllabusProgressSnapshot syllabus,
    WeaknessSnapshot weakness,
    Map<String, double> areaScores,
    List<DailyStudyPlan> recentPlans,
    String dateKey,
  ) {
    final recentIds = <String>{};
    for (final plan in recentPlans) {
      if (plan.dateKey == dateKey) continue;
      for (final t in plan.tasks) {
        if (t.type == DailyPlanTaskType.study && t.chapterId.isNotEmpty) {
          recentIds.add(t.chapterId);
        }
      }
    }
    final topics = [...syllabus.topics];
    topics.sort((a, b) {
      final sa = _topicScore(a, areaScores, recentIds, weakness);
      final sb = _topicScore(b, areaScores, recentIds, weakness);
      return sb.compareTo(sa);
    });
    return topics;
  }

  int _topicScore(
    SyllabusTopicProgress topic,
    Map<String, double> areaScores,
    Set<String> recentIds,
    WeaknessSnapshot weakness,
  ) {
    var score = 40;
    final areaPct = areaScores[topic.plannerAreaId];
    if (areaPct != null) {
      if (areaPct < 50) {
        score = 100 + (50 - areaPct).round();
      } else if (areaPct < 70) {
        score = 60;
      } else {
        score = 22;
      }
    }
    if (topic.status == SyllabusTopicStatus.pending) score += 18;
    if (topic.status == SyllabusTopicStatus.inProgress) score += 10;
    if (topic.status == SyllabusTopicStatus.completed) score -= 25;
    if (recentIds.contains(topic.chapterId)) score -= 35;
    for (final s in weakness.signals) {
      if (s.chapterId == topic.chapterId && s.scorePercent < 50) {
        score += 20;
      }
    }
    return score;
  }

  int _priorityFor(double? areaPct) {
    if (areaPct == null) return 48;
    if (areaPct < 20) return 95;
    if (areaPct < 50) return 80;
    if (areaPct < 70) return 40;
    return 18;
  }

  int _studyMinutesFor(double? areaPct, double dailyHours) {
    final cap = (dailyHours * 60).round();
    int fit(int minutes) {
      if (minutes < 30) return 30;
      if (minutes > cap) return cap < 30 ? cap : cap;
      return minutes;
    }

    if (areaPct != null && areaPct < 20) return fit(60);
    if (areaPct != null && areaPct < 50) return fit(50);
    if (areaPct != null && areaPct < 70) return fit(45);
    return fit(30);
  }

  List<DailyPlanTask> _openFromHistory(
    List<DailyStudyPlan> plans,
    String todayKey,
  ) {
    final past = [
      for (final plan in plans)
        if (plan.dateKey.compareTo(todayKey) < 0) plan,
    ]..sort((a, b) => b.dateKey.compareTo(a.dateKey));
    if (past.isEmpty) return const [];
    final out = <DailyPlanTask>[];
    final seen = <String>{};
    for (final task in past.first.tasks) {
      final key = '${task.chapterId}|${task.type.name}|${task.topic}';
      if (seen.contains(key)) continue;
      final open = task.status == DailyPlanTaskStatus.pending ||
          task.status == DailyPlanTaskStatus.carriedForward ||
          task.status == DailyPlanTaskStatus.skipped ||
          (task.status == DailyPlanTaskStatus.rescheduled &&
              task.rescheduledToDateKey == todayKey);
      if (!open) continue;
      seen.add(key);
      out.add(task);
    }
    return out;
  }

  SyllabusTopicProgress? _spacedDue(
    SyllabusProgressSnapshot syllabus,
    DateTime now,
    Set<String> already,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    const offsets = [1, 3, 7, 21];
    for (final t in syllabus.completed) {
      if (already.contains(t.chapterId)) continue;
      final done = t.completedAt ?? t.lastStudiedAt;
      if (done == null) continue;
      final day = DateTime(done.year, done.month, done.day);
      final age = today.difference(day).inDays;
      if (offsets.contains(age)) return t;
    }
    return null;
  }

  String _trackStatus({
    required int remainingTopics,
    required int daysRemaining,
    required double dailyHours,
  }) {
    final capacity = (dailyHours / 1.5).clamp(1, 8);
    final needed = remainingTopics / daysRemaining.clamp(1, 10000);
    if (needed > capacity * 1.25) return 'behind';
    if (needed > capacity) return 'at_risk';
    return 'on_track';
  }

  int _dayNumber(List<DailyStudyPlan> recent, String dateKey) {
    if (recent.isEmpty) return 1;
    final keys = [dateKey, ...recent.map((p) => p.dateKey)]..sort();
    return keys.toSet().length;
  }

  SyllabusProgressSnapshot _markStudied(
    SyllabusProgressSnapshot syllabus,
    DailyStudyPlan plan,
  ) {
    final studied = {
      for (final t in plan.tasks)
        if (t.type == DailyPlanTaskType.study && t.chapterId.isNotEmpty)
          t.chapterId,
    };
    if (studied.isEmpty) return syllabus;
    return SyllabusProgressSnapshot(
      topics: [
        for (final t in syllabus.topics)
          if (studied.contains(t.chapterId) && t.isIncomplete)
            SyllabusTopicProgress(
              subject: t.subject,
              chapter: t.chapter,
              status: SyllabusTopicStatus.completed,
              classroomFraction: t.classroomFraction,
              quizAccuracy: t.quizAccuracy,
              studyMinutes: t.studyMinutes,
              revisionCount: t.revisionCount,
              completedAt: plan.generatedAt,
              lastStudiedAt: plan.generatedAt,
              statusSource: 'planner',
            )
          else
            t,
      ],
    );
  }

  int _chunk(num minutes) {
    final rounded = ((minutes / 5).round() * 5);
    return rounded.clamp(0, 12 * 60);
  }

  /// Keep recorded weak/strong chapters schedulable when they are missing
  /// from the loaded syllabus snapshot. Does not invent Group B titles.
  SyllabusProgressSnapshot _withWeaknessTopics(
    SyllabusProgressSnapshot syllabus,
    WeaknessSnapshot weakness,
  ) {
    final extra = <SyllabusTopicProgress>[];
    final seen = {for (final t in syllabus.topics) t.chapterId};
    for (final signal in weakness.signals) {
      final topic = _topicFromWeakness(signal);
      if (topic == null) continue;
      if (seen.contains(topic.chapterId)) continue;
      seen.add(topic.chapterId);
      extra.add(topic);
    }
    if (extra.isEmpty) return syllabus;
    return SyllabusProgressSnapshot(topics: [...syllabus.topics, ...extra]);
  }

  SyllabusTopicProgress? _topicFromWeakness(WeakTopicSignal signal) {
    final chapterId = signal.chapterId.trim();
    final title = signal.label.trim();
    if (chapterId.isEmpty && title.isEmpty) return null;
    final id = chapterId.isNotEmpty ? chapterId : title;
    final subjectId =
        signal.subjectId.trim().isNotEmpty ? signal.subjectId.trim() : id;
    final subjectTitle = signal.subjectTitle.trim().isNotEmpty
        ? signal.subjectTitle.trim()
        : title;
    return SyllabusTopicProgress(
      subject: SubjectItem(
        id: subjectId,
        title: subjectTitle,
        subtitle: '',
        iconName: 'menu_book',
        order: 0,
      ),
      chapter: ChapterItem(
        id: id,
        subjectId: subjectId,
        title: title.isNotEmpty ? title : id,
        order: 0,
      ),
      status: SyllabusTopicStatus.pending,
    );
  }
}

const AdaptiveStudyPlanBuilder adaptiveStudyPlanBuilder =
    AdaptiveStudyPlanBuilder();
