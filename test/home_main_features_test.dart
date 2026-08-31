import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_hub_screen.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_screen.dart';
import 'package:mpsc_combine_ai/screens/current_affairs_screen.dart';
import 'package:mpsc_combine_ai/screens/home/home_main_features.dart';
import 'package:mpsc_combine_ai/screens/jobs/job_alerts_screen.dart';
import 'package:mpsc_combine_ai/screens/practice/smart_practice_test_series_screen.dart';
import 'package:mpsc_combine_ai/screens/pyq_screen.dart';
import 'package:mpsc_combine_ai/screens/study_planner_screen.dart';
import 'package:mpsc_combine_ai/screens/syllabus/syllabus_tracker_screen.dart';
import 'package:mpsc_combine_ai/screens/weakness/ai_weakness_tracker_screen.dart';

void main() {
  testWidgets('Home Main Features shows the three Home cards only', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: HomeMainFeaturesSection(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Main Features'), findsOneWidget);
    expect(find.byType(MainFeatureCard), findsNWidgets(3));
    expect(homeMainFeatures(), hasLength(3));

    for (final feature in homeMainFeatures()) {
      expect(find.text(feature.title), findsOneWidget);
      expect(find.byKey(ValueKey<String>(feature.cardKey)), findsOneWidget);
    }

    expect(find.text('Previous Year Questions (PYQ)'), findsNothing);
    expect(find.text('Current Affairs + Daily Quiz'), findsNothing);
    expect(find.text('Smart Practice + Test Series'), findsNothing);
    expect(find.text('Instant Doubt Solving'), findsNothing);
    expect(find.text('Syllabus Tracker + Progress'), findsNothing);
    expect(find.text('On-Demand AI Video'), findsNothing);
  });

  testWidgets('Main Features grid fits a phone-width Home layout', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
      old?.call(details);
    };
    addTearDown(() => FlutterError.onError = old);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: HomeMainFeaturesSection(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Main Features'), findsOneWidget);
    expect(find.byType(MainFeatureCard), findsNWidgets(3));
    expect(errors.where((e) => e.toString().contains('overflowed')), isEmpty);
  });

  test('the three Home Main Feature cards open their existing screens', () {
    final visible = homeMainFeatures();
    expect(visible[0].buildScreen(), isA<StudyPlannerScreen>());
    expect(visible[1].buildScreen(), isA<AiWeaknessTrackerScreen>());
    expect(visible[2].buildScreen(), isA<JobAlertsScreen>());
  });

  test('other existing feature screens remain available', () {
    expect(kMainFeatures[1].buildScreen(), isA<PyqScreen>());
    expect(kMainFeatures[2].buildScreen(), isA<CurrentAffairsScreen>());
    expect(
      kMainFeatures[3].buildScreen(),
      isA<SmartPracticeTestSeriesScreen>(),
    );
    expect(kMainFeatures[5].buildScreen(), isA<AiTeacherScreen>());
    expect(kMainFeatures[6].buildScreen(), isA<SyllabusTrackerScreen>());
    expect(kMainFeatures[8].buildScreen(), isA<AiTeacherHubScreen>());
  });

  testWidgets('tapping Job Alerts opens the Job Alerts screen', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: HomeMainFeaturesSection(),
            ),
          ),
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('main-feature-jobAlerts')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('main-feature-jobAlerts')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(JobAlertsScreen), findsOneWidget);
    expect(find.text('Coming Soon'), findsNothing);
  });

  testWidgets('every Main Feature card is tappable', (tester) async {
    final opened = <MainFeatureId>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: HomeMainFeaturesSection(
                onOpen: (feature) => opened.add(feature.id),
              ),
            ),
          ),
        ),
      ),
    );

    for (final feature in homeMainFeatures()) {
      await tester.ensureVisible(find.byKey(ValueKey<String>(feature.cardKey)));
      await tester.tap(find.byKey(ValueKey<String>(feature.cardKey)));
      await tester.pump();
    }

    expect(opened, homeMainFeatures().map((f) => f.id).toList());
  });

  testWidgets('Job Alerts shows published-feed empty state, not a fake list', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: JobAlertsScreen()));
    expect(find.text('Job Alerts'), findsWidgets);
    expect(find.text('Coming Soon'), findsNothing);
    expect(find.textContaining('Automatic external job feeds'), findsOneWidget);
  });

  testWidgets('Smart Practice hub does not show Coming Soon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SmartPracticeTestSeriesScreen()),
    );
    expect(find.text('Smart Practice + Test Series'), findsWidgets);
    expect(find.text('Coming Soon'), findsNothing);
    expect(find.text('Smart Practice'), findsOneWidget);
    expect(find.text('Test Series'), findsOneWidget);
  });
}
