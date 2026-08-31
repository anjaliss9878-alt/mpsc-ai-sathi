import 'package:mpsc_combine_ai/models/daily_study_plan.dart';
import 'package:mpsc_combine_ai/services/ai_weakness_tracker.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';

class PlannerPrefs {
  const PlannerPrefs({
    required this.targetExam,
    required this.examDate,
    required this.dailyHours,
    this.assignedSubjectIds = const [],
  });

  final String targetExam;
  final String examDate;
  final double dailyHours;
  final List<String> assignedSubjectIds;
}

/// Builds an adaptive daily plan from published syllabus + weakness signals.
///
/// Deterministic (no extra Gemini call) so offline / empty-key environments
/// still produce a real plan from Firebase student data.
class DailyPlannerService {
  DailyPlannerService({
    SyllabusProgressTracker? syllabus,
    AiWeaknessTracker? weakness,
    StudentProgressRepository? progress,
    ProfileRepository? profiles,
  })  : _syllabusOverride = syllabus,
        _weaknessOverride = weakness,
        _progressOverride = progress,
        _profilesOverride = profiles;

  final SyllabusProgressTracker? _syllabusOverride;
  final AiWeaknessTracker? _weaknessOverride;
  final StudentProgressRepository? _progressOverride;
  final ProfileRepository? _profilesOverride;

  SyllabusProgressTracker get _syllabus =>
      _syllabusOverride ?? syllabusProgressTracker;
  AiWeaknessTracker get _weakness => _weaknessOverride ?? aiWeaknessTracker;
  StudentProgressRepository get _progress =>
      _progressOverride ?? studentProgressRepository;
  ProfileRepository get _profiles => _profilesOverride ?? profileRepository;

  Future<DailyStudyPlan> generate({
    required String uid,
    required PlannerPrefs prefs,
    DateTime? now,
    List<DailyStudyPlan> recentPlans = const [],
  }) async {
    final clock = now ?? DateTime.now();
    final dateKey = DailyStudyPlan.dateKeyFor(clock);
    var syllabus = await _syllabus.load(uid);
    final assigned = List<String>.from(prefs.assignedSubjectIds);
    if (assigned.isEmpty) {
      try {
        final profile = await _profiles.getProfile(uid);
        assigned.addAll(profile?.assignedSubjectIds ?? const []);
      } catch (_) {}
    }
    if (assigned.isNotEmpty) {
      syllabus = syllabus.forSubjectIds(assigned);
    }
    final weakness = await _weakness.load(uid, syllabus: syllabus, now: clock);
    var history = recentPlans;
    if (history.isEmpty) {
      history = await _progress.getRecentDailyPlans(uid, limit: 14);
    }
    return buildPlan(
      uid: uid,
      prefs: prefs,
      dateKey: dateKey,
      syllabus: syllabus,
      weakness: weakness,
      recentPlans: history,
      now: clock,
    );
  }

  DailyStudyPlan buildPlan({
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
    final recentIds = _recentChapterIds(recentPlans, dateKey);
    final skipped = _openSkipped(recentPlans, dateKey);
    final notes = <String>[];

    final studyPick = _pickStudyTopic(syllabus, skipped, recentIds);
    final weakPick = _pickWeakTopic(weakness);
    final strongPick = _pickStrongTopic(weakness, weakPick);

    final hasPersonalSignals = syllabus.hasSyllabus ||
        weakness.hasPerformance ||
        skipped.isNotEmpty;
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

    final weights = _weights(
      daysToExam: _daysToExam(prefs.examDate, clock),
      weakness: weakness,
      pendingCount: syllabus.pending.length,
    );

    var studyMin = _chunk(totalMinutes * weights.study);
    var revisionMin = _chunk(totalMinutes * weights.revision);
    var mcqMin = _chunk(totalMinutes * weights.mcq);
    var pyqMin = _chunk(totalMinutes * weights.pyq);
    var testMin = _chunk(totalMinutes * weights.test);

    if (weakPick != null && weakPick.isWeak) {
      notes.add(
        'Weak: ${weakPick.subjectTitle.isEmpty ? weakPick.label : '${weakPick.subjectTitle} → ${weakPick.label}'} '
        '(${weakPick.scorePercent.round()}%) — revision, targeted MCQs, and related PYQs are prioritized.',
      );
      final steal = _chunk(studyMin * 0.25);
      studyMin = (studyMin - steal).clamp(15, totalMinutes);
      mcqMin += steal;
    }
    if (strongPick != null && strongPick.isStrong) {
      notes.add(
        'Strong: ${strongPick.label} — lighter revision as accuracy has improved.',
      );
      final cut = _chunk(revisionMin * 0.2);
      revisionMin = (revisionMin - cut).clamp(10, totalMinutes);
      studyMin += cut;
    }
    if (syllabus.pending.isNotEmpty) {
      notes.add(
        'Pending syllabus: ${syllabus.pending.length} topic(s) kept in the study block.',
      );
    }
    if (weakness.hasPoorRecentTests) {
      notes.add('Recent test scores are low — extra practice was added.');
    }
    if (weakness.needsWeeklyTest) {
      notes.add('No test this week — a short quiz/test block was added.');
    } else if (testMin > 20 && !weakness.hasPoorRecentTests) {
      final extra = testMin - 15;
      testMin = 15;
      studyMin += extra;
    }

    if (!syllabus.hasSyllabus && skipped.isEmpty && studyPick == null) {
      notes.add(
        'Published syllabus topics were not found. The plan uses your recorded weak topics until Admin Notes are published.',
      );
    }

    final tasks = <DailyPlanTask>[];
    var seq = 0;
    DailyPlanTask next({
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
    }) {
      seq++;
      return DailyPlanTask(
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
      );
    }

    final weakTopic = _topicFromSignal(weakPick, syllabus);
    final weakIsWeak = weakPick != null && weakPick.isWeak;
    final weakPriority = weakPick?.priority ?? 0;

    if (revisionMin >= 10) {
      final rev = weakIsWeak
          ? (weakTopic ?? studyPick)
          : studyPick ?? _topicFromSignal(strongPick, syllabus);
      if (rev != null || weakIsWeak) {
        tasks.add(
          next(
            type: DailyPlanTaskType.revision,
            subject: rev?.subjectTitle ?? weakPick?.subjectTitle ?? 'GS',
            topic: rev?.chapterTitle ?? weakPick?.label ?? 'Revision',
            minutes: revisionMin,
            subjectId: rev?.subjectId ?? weakPick?.subjectId ?? '',
            chapterId: rev?.chapterId ?? weakPick?.chapterId ?? '',
            revision: revisionMin,
            reason: weakIsWeak ? 'Weak topic revision' : 'Regular revision',
            priority: weakIsWeak ? 50 + weakPriority : 10,
          ),
        );
      }
    }

    if (studyMin >= 15 && studyPick != null) {
      tasks.add(
        next(
          type: DailyPlanTaskType.study,
          subject: studyPick.subjectTitle,
          topic: studyPick.chapterTitle,
          minutes: studyMin,
          subjectId: studyPick.subjectId,
          chapterId: studyPick.chapterId,
          study: studyMin,
          reason: studyPick.status == SyllabusTopicStatus.pending
              ? 'Pending syllabus'
              : 'Continue in-progress topic',
          priority: 20,
        ),
      );
    }

    if (mcqMin >= 10) {
      final mcqTopic = weakIsWeak
          ? (weakTopic ?? studyPick)
          : studyPick ?? weakTopic;
      final label = mcqTopic?.chapterTitle ?? weakPick?.label ?? 'MPSC MCQ';
      final subject = mcqTopic?.subjectTitle ?? weakPick?.subjectTitle ?? 'GS';
      tasks.add(
        next(
          type: DailyPlanTaskType.practiceMcq,
          subject: subject,
          topic: label,
          minutes: mcqMin,
          subjectId: mcqTopic?.subjectId ?? weakPick?.subjectId ?? '',
          chapterId: mcqTopic?.chapterId ?? weakPick?.chapterId ?? '',
          practice: mcqMin,
          reason: weakIsWeak ? 'Targeted MCQs for a weak topic' : 'Daily practice',
          priority: weakIsWeak ? 45 + weakPriority : 15,
        ),
      );
    }

    if (pyqMin >= 10) {
      final pyqTopic = weakIsWeak
          ? (weakTopic ?? studyPick)
          : studyPick ?? weakTopic;
      tasks.add(
        next(
          type: DailyPlanTaskType.pyq,
          subject: pyqTopic?.subjectTitle ?? prefs.targetExam,
          topic: pyqTopic?.chapterTitle ?? 'Previous year questions',
          minutes: pyqMin,
          subjectId: pyqTopic?.subjectId ?? weakPick?.subjectId ?? '',
          chapterId: pyqTopic?.chapterId ?? weakPick?.chapterId ?? '',
          practice: pyqMin,
          reason: weakIsWeak ? 'Related PYQs for a weak topic' : 'PYQ practice',
          priority: weakIsWeak ? 40 + weakPriority : 12,
        ),
      );
    }

    if (testMin >= 10) {
      final testTopic = studyPick ?? weakTopic;
      tasks.add(
        next(
          type: DailyPlanTaskType.testQuiz,
          subject: testTopic?.subjectTitle ?? prefs.targetExam,
          topic: testTopic?.chapterTitle ?? 'Mock / topic quiz',
          minutes: testMin,
          subjectId: testTopic?.subjectId ?? '',
          chapterId: testTopic?.chapterId ?? '',
          practice: testMin,
          reason: weakness.needsWeeklyTest
              ? 'Weekly test'
              : 'Quiz practice',
          priority: 8,
        ),
      );
    }

    if (tasks.isEmpty && studyPick != null) {
      tasks.add(
        next(
          type: DailyPlanTaskType.study,
          subject: studyPick.subjectTitle,
          topic: studyPick.chapterTitle,
          minutes: totalMinutes,
          subjectId: studyPick.subjectId,
          chapterId: studyPick.chapterId,
          study: totalMinutes,
          reason: 'Pending syllabus',
        ),
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
    );
  }

  _AllocWeights _weights({
    required int? daysToExam,
    required WeaknessSnapshot weakness,
    required int pendingCount,
  }) {
    if (daysToExam != null && daysToExam <= 21) {
      return const _AllocWeights(
        study: 0.22,
        revision: 0.30,
        mcq: 0.24,
        pyq: 0.14,
        test: 0.10,
      );
    }
    if (pendingCount == 0) {
      return const _AllocWeights(
        study: 0.15,
        revision: 0.30,
        mcq: 0.25,
        pyq: 0.18,
        test: 0.12,
      );
    }
    if (weakness.hasPoorRecentTests) {
      return const _AllocWeights(
        study: 0.30,
        revision: 0.22,
        mcq: 0.28,
        pyq: 0.12,
        test: 0.08,
      );
    }
    return const _AllocWeights(
      study: 0.40,
      revision: 0.18,
      mcq: 0.22,
      pyq: 0.12,
      test: 0.08,
    );
  }

  SyllabusTopicProgress? _pickStudyTopic(
    SyllabusProgressSnapshot syllabus,
    List<DailyPlanTask> skipped,
    Set<String> recentIds,
  ) {
    for (final task in skipped) {
      final match = syllabus.topics.where((t) => t.chapterId == task.chapterId);
      if (match.isNotEmpty) return match.first;
    }
    SyllabusTopicProgress? firstPendingNotRecent;
    for (final t in syllabus.pending) {
      if (!recentIds.contains(t.chapterId)) return t;
      firstPendingNotRecent ??= t;
    }
    if (firstPendingNotRecent != null) return firstPendingNotRecent;
    if (syllabus.inProgress.isNotEmpty) return syllabus.inProgress.first;
    if (syllabus.topics.isNotEmpty) return syllabus.topics.first;
    return null;
  }

  WeakTopicSignal? _pickWeakTopic(WeaknessSnapshot weakness) {
    if (weakness.weakTopics.isEmpty) return null;
    return weakness.weakTopics.first;
  }

  WeakTopicSignal? _pickStrongTopic(
    WeaknessSnapshot weakness,
    WeakTopicSignal? weak,
  ) {
    for (final s in weakness.strongTopics) {
      if (weak == null || s.chapterId != weak.chapterId) return s;
    }
    return null;
  }

  SyllabusTopicProgress? _topicFromSignal(
    WeakTopicSignal? signal,
    SyllabusProgressSnapshot syllabus,
  ) {
    if (signal == null) return null;
    if (signal.chapterId.isNotEmpty) {
      for (final t in syllabus.topics) {
        if (t.chapterId == signal.chapterId) return t;
      }
    }
    if (signal.subjectId.isNotEmpty) {
      for (final t in syllabus.topics) {
        if (t.subjectId == signal.subjectId &&
            t.status != SyllabusTopicStatus.completed) {
          return t;
        }
      }
    }
    return null;
  }

  Set<String> _recentChapterIds(List<DailyStudyPlan> plans, String todayKey) {
    final ids = <String>{};
    for (final plan in plans) {
      if (plan.dateKey == todayKey) continue;
      for (final task in plan.tasks) {
        if (task.type == DailyPlanTaskType.study && task.chapterId.isNotEmpty) {
          ids.add(task.chapterId);
        }
      }
    }
    return ids;
  }

  List<DailyPlanTask> _openSkipped(List<DailyStudyPlan> plans, String todayKey) {
    final out = <DailyPlanTask>[];
    for (final plan in plans) {
      if (plan.dateKey == todayKey) continue;
      for (final task in plan.tasks) {
        if (task.status == DailyPlanTaskStatus.skipped ||
            (task.status == DailyPlanTaskStatus.rescheduled &&
                task.rescheduledToDateKey == todayKey)) {
          out.add(task);
        }
      }
    }
    return out;
  }

  int? _daysToExam(String examDate, DateTime now) {
    if (examDate.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(examDate.trim());
    if (parsed == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    final exam = DateTime(parsed.year, parsed.month, parsed.day);
    return exam.difference(today).inDays;
  }

  int _chunk(num minutes) {
    final rounded = ((minutes / 5).round() * 5);
    return rounded.clamp(0, 12 * 60);
  }
}

class _AllocWeights {
  const _AllocWeights({
    required this.study,
    required this.revision,
    required this.mcq,
    required this.pyq,
    required this.test,
  });

  final double study;
  final double revision;
  final double mcq;
  final double pyq;
  final double test;
}

final DailyPlannerService dailyPlannerService = DailyPlannerService();
