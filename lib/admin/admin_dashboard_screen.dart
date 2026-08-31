import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/ai_lessons/admin_ai_lessons_screen.dart';
import 'package:mpsc_combine_ai/admin/ai_teacher_content/admin_ai_teacher_content_screen.dart';
import 'package:mpsc_combine_ai/admin/audit/admin_audit_log_screen.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/admin_bulk_upload_hub_screen.dart';
import 'package:mpsc_combine_ai/admin/current_affairs/admin_current_affairs_screen.dart';
import 'package:mpsc_combine_ai/admin/faculty/admin_faculty_screen.dart';
import 'package:mpsc_combine_ai/admin/flashcards/admin_flashcards_screen.dart';
import 'package:mpsc_combine_ai/admin/jobs/admin_job_alerts_screen.dart';
import 'package:mpsc_combine_ai/admin/live_classes/admin_live_class_attendance_screen.dart';
import 'package:mpsc_combine_ai/admin/live_classes/admin_live_class_recordings_screen.dart';
import 'package:mpsc_combine_ai/admin/live_classes/admin_live_classes_screen.dart';
import 'package:mpsc_combine_ai/admin/mcqs/admin_mcqs_screen.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_notes_screen.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_subjects_screen.dart';
import 'package:mpsc_combine_ai/admin/notifications/admin_notifications_screen.dart';
import 'package:mpsc_combine_ai/admin/pyqs/admin_pyqs_screen.dart';
import 'package:mpsc_combine_ai/admin/rag/admin_rag_sources_screen.dart';
import 'package:mpsc_combine_ai/admin/seed/mpsc_curriculum_seeder.dart';
import 'package:mpsc_combine_ai/admin/seed/sample_content_seeder.dart';
import 'package:mpsc_combine_ai/admin/smart_tricks/admin_smart_tricks_screen.dart';
import 'package:mpsc_combine_ai/admin/students/admin_students_screen.dart';
import 'package:mpsc_combine_ai/admin/teaching_slides/admin_teaching_slides_screen.dart';
import 'package:mpsc_combine_ai/admin/tests/admin_tests_screen.dart';
import 'package:mpsc_combine_ai/admin/videos/admin_videos_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/models/audit_log_item.dart';
import 'package:mpsc_combine_ai/services/admin_dashboard_stats_repository.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/date_format.dart';

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

  Future<void> _importMpscStructureOnly() async {
    setState(() => _isSeeding = true);
    try {
      final summary = await seedMpscCurriculumStructure();
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
          FutureBuilder<DashboardStats>(
            future: adminDashboardStatsRepository.load(),
            builder: (context, snapshot) {
              final stats = snapshot.data ?? DashboardStats.empty;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _StatCard(label: 'Total Students', value: '${stats.totalStudents}', icon: Icons.people_rounded),
                  _StatCard(label: 'Active Students', value: '${stats.activeStudents}', icon: Icons.bolt_rounded),
                  _StatCard(
                    label: 'Revenue',
                    value: '₹${stats.revenue.toStringAsFixed(0)}',
                    icon: Icons.currency_rupee_rounded,
                  ),
                  _StatCard(label: 'Courses', value: '${stats.courses}', icon: Icons.menu_book_rounded),
                  _StatCard(
                    label: 'Live Classes',
                    value: '${stats.liveClassesUpcoming}',
                    icon: Icons.live_tv_rounded,
                  ),
                  _StatCard(
                    label: 'AI Teacher Usage',
                    value: '${stats.aiTeacherUsage}',
                    icon: Icons.psychology_rounded,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const Text('Recent Activity', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          StreamBuilder<List<AuditLogItem>>(
            stream: auditLogRepository.watchRecent(limit: 6),
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <AuditLogItem>[];
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No admin activity yet.', style: TextStyle(color: AppColors.textSecondary)),
                );
              }
              return Card(
                child: Column(
                  children: [
                    for (final item in items)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.history_rounded, color: AppColors.navy),
                        title: Text('${item.action} · ${item.module}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(item.targetLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text(
                          formatFriendlyDateTime(item.createdAt),
                          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const AdminAuditLogScreen()),
                        ),
                        child: const Text('View full audit log'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              AdminModuleCard(
                title: 'Content Index',
                subtitle: 'Exam → Subject → Chapter → Topic',
                icon: Icons.account_tree_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminSubjectsScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'Notes',
                subtitle: 'PDF-first notes · draft → publish · RAG',
                icon: Icons.picture_as_pdf_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminNotesScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'MCQs',
                subtitle: 'Practice sets · draft → publish · AI drafts',
                icon: Icons.quiz_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminMcqsScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'Flashcards',
                subtitle: 'Front/back cards · draft → publish · AI drafts',
                icon: Icons.style_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminFlashcardsScreen(),
                  ),
                ),
              ),
              AdminModuleCard(
                title: 'Smart Tricks',
                subtitle: 'Memory tricks · draft → publish · AI drafts',
                icon: Icons.psychology_alt_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminSmartTricksScreen(),
                  ),
                ),
              ),
              AdminModuleCard(
                title: 'Tests',
                subtitle: 'Mock tests · duration, marks, publish',
                icon: Icons.assignment_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminTestsScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'Current Affairs',
                subtitle: 'Daily/weekly updates · draft → publish',
                icon: Icons.newspaper_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminCurrentAffairsScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'Job Alerts',
                subtitle: 'Recruitment / exam notices',
                icon: Icons.work_outline_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminJobAlertsScreen(),
                  ),
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
                subtitle: 'Create, schedule, edit & delete',
                icon: Icons.live_tv_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminLiveClassesScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'Faculty',
                subtitle: 'Instructors for live classes',
                icon: Icons.person_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminFacultyScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'Attendance',
                subtitle: 'Who joined each live class',
                icon: Icons.fact_check_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminLiveClassAttendanceScreen(),
                  ),
                ),
              ),
              AdminModuleCard(
                title: 'Recordings',
                subtitle: 'Recorded live class links',
                icon: Icons.smart_display_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminLiveClassRecordingsScreen(),
                  ),
                ),
              ),
              AdminModuleCard(
                title: 'PYQs',
                subtitle: 'Previous year questions · import · publish',
                icon: Icons.history_edu_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminPyqsScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'RAG Management',
                subtitle: 'Content → index, re-index, test retrieval',
                icon: Icons.auto_stories_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminRagSourcesScreen(),
                  ),
                ),
              ),
              AdminModuleCard(
                title: 'Teaching Slides',
                subtitle: 'Slide decks for chapters',
                icon: Icons.slideshow_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminTeachingSlidesScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'AI Classroom Lessons',
                subtitle: 'Generate, monitor, regenerate, delete assets',
                icon: Icons.smart_display_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminAiLessonsScreen(),
                  ),
                ),
              ),
              AdminModuleCard(
                title: 'AI Teacher Content',
                subtitle: 'Authored lessons · review · publish',
                icon: Icons.co_present_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminAiTeacherContentScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'Students',
                subtitle: 'Analytics, block, assign courses',
                icon: Icons.people_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminStudentsScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'Notifications',
                subtitle: 'Send to all or selected students',
                icon: Icons.campaign_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminNotificationsScreen()),
                ),
              ),
              AdminModuleCard(
                title: 'Bulk Upload',
                subtitle: 'Import MCQ / PYQ / Flashcard / Trick as DRAFT',
                icon: Icons.file_upload_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminBulkUploadHubScreen(),
                  ),
                ),
              ),
              AdminModuleCard(
                title: 'Audit Log',
                subtitle: 'Every admin action, tracked',
                icon: Icons.receipt_long_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminAuditLogScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _isSeeding ? null : _importMpscStructureOnly,
            icon: _isSeeding
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.account_tree_rounded),
            label: Text(_isSeeding ? 'Importing…' : 'Import MPSC structure'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Idempotent: creates all 10 subjects + every topic (chapters) by slug. '
            'Does not wipe Admin PDF/summary content on existing topics.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isSeeding ? null : _importSampleContent,
            icon: _isSeeding
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_rounded),
            label: Text(_isSeeding ? 'Importing…' : 'Import MPSC structure + samples'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Full curriculum + starter MCQ/Test/CA/Video/PYQ samples for empty collections. '
            'Safe to run multiple times.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.orange, size: 20),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.navy)),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}
