import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/models/continue_session.dart';
import 'package:mpsc_combine_ai/models/study_goal.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_hub_screen.dart';
import 'package:mpsc_combine_ai/screens/auth/auth_gate.dart';
import 'package:mpsc_combine_ai/screens/auth/profile_screen.dart';
import 'package:mpsc_combine_ai/screens/courses/courses_tab_screen.dart';
import 'package:mpsc_combine_ai/screens/current_affairs_screen.dart';
import 'package:mpsc_combine_ai/screens/home/home_main_features.dart';
import 'package:mpsc_combine_ai/screens/home/home_upgrade_sections.dart';
import 'package:mpsc_combine_ai/screens/live_classes/live_classes_home_screen.dart';
import 'package:mpsc_combine_ai/screens/mcq_practice_screen.dart';
import 'package:mpsc_combine_ai/screens/mock_tests_screen.dart';
import 'package:mpsc_combine_ai/screens/my_performance_screen.dart';
import 'package:mpsc_combine_ai/screens/notifications/notifications_inbox_screen.dart';
import 'package:mpsc_combine_ai/screens/pyq_screen.dart';
import 'package:mpsc_combine_ai/screens/revision/revision_hub_screen.dart';
import 'package:mpsc_combine_ai/screens/search/global_search_screen.dart';
import 'package:mpsc_combine_ai/screens/study_goal_screen.dart';
import 'package:mpsc_combine_ai/screens/subject_notes_screen.dart';
import 'package:mpsc_combine_ai/screens/tests/tests_tab_screen.dart';
import 'package:mpsc_combine_ai/screens/topic_list_screen.dart';
import 'package:mpsc_combine_ai/screens/videos_screen.dart';
import 'package:mpsc_combine_ai/models/notification_item.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/notification_repository.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/firebase_initializer.dart';

void main() {
  // Required for Flutter web plugins / Firebase before first frame.
  WidgetsFlutterBinding.ensureInitialized();
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
    this.session,
  });

  final String title;
  final String subtitle;
  final double progress;
  final IconData icon;
  final String snackMessage;
  final ContinueSession? session;
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
          secondary: AppColors.sky,
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
          selectedItemColor: AppColors.sky,
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

  void _onNavTap(int index) {
    setState(() => _currentIndex = index);
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
    final Widget body = switch (_currentIndex) {
      0 => HomeScreen(onSnack: _showSnack, onNavigateToTab: _goToTab),
      1 => const CoursesTabScreen(),
      2 => const AiTeacherHubScreen(embeddedInTab: true),
      3 => const TestsTabScreen(),
      _ => const ProfileScreen(),
    };

    return Scaffold(
      body: body,
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

  Future<void> _openAiClassroom(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AiTeacherHubScreen(),
      ),
    );
  }

  Future<void> _openContinueSession(ContinueSession session) async {
    switch (session.type) {
      case 'classroom':
        await _openAiClassroom(context);
        return;
      case 'mcq':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const McqPracticeScreen()),
        );
        return;
      case 'test':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const MockTestsScreen()),
        );
        return;
      case 'revision':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const RevisionHubScreen()),
        );
        return;
      case 'current_affairs':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CurrentAffairsScreen()),
        );
        return;
      case 'video':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const VideosScreen()),
        );
        return;
      case 'notes':
      case 'chapter':
      default:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SubjectNotesScreen()),
        );
    }
  }

  IconData _iconForContinue(String type) => switch (type) {
        'mcq' => Icons.quiz_rounded,
        'classroom' => Icons.co_present_rounded,
        'test' => Icons.assignment_rounded,
        'revision' => Icons.style_rounded,
        'current_affairs' => Icons.newspaper_rounded,
        'video' => Icons.smart_display_rounded,
        _ => Icons.menu_book_rounded,
      };

  List<FeatureItem> _buildFeatures() {
    return [
      FeatureItem(
        title: 'AI Teacher',
        icon: Icons.psychology_rounded,
        onTap: () => widget.onNavigateToTab(2),
      ),
      FeatureItem(
        title: 'Courses',
        icon: Icons.menu_book_rounded,
        onTap: () => widget.onNavigateToTab(1),
      ),
      const FeatureItem(
        title: 'Notes',
        icon: Icons.library_books_rounded,
        screen: SubjectNotesScreen(),
      ),
      const FeatureItem(
        title: 'Practice',
        icon: Icons.quiz_rounded,
        screen: McqPracticeScreen(),
      ),
      FeatureItem(
        title: 'Tests',
        icon: Icons.fact_check_rounded,
        onTap: () => widget.onNavigateToTab(3),
      ),
      const FeatureItem(
        title: 'PYQ',
        icon: Icons.history_edu_rounded,
        screen: PyqScreen(),
      ),
      const FeatureItem(
        title: 'Revision',
        icon: Icons.style_rounded,
        screen: RevisionHubScreen(),
      ),
      const FeatureItem(
        title: 'Live Classes',
        icon: Icons.live_tv_rounded,
        screen: LiveClassesHomeScreen(),
      ),
      const FeatureItem(
        title: 'My Progress',
        icon: Icons.insights_rounded,
        screen: MyPerformanceScreen(),
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
                    studentName: _profile?.name,
                    targetExam: _profile?.targetExam,
                    isLoadingProfile: _isLoadingProfile,
                    onQuickStart: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const StudyGoalScreen(),
                        ),
                      );
                    },
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
                  child: _SearchBar(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const GlobalSearchScreen(),
                        ),
                      );
                    },
                  ),
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
                  child: const _SectionTitle(title: 'Continue Learning'),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 148,
                  child: Builder(
                    builder: (context) {
                      final uid = authService.currentUser?.uid;
                      if (uid == null) {
                        return ListView(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            12,
                            horizontalPadding,
                            0,
                          ),
                          scrollDirection: Axis.horizontal,
                          children: [
                            ContinueLearningCard(
                              item: const ContinueItem(
                                title: 'Start Learning',
                                subtitle: 'Open Courses',
                                progress: 0,
                                icon: Icons.school_rounded,
                                snackMessage: '',
                              ),
                              onTap: () => widget.onNavigateToTab(1),
                            ),
                          ],
                        );
                      }
                      return StreamBuilder<List<ContinueSession>>(
                        stream:
                            studentProgressRepository.watchContinueSessions(uid),
                        builder: (context, snapshot) {
                          final sessions =
                              snapshot.data ?? const <ContinueSession>[];
                          final items = sessions.isEmpty
                              ? const [
                                  ContinueItem(
                                    title: 'Subject Notes',
                                    subtitle: 'Start a chapter',
                                    progress: 0,
                                    icon: Icons.library_books_rounded,
                                    snackMessage: '',
                                  ),
                                  ContinueItem(
                                    title: 'MCQ Tests',
                                    subtitle: 'Practice questions',
                                    progress: 0,
                                    icon: Icons.quiz_rounded,
                                    snackMessage: '',
                                  ),
                                  ContinueItem(
                                    title: 'AI Teacher',
                                    subtitle: 'Continue the lesson',
                                    progress: 0,
                                    icon: Icons.co_present_rounded,
                                    snackMessage: '',
                                  ),
                                ]
                              : sessions
                                  .take(8)
                                  .map(
                                    (s) => ContinueItem(
                                      title: s.title,
                                      subtitle: s.subtitle,
                                      progress: s.progress,
                                      icon: _iconForContinue(s.type),
                                      snackMessage: '',
                                      session: s,
                                    ),
                                  )
                                  .toList();
                          return ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              12,
                              horizontalPadding,
                              0,
                            ),
                            scrollDirection: Axis.horizontal,
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return ContinueLearningCard(
                                item: item,
                                onTap: () {
                                  if (item.session != null) {
                                    _openContinueSession(item.session!);
                                    return;
                                  }
                                  if (item.title.contains('MCQ')) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const McqPracticeScreen(),
                                      ),
                                    );
                                  } else if (item.title.contains('Classroom') ||
                                      item.title.contains('AI')) {
                                    _openAiClassroom(context);
                                  } else {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const SubjectNotesScreen(),
                                      ),
                                    );
                                  }
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
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
                  child: const HomeMainFeaturesSection(),
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
                  child: Builder(
                    builder: (context) {
                      final uid = authService.currentUser?.uid;
                      if (uid == null) {
                        return _StudyGoalCard(
                          goal: StudyGoal.emptyForToday(),
                          streakDays: 0,
                          onTap: () =>
                              widget.onSnack('Sign in to track study goals.'),
                        );
                      }
                      return StreamBuilder<StudyGoal>(
                        stream: studentProgressRepository.watchTodayGoal(uid),
                        builder: (context, snapshot) {
                          final goal =
                              snapshot.data ?? StudyGoal.emptyForToday();
                          return StreamBuilder<int>(
                            stream:
                                studentProgressRepository.watchStudyStreak(uid),
                            builder: (context, streakSnap) {
                              return _StudyGoalCard(
                                goal: goal,
                                streakDays: streakSnap.data ?? 0,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const StudyGoalScreen(),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
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
                        child: const _SectionTitle(title: 'Start Learning'),
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
                  child: Row(
                    children: [
                      const Expanded(
                        child: _SectionTitle(title: 'Subjects'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SubjectNotesScreen(),
                            ),
                          );
                        },
                        child: const Text('See All'),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 112,
                  child: StreamBuilder<List<SubjectItem>>(
                    stream: notesRepository.watchPublishedSubjects(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            12,
                            horizontalPadding,
                            0,
                          ),
                          child: Text(
                            'Subjects could not be loaded. Please try again.',
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        );
                      }
                      final subjects = snapshot.data ?? const <SubjectItem>[];
                      if (!snapshot.hasData) {
                        return const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      if (subjects.isEmpty) {
                        return Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            12,
                            horizontalPadding,
                            0,
                          ),
                          child: Text(
                            'No published subjects yet. Publish them from the Admin Panel.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          12,
                          horizontalPadding,
                          0,
                        ),
                        scrollDirection: Axis.horizontal,
                        itemCount: subjects.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final subject = subjects[index];
                          return ActionChip(
                            avatar: Icon(subject.icon, size: 18, color: AppColors.navy),
                            label: Text(subject.title),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => TopicListScreen(subject: subject),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: HomeUpgradeSections(horizontalPadding: horizontalPadding),
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

/// Bell icon with a live unread-count badge, sourced from the same
/// `students/{uid}/inbox` stream the [NotificationsInboxScreen] reads —
/// so it updates instantly whenever the Admin Panel sends a notification.
class _NotificationsBellButton extends StatelessWidget {
  const _NotificationsBellButton();

  @override
  Widget build(BuildContext context) {
    final uid = authService.currentUser?.uid;
    return IconButton(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const NotificationsInboxScreen()),
      ),
      icon: uid == null
          ? const Icon(Icons.notifications_outlined, color: Colors.white)
          : StreamBuilder<List<NotificationItem>>(
              stream: notificationRepository.watchInbox(uid),
              builder: (context, snapshot) {
                final unread = (snapshot.data ?? const <NotificationItem>[])
                    .where((n) => !n.isRead)
                    .length;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_outlined, color: Colors.white),
                    if (unread > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          decoration: const BoxDecoration(
                            color: AppColors.sky,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            unread > 9 ? '9+' : '$unread',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

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
                    color: AppColors.sky,
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
                        'AI-first MPSC Learning Platform',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const _NotificationsBellButton(),
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
                    'MIT Pune Startup Presentation',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
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
    required this.onQuickStart,
    required this.studentName,
    required this.targetExam,
    required this.isLoadingProfile,
  });

  final VoidCallback onQuickStart;
  final String? studentName;
  final String? targetExam;
  final bool isLoadingProfile;

  @override
  Widget build(BuildContext context) {
    final name = (studentName != null && studentName!.trim().isNotEmpty)
        ? studentName!.trim()
        : 'Student';
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
                  'Hello, $name!',
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
                      color: AppColors.sky.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.flag_rounded,
                          size: 13,
                          color: AppColors.sky,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Target: ${targetExam!.trim()}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.sky,
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
                    'Ready to crack the MPSC Combine exam?',
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
            color: AppColors.sky,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onQuickStart,
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
                  'Search subjects, notes, or questions',
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
  const _StudyGoalCard({
    required this.onTap,
    required this.goal,
    this.streakDays = 0,
  });

  final VoidCallback onTap;
  final StudyGoal goal;
  final int streakDays;

  @override
  Widget build(BuildContext context) {
    final progress = goal.progress;
    final completed = goal.completedCount;
    final total = goal.totalCount;

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
                  color: AppColors.sky.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.flag_rounded,
                  color: AppColors.sky,
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
                      streakDays > 0
                          ? '$completed / $total complete · $streakDays-day streak'
                          : '$completed / $total tasks complete',
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
                      color: AppColors.sky,
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
              color: AppColors.sky,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _GoalChip(label: 'Notes', done: goal.notesDone),
              _GoalChip(label: 'MCQ', done: goal.mcqsDone),
              _GoalChip(label: 'Revision', done: goal.revisionDone),
              _GoalChip(label: 'Test', done: goal.testDone),
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
            color: AppColors.sky,
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
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.25,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: AppColors.sky.withValues(alpha: 0.8),
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
                        color: AppColors.sky.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        item.icon,
                        color: AppColors.sky,
                        size: 20,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(item.progress * 100).toInt()}%',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.sky,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.25,
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
                    color: AppColors.sky,
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
