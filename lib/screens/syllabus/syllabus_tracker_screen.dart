import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/screens/notes_detail_screen.dart';
import 'package:mpsc_combine_ai/screens/revision/revision_hub_screen.dart';
import 'package:mpsc_combine_ai/screens/study_planner_screen.dart';
import 'package:mpsc_combine_ai/screens/syllabus/syllabus_subject_screen.dart';
import 'package:mpsc_combine_ai/screens/weakness/ai_weakness_tracker_screen.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Student syllabus dashboard: overall % and per-subject progress.
/// Content comes from published `subjects` + `chapters` (topics).
class SyllabusTrackerScreen extends StatefulWidget {
  const SyllabusTrackerScreen({super.key});

  @override
  State<SyllabusTrackerScreen> createState() => _SyllabusTrackerScreenState();
}

class _SyllabusTrackerScreenState extends State<SyllabusTrackerScreen> {
  late final String? _uid;
  Stream<SyllabusProgressSnapshot>? _stream;
  int _retry = 0;

  @override
  void initState() {
    super.initState();
    final uid = authService.currentUser?.uid;
    _uid = uid;
    _stream = uid == null ? null : syllabusProgressTracker.watch(uid);
  }

  void _reload() {
    final uid = _uid;
    setState(() {
      _retry++;
      if (uid != null) {
        _stream = syllabusProgressTracker.watch(uid);
      }
    });
  }

  String _errorMessage(Object error) {
    final text = '$error'.toLowerCase();
    if (text.contains('permission-denied') || text.contains('permission_denied')) {
      return 'Firebase परवानगी नाकारली. कृपया पुन्हा साइन इन करा.\n(Permission denied.)';
    }
    if (text.contains('unavailable') ||
        text.contains('network') ||
        text.contains('socket') ||
        text.contains('offline')) {
      return 'नेटवर्क उपलब्ध नाही. कनेक्शन तपासून पुन्हा प्रयत्न करा.\n(Network error.)';
    }
    return 'अभ्यासक्रम लोड करता आला नाही.\n$error';
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    return Scaffold(
      appBar: AppBar(title: const Text('अभ्यासक्रम प्रगती')),
      body: uid == null
          ? const ErrorState(message: 'ट्रॅकर वापरण्यासाठी साइन इन करा.')
          : StreamBuilder<StudentProfile?>(
              stream: profileRepository.watchProfile(uid),
              builder: (context, profileSnap) {
                return StreamBuilder<SyllabusProgressSnapshot>(
                  key: ValueKey(_retry),
                  stream: _stream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return ErrorState(
                        message: _errorMessage(snapshot.error!),
                        onRetry: _reload,
                      );
                    }
                    if (!snapshot.hasData) return const LoadingState();
                    final data = snapshot.data!;
                    if (!data.hasSyllabus) {
                      return const EmptyState(
                        icon: Icons.menu_book_outlined,
                        message:
                            'अजून प्रकाशित अभ्यासक्रम नाही.\n'
                            'Admin Panel मधून विषय व टॉपिक Published करा.',
                      );
                    }
                    final exam = profileSnap.data?.targetExam.trim();
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          (exam != null && exam.isNotEmpty) ? exam : 'MPSC Combine',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.navy,
                              ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'विषय → टॉपिक (प्रकाशित Firestore अभ्यासक्रम)',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        _OverallCard(snapshot: data),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const StudyPlannerScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.edit_calendar_rounded),
                          label: const Text('आजचा अभ्यास प्लॅन'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AiWeaknessTrackerScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.insights_rounded),
                          label: const Text('कमकुवत विषय पहा'),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'विषय',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        for (final subject in data.subjects)
                          _SubjectProgressTile(
                            row: subject,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SyllabusSubjectScreen(
                                  subjectId: subject.subject.id,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.snapshot});

  final SyllabusProgressSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final pct = snapshot.overallPercent.clamp(0, 100);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'एकूण अभ्यासक्रम',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                Text(
                  '${pct.round()}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: AppColors.sky,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: snapshot.overallFraction,
                minHeight: 10,
                backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                color: AppColors.sky,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${snapshot.completedTopics} / ${snapshot.totalTopics} टॉपिक पूर्ण · '
              '${snapshot.inProgress.length} सुरू · '
              '${snapshot.pending.length} बाकी',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectProgressTile extends StatelessWidget {
  const _SubjectProgressTile({required this.row, required this.onTap});

  final SyllabusSubjectProgress row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(row.subject.icon, color: AppColors.navy),
        title: Text(
          row.subject.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${row.completedTopics} / ${row.totalTopics} टॉपिक · '
          '${row.percent.round()}% · ${row.statusLabel}',
        ),
        trailing: SizedBox(
          width: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${row.percent.round()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.sky,
                ),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: row.totalTopics == 0 ? 0 : row.completedTopics / row.totalTopics,
                  minHeight: 4,
                  backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                  color: AppColors.sky,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openSyllabusTopicNotes(
  BuildContext context,
  SyllabusTopicProgress topic,
) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NotesDetailScreen(
        subjectTitle: topic.subjectTitle,
        chapter: topic.chapter,
        topicNumber: topic.chapter.order,
      ),
    ),
  );
}

Future<void> openSyllabusRevision(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const RevisionHubScreen()),
  );
}
