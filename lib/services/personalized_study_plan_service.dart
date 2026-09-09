import 'package:mpsc_combine_ai/data/student_onboarding.dart';
import 'package:mpsc_combine_ai/models/daily_study_plan.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/services/ai_weakness_tracker.dart';
import 'package:mpsc_combine_ai/services/daily_planner_service.dart';
import 'package:mpsc_combine_ai/services/diagnostic_service.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';

/// Builds the first personalized plan with the existing Daily Planner.
/// Does not create a second planner.
class PersonalizedStudyPlanService {
  PersonalizedStudyPlanService({
    DailyPlannerService? planner,
    AiWeaknessTracker? weakness,
    SyllabusProgressTracker? syllabus,
    StudentProgressRepository? progress,
  })  : _planner = planner ?? dailyPlannerService,
        _weakness = weakness ?? aiWeaknessTracker,
        _syllabus = syllabus ?? syllabusProgressTracker,
        _progress = progress ?? studentProgressRepository;

  final DailyPlannerService _planner;
  final AiWeaknessTracker _weakness;
  final SyllabusProgressTracker _syllabus;
  final StudentProgressRepository _progress;

  PlannerPrefs prefsFrom(StudentProfile profile) => PlannerPrefs(
        targetExam: profile.targetExam.isEmpty
            ? kTargetExamGroupBCombined
            : profile.targetExam,
        examDate: profile.examDate,
        dailyHours: profile.dailyStudyHours,
        assignedSubjectIds: profile.assignedSubjectIds,
        preparationDurationDays: profile.preparationDurationDays,
        preparationStage: profile.preparationStage,
        preferredLanguage: profile.preferredLanguage,
      );

  Future<DailyStudyPlan> createAndSave({
    required String uid,
    required StudentProfile profile,
    DiagnosticAttemptResult? diagnostic,
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now();
    final prefs = prefsFrom(profile);
    var syllabus = await _syllabus.load(uid);
    if (!syllabus.hasSyllabus &&
        isGroupBCombinedTargetExam(prefs.targetExam)) {
      syllabus = groupBFallbackSyllabus();
    }
    final weakness = await _weakness.load(uid, syllabus: syllabus, now: clock);
    var history = <DailyStudyPlan>[];
    try {
      history = await _progress.getRecentDailyPlans(uid, limit: 21);
    } catch (_) {}
    var plan = _planner.buildPlan(
      uid: uid,
      prefs: prefs,
      dateKey: DailyStudyPlan.dateKeyFor(clock),
      syllabus: syllabus,
      weakness: weakness,
      recentPlans: history,
      now: clock,
    );

    final horizon = _planner.previewHorizon(
      uid: uid,
      prefs: prefs,
      syllabus: syllabus,
      weakness: weakness,
      now: clock,
      days: 7,
      recentPlans: [plan, ...history],
    );

    final notes = <String>[
      'Your Personalized Study Plan is Ready',
      'Target exam: ${prefs.targetExam}. '
          '${profile.studyMode == kStudyModeFullTime ? 'Full time' : 'Part time'}, '
          '${profile.dailyStudyHours} hours/day, ${profile.preferredLanguage}.',
      'Preparation stage: ${profile.preparationStage}.',
      if (diagnostic != null) ...[
        if (diagnostic.weakAreas.isNotEmpty)
          'Weak areas get extra study, MCQs, and revision: '
              '${diagnostic.weakAreas.map((a) {
                final chapter = groupBChapterForArea(a.areaId);
                final topic = chapter?.title ?? a.title;
                return '${a.title} → $topic (${a.percent.round()}%)';
              }).join('; ')}.',
        if (diagnostic.strongAreas.isNotEmpty)
          'Strong areas get lighter new learning and more revision: '
              '${diagnostic.strongAreas.map((a) => a.title).join(', ')}.',
      ],
      ...plan.adaptationNotes,
      if (horizon.length > 1)
        'This week: ${[
          for (var i = 0; i < horizon.length && i < 7; i++)
            'Day ${i + 1} ${horizon[i].tasks.where((t) => t.type == DailyPlanTaskType.study).map((t) => t.subject).toSet().take(3).join(', ')}'
        ].join(' · ')}',
    ];
    plan = plan.copyWith(adaptationNotes: notes);
    if (plan.tasks.isNotEmpty) {
      await _progress.saveDailyPlan(uid, plan);
    }
    return plan;
  }
}

final PersonalizedStudyPlanService personalizedStudyPlanService =
    PersonalizedStudyPlanService();
