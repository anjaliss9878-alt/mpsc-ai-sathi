import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/current_affairs/admin_current_affairs_screen.dart';
import 'package:mpsc_combine_ai/admin/live_classes/admin_live_classes_screen.dart';
import 'package:mpsc_combine_ai/admin/mcqs/admin_mcqs_screen.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_subjects_screen.dart';
import 'package:mpsc_combine_ai/admin/pyqs/admin_pyqs_screen.dart';
import 'package:mpsc_combine_ai/admin/seed/sample_content_seeder.dart';
import 'package:mpsc_combine_ai/admin/tests/admin_tests_screen.dart';
import 'package:mpsc_combine_ai/admin/videos/admin_videos_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _isSeeding = false;

  Future<void> _importSampleContent() async {
    setState(() => _isSeeding = true);
    try {
      final summary = await seedSampleContent();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(summary)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = authService.currentUser?.email ?? '';

    return AdminScaffold(
      title: 'Admin Dashboard',
      actions: [
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout_rounded),
          onPressed: () => authService.signOut(),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.verified_user_rounded, color: AppColors.navy),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Signed in as',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        Text(
                          email,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              AdminModuleCard(
                title: 'Notes',
                subtitle: 'Subjects, chapters & notes',
                icon: Icons.library_books_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminSubjectsScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'MCQs',
                subtitle: 'Practice questions & sets',
                icon: Icons.quiz_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminMcqsScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'Tests',
                subtitle: 'Mock tests / CBT papers',
                icon: Icons.assignment_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminTestsScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'Current Affairs',
                subtitle: 'Daily/weekly updates',
                icon: Icons.newspaper_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminCurrentAffairsScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'Videos',
                subtitle: 'Lecture / concept videos',
                icon: Icons.smart_display_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminVideosScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'Live Classes',
                subtitle: 'Scheduled & recorded sessions',
                icon: Icons.live_tv_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminLiveClassesScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'PYQs',
                subtitle: 'Previous year question papers',
                icon: Icons.history_edu_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminPyqsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _isSeeding ? null : _importSampleContent,
            icon: _isSeeding
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_rounded),
            label: Text(_isSeeding ? 'Importing…' : 'Import Sample Content'),
          ),
          const SizedBox(height: 8),
          const Text(
            'One-time helper that seeds each content type with a starter example '
            'so the student app and this dashboard are not empty. Safe to run '
            'multiple times — it skips a collection if it already has data.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
