import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/data/diagnostic_questions.dart';
import 'package:mpsc_combine_ai/data/student_curriculum.dart';
import 'package:mpsc_combine_ai/data/student_onboarding.dart';
import 'package:mpsc_combine_ai/models/daily_study_plan.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_progress_repository.dart';
import 'package:mpsc_combine_ai/services/ai_weakness_tracker.dart';
import 'package:mpsc_combine_ai/services/daily_planner_service.dart';
import 'package:mpsc_combine_ai/services/diagnostic_service.dart';
import 'package:mpsc_combine_ai/services/personalized_study_plan_service.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';

class _EmptySyllabus extends SyllabusProgressTracker {
  @override
  Future<SyllabusProgressSnapshot> load(String uid) async =>
      const SyllabusProgressSnapshot(topics: []);
}

void main() {
  test('legacy profiles skip onboarding; new flags do not', () {
    final legacy = StudentProfile.fromMap({
      'name': 'Asha',
      'email': 'a@x.com',
      'mobile': '9999999999',
      'targetExam': 'PSI / STI / ASO',
    }, 'u1');
    expect(legacy.onboardingCompleted, isTrue);
    expect(legacy.diagnosticCompleted, isTrue);
    expect(legacy.needsOnboarding, isFalse);
    expect(legacy.needsDiagnostic, isFalse);

    final fresh = StudentProfile.fromMap({
      'name': 'Asha',
      'email': 'a@x.com',
      'onboardingCompleted': false,
      'diagnosticCompleted': false,
      'targetExam': kTargetExamGroupBCombined,
    }, 'u2');
    expect(fresh.needsOnboarding, isTrue);
    expect(fresh.needsDiagnostic, isFalse);

    final mid = fresh.copyWith(onboardingCompleted: true);
    expect(mid.needsDiagnostic, isTrue);
  });

  test('Group B Combined maps to existing curriculum id helpers', () {
    expect(isGroupBCombinedTargetExam(kTargetExamGroupBCombined), isTrue);
    expect(
      isGroupBCombinedTargetExam('संयुक्त पूर्व परीक्षा गट ब (Combine Group B)'),
      isTrue,
    );
    expect(isGroupBCombinedTargetExam('UPSC'), isFalse);
    expect(
      examIdFromStudentTargetExam(kTargetExamGroupBCombined),
      kGroupBCombinedExamId,
    );
    expect(
      examIdFromStudentTargetExam('संयुक्त पूर्व परीक्षा गट ब (Combine Group B)'),
      kGroupBCombinedExamId,
    );
    expect(examIdFromStudentTargetExam(''), kGroupBCombinedExamId);
    expect(examIdFromStudentTargetExam('UPSC'), kDefaultExamId);
    expect(
      resolvedContentExamId(
        examId: '',
        subjectId: kGroupBSubjectPrelimsGatId,
      ),
      kGroupBCombinedExamId,
    );
    expect(
      resolvedContentExamId(examId: '', subjectId: 'legacy_polity'),
      kDefaultExamId,
    );
    expect(dailyHoursFromBucket('2–4 hours'), 3);
    expect(dailyHoursFromBucket('8+ hours'), 8);
  });

  test('diagnostic set is 30 questions covering Group B areas, not PYQs', () {
    final questions = groupBDiagnosticQuestions();
    expect(questions, hasLength(30));
    expect(questions.map((q) => q.id).toSet(), hasLength(30));
    final areas = questions.map((q) => q.areaId).toSet();
    expect(
      areas,
      containsAll([
        'current_affairs',
        'history',
        'geography',
        'economy',
        'polity',
        'general_science',
        'intelligence_arithmetic',
      ]),
    );
    for (final q in questions) {
      expect(q.question.toLowerCase(), isNot(contains('pyq')));
      expect(q.question.toLowerCase(), isNot(contains('previous year')));
    }
  });

  test('diagnostic scoring uses existing Weakness Tracker bands', () {
    final questions = groupBDiagnosticQuestions();
    final selected = List<int?>.generate(questions.length, (i) {
      if (questions[i].areaId == 'polity') {
        return (questions[i].correctIndex + 1) % questions[i].options.length;
      }
      return questions[i].correctIndex;
    });
    final result = DiagnosticService().score(
      attemptId: 'a1',
      targetExam: kTargetExamGroupBCombined,
      questions: questions,
      selected: selected,
    );
    expect(result.totalQuestions, 30);
    final polity = result.areaResults.singleWhere((a) => a.areaId == 'polity');
    expect(polity.percent, 0);
    expect(polity.band, WeaknessThresholds.defaults.bandFor(0));
    expect(polity.band, WeaknessBand.weak);
    expect(result.weakAreas.map((a) => a.areaId), contains('polity'));

    final history = result.areaResults.singleWhere((a) => a.areaId == 'history');
    expect(history.percent, 100);
    expect(history.band, WeaknessBand.strong);
    expect(result.strongAreas.map((a) => a.areaId), contains('history'));
  });

  test('diagnostic persist seeds testAttempts and existing planner/weakness',
      () async {
    final db = FakeFirebaseFirestore();
    final progress = StudentProgressRepository(firestore: db);
    final diagnostic = DiagnosticService(progress: progress);
    final questions = groupBDiagnosticQuestions();
    final selected = List<int?>.generate(
      questions.length,
      (i) => questions[i].areaId == 'polity'
          ? (questions[i].correctIndex + 1) % questions[i].options.length
          : questions[i].correctIndex,
    );
    final scored = diagnostic.score(
      attemptId: 'diag1',
      targetExam: kTargetExamGroupBCombined,
      questions: questions,
      selected: selected,
      now: DateTime(2026, 9, 4, 12),
    );
    await diagnostic.persist('student_1', scored);
    await expectLater(
      diagnostic.persist('  ', scored),
      throwsA(isA<StateError>()),
    );

    final stored = await progress.latestDiagnosticAttempt('student_1');
    expect(stored, isNotNull);
    expect(stored!['kind'], 'diagnostic');
    expect(stored['totalQuestions'], 30);
    expect(stored['targetExam'], kTargetExamGroupBCombined);

    final attempts = await progress.getTestAttempts('student_1');
    expect(attempts.any((a) => a.kind == 'diagnostic'), isTrue);
    expect(
      attempts.every((a) => a.kind != 'pyq'),
      isTrue,
    );
    expect(
      attempts.every((a) => !a.testTitle.toLowerCase().contains('previous year')),
      isTrue,
    );

    final profile = StudentProfile(
      uid: 'student_1',
      name: 'Asha',
      email: 'a@x.com',
      mobile: '9999999999',
      targetExam: kTargetExamGroupBCombined,
      dailyStudyHours: 5,
      studyMode: kStudyModePartTime,
      preparationStage: 'Beginner',
      preferredLanguage: 'Marathi + English',
      onboardingCompleted: true,
      diagnosticCompleted: false,
    );
    final profiles = ProfileRepository(firestore: db);
    await profiles.saveProfile(profile);

    final weakness = FirestoreAiWeaknessTracker(
      progress: progress,
      classroom: LessonProgressRepository(firestore: db),
      syllabus: _EmptySyllabus(),
      profiles: profiles,
    );
    final planner = DailyPlannerService(
      syllabus: _EmptySyllabus(),
      weakness: weakness,
      progress: progress,
      profiles: profiles,
    );
    final plans = PersonalizedStudyPlanService(
      planner: planner,
      weakness: weakness,
      syllabus: _EmptySyllabus(),
      progress: progress,
    );
    final plan = await plans.createAndSave(
      uid: 'student_1',
      profile: profile,
      diagnostic: scored,
      now: DateTime(2026, 9, 4, 12),
    );
    expect(plan.tasks, isNotEmpty);
    expect(
      plan.adaptationNotes.join(' '),
      contains('Your Personalized Study Plan is Ready'),
    );
    expect(plan.adaptationNotes.join(' '), contains('Polity'));
    expect(plan.adaptationNotes.join(' '), contains('History'));
    final saved = await progress.getDailyPlan('student_1', dateKey: plan.dateKey);
    expect(saved, isNotNull);
    expect(saved!.tasks, isNotEmpty);

    final snap = await weakness.load(
      'student_1',
      syllabus: groupBFallbackSyllabus(),
      now: DateTime(2026, 9, 4, 12),
    );
    expect(snap.hasPerformance, isTrue);
    expect(snap.signals, isNotEmpty);
  });

  test('firestore.rules allow owner diagnosticAttempts writes', () {
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules, contains('match /students/{uid}'));
    expect(rules, contains('function isOwner(uid)'));
    expect(rules, contains('request.auth.uid == uid'));
    expect(rules, isNot(contains('allow write: if true')));
    for (final path in [
      'match /diagnosticAttempts/{attemptId}',
      'match /testAttempts/{attemptId}',
      'match /studyPlans/{planId}',
    ]) {
      final start = rules.indexOf(path);
      expect(start, greaterThanOrEqualTo(0), reason: path);
      final block = rules.substring(start, start + 180);
      expect(block, contains('allow read: if isOwner(uid) || isAdmin();'));
      expect(block, contains('allow write: if isOwner(uid);'));
      expect(block, isNot(contains('allow write: if isOwner(uid) || isAdmin()')));
    }
  });

  test('student-facing Dart UI has no MIT / incubation branding', () {
    final hits = <String>[];
    final root = Directory('lib');
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final normalized = file.path.replaceAll('\\', '/');
      if (normalized.contains('/admin/')) continue;
      final text = file.readAsStringSync();
      for (final needle in [
        'MIT Pune',
        'MIT ADT',
        'MIT Incubation',
        'MIT incubation',
        'AIC MIT',
        'incubation',
        'incubator',
      ]) {
        if (text.contains(needle)) {
          hits.add('$normalized: $needle');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('Economy diagnostic maps to Economy, not General Ability Test', () {
    final questions = groupBDiagnosticQuestions();
    final selected = List<int?>.generate(questions.length, (i) {
      if (questions[i].areaId == 'economy') {
        return (questions[i].correctIndex + 1) % questions[i].options.length;
      }
      return questions[i].correctIndex;
    });
    final result = DiagnosticService().score(
      attemptId: 'eco0',
      targetExam: kTargetExamGroupBCombined,
      questions: questions,
      selected: selected,
    );
    final economy = result.areaResults.singleWhere((a) => a.areaId == 'economy');
    expect(economy.percent, 0);
    expect(economy.mappingLine, contains('Economy →'));
    expect(economy.mappingLine, contains('Basics of Indian Economy'));
    expect(economy.mappingLine, isNot(contains('General Ability Test')));
    expect(economy.title, 'Economy');
    final chapter = groupBChapterForArea('economy')!;
    expect(plannerSubjectTitleForChapter(chapter), 'Economy');
  });

  test('adaptive plan includes full Group B syllabus areas, not only weak ones', () {
    final scored = DiagnosticService().score(
      attemptId: 'a2',
      targetExam: kTargetExamGroupBCombined,
      questions: groupBDiagnosticQuestions(),
      selected: List<int?>.generate(groupBDiagnosticQuestions().length, (i) {
        final q = groupBDiagnosticQuestions()[i];
        if (q.areaId == 'economy') {
          return (q.correctIndex + 1) % q.options.length;
        }
        return q.correctIndex;
      }),
    );
    final syllabus = groupBFallbackSyllabus();
    expect(syllabus.topics.map((t) => t.plannerAreaId).toSet(), containsAll([
      'current_affairs',
      'history',
      'geography',
      'economy',
      'polity',
      'general_science',
      'intelligence_arithmetic',
      'marathi',
      'english',
      'environment',
    ]));
    final weakness = WeaknessSnapshot(
      signals: [
        for (final area in scored.areaResults)
          WeakTopicSignal(
            label: groupBChapterForArea(area.areaId)?.title ?? area.title,
            scorePercent: area.percent,
            source: 'diagnostic',
            subjectId: area.subjectId,
            chapterId: area.chapterId,
            subjectTitle: area.title,
            attempted: area.attempted,
            correct: area.correct,
            band: area.band,
          ),
      ],
      averageTestPercent: scored.scorePercentage,
      attemptsThisWeek: 1,
    );
    final prefs = const PlannerPrefs(
      targetExam: kTargetExamGroupBCombined,
      examDate: '',
      dailyHours: 6,
      preparationDurationDays: 90,
    );
    final day1 = DailyPlannerService().buildPlan(
      uid: 'u1',
      prefs: prefs,
      dateKey: '2026-09-07',
      syllabus: syllabus,
      weakness: weakness,
      now: DateTime(2026, 9, 7),
    );
    expect(day1.tasks, isNotEmpty);
    expect(day1.adaptationNotes.join(' '), contains('Weak: Economy'));
    expect(day1.adaptationNotes.join(' '), isNot(contains('Weak: General Ability Test')));
    expect(day1.topicsTotal, greaterThan(100));
    expect(day1.daysRemaining, 90);

    final horizon = DailyPlannerService().previewHorizon(
      uid: 'u1',
      prefs: prefs,
      syllabus: syllabus,
      weakness: weakness,
      now: DateTime(2026, 9, 7),
      days: 10,
    );
    final subjects = {
      for (final d in horizon)
        for (final t in d.tasks) t.subject,
    };
    expect(subjects, contains('Economy'));
    expect(subjects, anyOf(contains('Marathi'), contains('English')));
    expect(subjects, contains('Current Affairs'));

    final yesterday = day1.copyWith(
      tasks: [
        for (final t in day1.tasks)
          t.id == day1.tasks.first.id
              ? t
              : t.copyWith(status: DailyPlanTaskStatus.completed),
      ],
    );
    final day2 = DailyPlannerService().buildPlan(
      uid: 'u1',
      prefs: prefs,
      dateKey: '2026-09-08',
      syllabus: syllabus,
      weakness: weakness,
      recentPlans: [yesterday],
      now: DateTime(2026, 9, 8),
    );
    expect(
      day2.tasks.any((t) => t.isCarriedForward),
      isTrue,
    );
  });
}
