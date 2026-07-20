import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_screen.dart';
import 'package:mpsc_combine_ai/screens/auth/auth_gate.dart';
import 'package:mpsc_combine_ai/screens/auth/profile_screen.dart';
import 'package:mpsc_combine_ai/screens/current_affairs_screen.dart';
import 'package:mpsc_combine_ai/screens/live_classes_screen.dart';
import 'package:mpsc_combine_ai/screens/mcq_practice_screen.dart';
import 'package:mpsc_combine_ai/screens/mock_tests_screen.dart';
import 'package:mpsc_combine_ai/screens/my_performance_screen.dart';
import 'package:mpsc_combine_ai/screens/pyq_screen.dart';
import 'package:mpsc_combine_ai/screens/study_planner_screen.dart';
import 'package:mpsc_combine_ai/screens/subject_notes_screen.dart';
import 'package:mpsc_combine_ai/screens/videos_screen.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/firebase_initializer.dart';

void main() {
  runApp(const MpscCombineApp());
}

// ─── Data Models ──────────────────────────────────────────────────────────────

class FeatureItem {
  const FeatureItem({
    required this.title,
    required this.icon,
    this.screen,
    this.onTap,
  }) : assert(
          screen != null || onTap != null,
          'FeatureItem needs either a screen to push or a custom onTap.',
        );

  final String title;
  final IconData icon;

  /// Pushed via [Navigator] when tapped, unless [onTap] is provided instead
  /// (e.g. to switch bottom-nav tabs, like the Profile card does).
  final Widget? screen;
  final VoidCallback? onTap;
}

class ContinueItem {
  const ContinueItem({
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.icon,
    required this.snackMessage,
  });

  final String title;
  final String subtitle;
  final double progress;
  final IconData icon;
  final String snackMessage;
}

// ─── Root App ─────────────────────────────────────────────────────────────────

class MpscCombineApp extends StatelessWidget {
  const MpscCombineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MPSC COMBINE AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.navy,
          primary: AppColors.navy,
          secondary: AppColors.orange,
          surface: AppColors.background,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: AppColors.cardWhite,
          elevation: 2,
          shadowColor: AppColors.navy.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          backgroundColor: AppColors.navy,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.orange,
          unselectedItemColor: AppColors.textSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 12,
        ),
      ),
      home: const FirebaseInitializer(
        child: AuthGate(loggedInChild: MainShell()),
      ),
    );
  }
}

// ─── Main Shell with Bottom Navigation ────────────────────────────────────────

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const _navLabels = [
    'Home',
    'Courses',
    'AI Teacher',
    'Tests',
    'Profile',
  ];

  void _onNavTap(int index) {
    setState(() => _currentIndex = index);
    // Home (0) and Profile (4) are implemented; the rest are still placeholders.
    if (index != 0 && index != 4) {
      _showSnack('${_navLabels[index]} — Coming soon!');
    }
  }

  /// Lets tab content (e.g. the Home dashboard's Profile card) switch the
  /// bottom-nav tab directly, instead of pushing a second Profile route.
  void _goToTab(int index) => setState(() => _currentIndex = index);

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(onSnack: _showSnack, onNavigateToTab: _goToTab),
          const PlaceholderTab(label: 'Courses'),
          const PlaceholderTab(label: 'AI Teacher'),
          const PlaceholderTab(label: 'Tests'),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onNavTap,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book_outlined),
            activeIcon: Icon(Icons.menu_book_rounded),
            label: 'Courses',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.psychology_outlined),
            activeIcon: Icon(Icons.psychology_rounded),
            label: 'AI Teacher',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.fact_check_outlined),
            activeIcon: Icon(Icons.fact_check_rounded),
            label: 'Tests',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.construction_rounded,
            size: 56,
            color: AppColors.navy.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coming soon',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Home Screen ──────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onSnack,
    required this.onNavigateToTab,
  });

  final void Function(String message) onSnack;

  /// Switches the bottom-nav tab (used by the Profile card below).
  final void Function(int tabIndex) onNavigateToTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StudentProfile? _profile;
  bool _isLoadingProfile = true;

  static const _continueItems = [
    ContinueItem(
      title: 'भारतीय राज्यव्यवस्था',
      subtitle: 'Chapter 4 — संसद',
      progress: 0.65,
      icon: Icons.account_balance_rounded,
      snackMessage: 'Resuming: भारतीय राज्यव्यवस्था',
    ),
    ContinueItem(
      title: 'MCQ Practice',
      subtitle: 'Set 12 — 30 questions',
      progress: 0.40,
      icon: Icons.quiz_rounded,
      snackMessage: 'Resuming: MCQ Practice Set 12',
    ),
    ContinueItem(
      title: 'Current Affairs',
      subtitle: 'July 2026 — Week 2',
      progress: 0.20,
      icon: Icons.newspaper_rounded,
      snackMessage: 'Resuming: Current Affairs July 2026',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = authService.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoadingProfile = false);
      return;
    }
    try {
      final profile = await profileRepository.getProfile(uid);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _isLoadingProfile = false;
      });
    } catch (_) {
      // Dashboard falls back to defaults below — a Firestore hiccup here
      // must never block the Home screen from rendering.
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  List<FeatureItem> _buildFeatures() {
    return [
      const FeatureItem(
        title: 'AI Teacher',
        icon: Icons.psychology_rounded,
        screen: AiTeacherScreen(),
      ),
      const FeatureItem(
        title: 'Live Classes',
        icon: Icons.live_tv_rounded,
        screen: LiveClassesScreen(),
      ),
      const FeatureItem(
        title: 'विषयवार नोट्स',
        icon: Icons.library_books_rounded,
        screen: SubjectNotesScreen(),
      ),
      const FeatureItem(
        title: 'MCQ Practice',
        icon: Icons.quiz_rounded,
        screen: McqPracticeScreen(),
      ),
      const FeatureItem(
        title: 'Previous Year Questions',
        icon: Icons.history_edu_rounded,
        screen: PyqScreen(),
      ),
      const FeatureItem(
        title: 'Daily Current Affairs',
        icon: Icons.newspaper_rounded,
        screen: CurrentAffairsScreen(),
      ),
      const FeatureItem(
        title: 'Mock Tests',
        icon: Icons.assignment_rounded,
        screen: MockTestsScreen(),
      ),
      const FeatureItem(
        title: 'Videos',
        icon: Icons.smart_display_rounded,
        screen: VideosScreen(),
      ),
      const FeatureItem(
        title: 'Study Planner',
        icon: Icons.calendar_month_rounded,
        screen: StudyPlannerScreen(),
      ),
      const FeatureItem(
        title: 'My Performance',
        icon: Icons.insights_rounded,
        screen: MyPerformanceScreen(),
      ),
      FeatureItem(
        title: 'Profile',
        icon: Icons.person_rounded,
        onTap: () => widget.onNavigateToTab(4),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth > 600 ? 24.0 : 16.0;
    final maxContentWidth = screenWidth > 800 ? 800.0 : double.infinity;
    final features = _buildFeatures();

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _HomeHeader(horizontalPadding: horizontalPadding),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: _WelcomeSection(
                    onSnack: widget.onSnack,
                    studentName: _profile?.name,
                    targetExam: _profile?.targetExam,
                    isLoadingProfile: _isLoadingProfile,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    20,
                    horizontalPadding,
                    0,
                  ),
                  child: _SearchBar(onTap: () {
                    widget.onSnack('Search — Coming soon!');
                  }),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    24,
                    horizontalPadding,
                    0,
                  ),
                  child: _StudyGoalCard(
                    onTap: () => widget.onSnack('Study Goal — Coming soon!'),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    28,
                    horizontalPadding,
                    0,
                  ),
                  child: const _SectionTitle(title: 'Explore Features'),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  12,
                  horizontalPadding,
                  0,
                ),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.05,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final feature = features[index];
                      return FeatureCard(
                        feature: feature,
                        onTap: () {
                          if (feature.onTap != null) {
                            feature.onTap!();
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => feature.screen!,
                              ),
                            );
                          }
                        },
                      );
                    },
                    childCount: features.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    28,
                    horizontalPadding,
                    0,
                  ),
                  child: const _SectionTitle(title: 'Continue Learning'),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 148,
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      12,
                      horizontalPadding,
                      0,
                    ),
                    scrollDirection: Axis.horizontal,
                    itemCount: _continueItems.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final item = _continueItems[index];
                      return ContinueLearningCard(
                        item: item,
                        onTap: () => widget.onSnack(item.snackMessage),
                      );
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Reusable Widgets ─────────────────────────────────────────────────────────

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.horizontalPadding});

  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navyDark, AppColors.navy, AppColors.navyLight],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(horizontalPadding, 20, horizontalPadding, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: AppColors.orange,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MPSC COMBINE AI',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Learn Smarter. Achieve Faster.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('Notifications — Coming soon!'),
                        ),
                      );
                  },
                  icon: const Icon(
                    Icons.notifications_outlined,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Unique Academy Kolhapur',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.orangeLight,
                          fontWeight: FontWeight.w500,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeSection extends StatelessWidget {
  const _WelcomeSection({
    required this.onSnack,
    required this.studentName,
    required this.targetExam,
    required this.isLoadingProfile,
  });

  final void Function(String message) onSnack;
  final String? studentName;
  final String? targetExam;
  final bool isLoadingProfile;

  @override
  Widget build(BuildContext context) {
    final name = (studentName != null && studentName!.trim().isNotEmpty)
        ? studentName!.trim()
        : 'विद्यार्थी';
    final hasTargetExam = targetExam != null && targetExam!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'नमस्कार, $name!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                if (!isLoadingProfile && hasTargetExam)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.flag_rounded,
                          size: 13,
                          color: AppColors.orange,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'लक्ष्य: ${targetExam!.trim()}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.orange,
                                      fontWeight: FontWeight.w700,
                                    ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    'Ready to ace your MPSC Combine exam?',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: AppColors.orange,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => onSnack('Quick Start — Coming soon!'),
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 4),
                    Text(
                      'Start',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: AppColors.navy.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: AppColors.textSecondary.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'विषय, नोट्स किंवा प्रश्न शोधा',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudyGoalCard extends StatelessWidget {
  const _StudyGoalCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const progress = 0.55;
    const completed = 2;
    const total = 4;

    return TappableCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.flag_rounded,
                  color: AppColors.orange,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's Study Goal",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$completed of $total tasks completed',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.orange,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.navy.withValues(alpha: 0.08),
              color: AppColors.orange,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _GoalChip(label: 'Notes', done: true),
              _GoalChip(label: 'MCQs', done: true),
              _GoalChip(label: 'Revision', done: false),
              _GoalChip(label: 'Test', done: false),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalChip extends StatelessWidget {
  const _GoalChip({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: done
            ? AppColors.navy.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: done
              ? AppColors.navy.withValues(alpha: 0.15)
              : AppColors.textSecondary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 12,
            color: done ? AppColors.navy : AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: done ? AppColors.navy : AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.orange,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
        ),
      ],
    );
  }
}

class TappableCard extends StatelessWidget {
  const TappableCard({
    super.key,
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}

class FeatureCard extends StatelessWidget {
  const FeatureCard({
    super.key,
    required this.feature,
    required this.onTap,
  });

  final FeatureItem feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  feature.icon,
                  color: AppColors.navy,
                  size: 26,
                ),
              ),
              const Spacer(),
              Text(
                feature.title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: AppColors.orange.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ContinueLearningCard extends StatelessWidget {
  const ContinueLearningCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  final ContinueItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        item.icon,
                        color: AppColors.orange,
                        size: 20,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(item.progress * 100).toInt()}%',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.orange,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: item.progress,
                    minHeight: 4,
                    backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                    color: AppColors.orange,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
