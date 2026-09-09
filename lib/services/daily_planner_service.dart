import 'package:mpsc_combine_ai/data/student_onboarding.dart';
import 'package:mpsc_combine_ai/models/daily_study_plan.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/services/adaptive_study_plan.dart';
import 'package:mpsc_combine_ai/services/ai_weakness_tracker.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';

export 'package:mpsc_combine_ai/services/adaptive_study_plan.dart'
    show PlannerPrefs, AdaptiveStudyPlanBuilder, adaptiveStudyPlanBuilder;

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
    bool save = false,
    bool preserveCompleted = true,
  }) async {
    final clock = now ?? DateTime.now();
    final dateKey = DailyStudyPlan.dateKeyFor(clock);
    var syllabus = await _syllabus.load(uid);
    StudentProfile? profile;
    try {
      profile = await _profiles.getProfile(uid);
    } catch (_) {}
    final assigned = List<String>.from(prefs.assignedSubjectIds);
    if (assigned.isEmpty) {
      assigned.addAll(profile?.assignedSubjectIds ?? const []);
    }
    syllabus = resolveSyllabus(
      syllabus,
      prefs: PlannerPrefs(
        targetExam: prefs.targetExam,
        examDate: prefs.examDate,
        dailyHours: prefs.dailyHours,
        assignedSubjectIds: assigned,
        preparationDurationDays: prefs.preparationDurationDays,
        preparationStage: prefs.preparationStage,
        preferredLanguage: prefs.preferredLanguage,
      ),
    );
    var resolvedPrefs = prefs;
    if (prefs.preparationDurationDays <= 0 &&
        (profile?.preparationDurationDays ?? 0) > 0) {
      resolvedPrefs = PlannerPrefs(
        targetExam: prefs.targetExam,
        examDate: prefs.examDate,
        dailyHours: prefs.dailyHours,
        assignedSubjectIds: prefs.assignedSubjectIds,
        preparationDurationDays: profile!.preparationDurationDays,
        preparationStage: prefs.preparationStage.isEmpty
            ? (profile.preparationStage)
            : prefs.preparationStage,
        preferredLanguage: prefs.preferredLanguage.isEmpty
            ? profile.preferredLanguage
            : prefs.preferredLanguage,
      );
    }
    final weakness = await _weakness.load(uid, syllabus: syllabus, now: clock);
    var history = recentPlans;
    if (history.isEmpty) {
      history = await _progress.getRecentDailyPlans(uid, limit: 21);
    }
    var plan = buildPlan(
      uid: uid,
      prefs: resolvedPrefs,
      dateKey: dateKey,
      syllabus: syllabus,
      weakness: weakness,
      recentPlans: history,
      now: clock,
    );
    if (preserveCompleted) {
      try {
        final existing = await _progress.getDailyPlan(uid, dateKey: dateKey);
        if (existing != null && existing.completedTasks.isNotEmpty) {
          plan = mergeKeepingCompleted(existing, plan);
        }
      } catch (_) {}
    }
    if (save && plan.tasks.isNotEmpty) {
      await _progress.saveDailyPlan(uid, plan);
    }
    return plan;
  }

  DailyStudyPlan mergeKeepingCompleted(
    DailyStudyPlan existing,
    DailyStudyPlan next,
  ) {
    final done = existing.completedTasks;
    final doneKeys = {
      for (final t in done) '${t.type.name}|${t.chapterId}|${t.topic}',
    };
    final open = [
      for (final t in next.tasks)
        if (!doneKeys.contains('${t.type.name}|${t.chapterId}|${t.topic}')) t,
    ];
    return next.copyWith(
      tasks: [...done, ...open],
      adaptationNotes: [
        'Updated from latest weakness, MCQ, and PYQ results.',
        ...next.adaptationNotes,
      ],
    );
  }

  /// Same syllabus source as [generate]: assigned-subject filter, then the
  /// existing Group B in-memory curriculum when Firestore chapters are empty.
  SyllabusProgressSnapshot resolveSyllabus(
    SyllabusProgressSnapshot loaded, {
    required PlannerPrefs prefs,
  }) {
    var syllabus = loaded;
    if (prefs.assignedSubjectIds.isNotEmpty) {
      syllabus = syllabus.forSubjectIds(prefs.assignedSubjectIds);
    }
    if (!syllabus.hasSyllabus &&
        isGroupBCombinedTargetExam(prefs.targetExam)) {
      syllabus = groupBFallbackSyllabus();
    }
    return syllabus;
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
    return adaptiveStudyPlanBuilder.build(
      uid: uid,
      prefs: prefs,
      dateKey: dateKey,
      syllabus: resolveSyllabus(syllabus, prefs: prefs),
      weakness: weakness,
      recentPlans: recentPlans,
      now: now,
    );
  }

  List<DailyStudyPlan> previewHorizon({
    required String uid,
    required PlannerPrefs prefs,
    required SyllabusProgressSnapshot syllabus,
    required WeaknessSnapshot weakness,
    DateTime? now,
    int days = 7,
    List<DailyStudyPlan> recentPlans = const [],
  }) {
    return adaptiveStudyPlanBuilder.previewHorizon(
      uid: uid,
      prefs: prefs,
      syllabus: resolveSyllabus(syllabus, prefs: prefs),
      weakness: weakness,
      start: now ?? DateTime.now(),
      days: days,
      recentPlans: recentPlans,
    );
  }
}

final DailyPlannerService dailyPlannerService = DailyPlannerService();
