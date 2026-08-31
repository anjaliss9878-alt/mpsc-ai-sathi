import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_hub_screen.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_screen.dart';
import 'package:mpsc_combine_ai/screens/current_affairs_screen.dart';
import 'package:mpsc_combine_ai/screens/jobs/job_alerts_screen.dart';
import 'package:mpsc_combine_ai/screens/practice/smart_practice_test_series_screen.dart';
import 'package:mpsc_combine_ai/screens/pyq_screen.dart';
import 'package:mpsc_combine_ai/screens/study_planner_screen.dart';
import 'package:mpsc_combine_ai/screens/syllabus/syllabus_tracker_screen.dart';
import 'package:mpsc_combine_ai/screens/weakness/ai_weakness_tracker_screen.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

enum MainFeatureId {
  dailyPlanner,
  pyq,
  currentAffairs,
  practiceTests,
  weaknessTracker,
  doubtSolving,
  syllabusTracker,
  jobAlerts,
  onDemandAiVideo,
}

class MainFeatureSpec {
  const MainFeatureSpec({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.buildScreen,
  });

  final MainFeatureId id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget Function() buildScreen;

  String get cardKey => 'main-feature-${id.name}';
}

/// The nine Home-screen Main Features and the existing screens they open.
const List<MainFeatureSpec> kMainFeatures = [
  MainFeatureSpec(
    id: MainFeatureId.dailyPlanner,
    title: 'Personalized Daily Planner',
    subtitle: 'Today\'s study plan, built around your exam.',
    icon: Icons.calendar_today_rounded,
    buildScreen: _planner,
  ),
  MainFeatureSpec(
    id: MainFeatureId.pyq,
    title: 'Previous Year Questions (PYQ)',
    subtitle: 'Past MPSC papers by year and exam.',
    icon: Icons.history_edu_rounded,
    buildScreen: _pyq,
  ),
  MainFeatureSpec(
    id: MainFeatureId.currentAffairs,
    title: 'Current Affairs + Daily Quiz',
    subtitle: 'Daily news briefings and quizzes.',
    icon: Icons.newspaper_rounded,
    buildScreen: _currentAffairs,
  ),
  MainFeatureSpec(
    id: MainFeatureId.practiceTests,
    title: 'Smart Practice + Test Series',
    subtitle: 'MCQ practice and timed mock tests.',
    icon: Icons.assignment_rounded,
    buildScreen: _practice,
  ),
  MainFeatureSpec(
    id: MainFeatureId.weaknessTracker,
    title: 'AI Weakness Tracker',
    subtitle: 'See weak topics and what to revise.',
    icon: Icons.insights_rounded,
    buildScreen: _weakness,
  ),
  MainFeatureSpec(
    id: MainFeatureId.doubtSolving,
    title: 'Instant Doubt Solving',
    subtitle: 'Ask the AI teacher any question.',
    icon: Icons.chat_bubble_outline_rounded,
    buildScreen: _doubts,
  ),
  MainFeatureSpec(
    id: MainFeatureId.syllabusTracker,
    title: 'Syllabus Tracker + Progress',
    subtitle: 'Topic coverage across every subject.',
    icon: Icons.checklist_rounded,
    buildScreen: _syllabus,
  ),
  MainFeatureSpec(
    id: MainFeatureId.jobAlerts,
    title: 'Job Alerts',
    subtitle: 'MPSC recruitment and vacancy updates.',
    icon: Icons.work_outline_rounded,
    buildScreen: _jobs,
  ),
  MainFeatureSpec(
    id: MainFeatureId.onDemandAiVideo,
    title: 'On-Demand AI Video',
    subtitle: 'Generate an AI classroom lesson.',
    icon: Icons.smart_display_rounded,
    buildScreen: _aiVideo,
  ),
];

Widget _planner() => const StudyPlannerScreen();
Widget _pyq() => const PyqScreen();
Widget _currentAffairs() => const CurrentAffairsScreen();
Widget _practice() => const SmartPracticeTestSeriesScreen();
Widget _weakness() => const AiWeaknessTrackerScreen();
Widget _doubts() => const AiTeacherScreen();
Widget _syllabus() => const SyllabusTrackerScreen();
Widget _jobs() => const JobAlertsScreen();
Widget _aiVideo() => const AiTeacherHubScreen();

void openMainFeature(BuildContext context, MainFeatureSpec feature) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => feature.buildScreen()));
}

/// Home "Main Features" section shows only these existing cards.
const List<MainFeatureId> kHomeMainFeatureIds = [
  MainFeatureId.dailyPlanner,
  MainFeatureId.weaknessTracker,
  MainFeatureId.jobAlerts,
];

List<MainFeatureSpec> homeMainFeatures() => [
  for (final id in kHomeMainFeatureIds)
    kMainFeatures.firstWhere((f) => f.id == id),
];

/// Visible Main Feature cards on the student Home screen.
class HomeMainFeaturesSection extends StatelessWidget {
  const HomeMainFeaturesSection({super.key, this.onOpen});

  /// Test hook. Production always pushes the real feature screen.
  final void Function(MainFeatureSpec feature)? onOpen;

  @override
  Widget build(BuildContext context) {
    final features = homeMainFeatures();
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 720 ? 3 : 2;
    final aspectRatio = width >= 720 ? 1.25 : 1.02;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: AppColors.sky,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Main Features',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Tap a card to open that feature.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: features.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: aspectRatio,
          ),
          itemBuilder: (context, index) {
            final feature = features[index];
            return MainFeatureCard(
              feature: feature,
              onTap: () {
                if (onOpen != null) {
                  onOpen!(feature);
                } else {
                  openMainFeature(context, feature);
                }
              },
            );
          },
        ),
      ],
    );
  }
}

class MainFeatureCard extends StatelessWidget {
  const MainFeatureCard({
    super.key,
    required this.feature,
    required this.onTap,
  });

  final MainFeatureSpec feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: feature.title,
      child: Card(
        key: ValueKey<String>(feature.cardKey),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(feature.icon, color: AppColors.navy, size: 22),
                ),
                const SizedBox(height: 10),
                Text(
                  feature.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.25,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    feature.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 12,
                  color: AppColors.sky.withValues(alpha: 0.85),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
