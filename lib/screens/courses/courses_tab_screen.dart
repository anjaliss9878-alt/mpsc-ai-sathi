import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/continue_session.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/ai_teacher_classroom_screen.dart'
    deferred as ai_classroom;
import 'package:mpsc_combine_ai/screens/certificates/certificates_screen.dart';
import 'package:mpsc_combine_ai/screens/subject_notes_screen.dart';
import 'package:mpsc_combine_ai/screens/topic_list_screen.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Courses tab: enrolled/assigned subjects, continue learning, certificates.
class CoursesTabScreen extends StatelessWidget {
  const CoursesTabScreen({super.key});

  Future<void> _openClassroom(BuildContext context) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.orange),
      ),
    );
    try {
      await ai_classroom.loadLibrary();
      if (!context.mounted) return;
      Navigator.of(context).pop();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ai_classroom.AiTeacherClassroomScreen(),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Classroom उघडता आला नाही. कृपया पुन्हा प्रयत्न करा.')),
      );
    }
  }

  Future<void> _openContinue(BuildContext context, ContinueSession session) async {
    switch (session.type) {
      case 'classroom':
        await _openClassroom(context);
        return;
      case 'notes':
      case 'chapter':
        final chapterId = session.payload['chapterId'] as String? ?? session.id;
        final subjectId = session.payload['subjectId'] as String? ?? '';
        final chapter = await notesRepository.getChapter(chapterId);
        final subject = subjectId.isNotEmpty
            ? await notesRepository.getSubject(subjectId)
            : null;
        if (!context.mounted) return;
        if (chapter == null) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SubjectNotesScreen()),
          );
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TopicListScreen(
              subject: subject ??
                  SubjectItem(
                    id: chapter.subjectId,
                    title: session.title,
                    subtitle: session.subtitle,
                    iconName: 'menu_book',
                    order: 0,
                  ),
            ),
          ),
        );
        return;
      default:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SubjectNotesScreen()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = authService.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Courses'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Certificates',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CertificatesScreen()),
            ),
            icon: const Icon(Icons.workspace_premium_rounded),
          ),
        ],
      ),
      body: uid == null
          ? const Center(child: Text('Sign in to see your courses.'))
          : StreamBuilder<StudentProfile?>(
              stream: profileRepository.watchProfile(uid),
              builder: (context, profileSnap) {
                final profile = profileSnap.data;
                return StreamBuilder<List<SubjectItem>>(
                  stream: notesRepository.watchPublishedSubjects(),
                  builder: (context, subjectsSnap) {
                    if (subjectsSnap.hasError) {
                      return ErrorState(
                        message: 'Could not load courses.\n${subjectsSnap.error}',
                      );
                    }
                    if (!subjectsSnap.hasData) {
                      return const LoadingState();
                    }
                    // Always show every published subject from Firestore so
                    // Admin-created subjects appear immediately. Enrollment
                    // (`assignedSubjectIds`) only sorts enrolled ones first.
                    final allPublished = subjectsSnap.data!;
                    final assigned = profile?.assignedSubjectIds ?? const [];
                    final assignedSet = assigned.toSet();
                    final subjects = [
                      ...allPublished.where((s) => assignedSet.contains(s.id)),
                      ...allPublished.where((s) => !assignedSet.contains(s.id)),
                    ];

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          assigned.isEmpty
                              ? 'All courses'
                              : 'Your courses',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        if (subjects.isEmpty)
                          const EmptyState(
                            message:
                                'अजून प्रकाशित विषय नाहीत.\n'
                                'Admin ने Published केलेले Subjects येथे दिसतील.\n'
                                '(No published subjects yet.)',
                            icon: Icons.menu_book_outlined,
                          )
                        else
                          ...subjects.map(
                            (s) {
                              final enrolled = assignedSet.contains(s.id);
                              return Card(
                                child: ListTile(
                                  leading: Icon(s.icon, color: AppColors.navy),
                                  title: Text(
                                    s.title,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    [
                                      if (enrolled && assigned.isNotEmpty) 'Enrolled',
                                      if (s.subtitle.isNotEmpty)
                                        s.subtitle
                                      else
                                        'Continue learning',
                                    ].join(' · '),
                                  ),
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppColors.orange,
                                  ),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => TopicListScreen(subject: s),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        const SizedBox(height: 20),
                        Text(
                          'Continue learning',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        StreamBuilder<List<ContinueSession>>(
                          stream: studentProgressRepository.watchContinueSessions(uid),
                          builder: (context, contSnap) {
                            final sessions = contSnap.data ?? const <ContinueSession>[];
                            if (sessions.isEmpty) {
                              return Card(
                                child: ListTile(
                                  leading: const Icon(Icons.play_circle_outline),
                                  title: const Text('Start a chapter to resume later'),
                                  subtitle: const Text('Progress syncs after you study'),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const SubjectNotesScreen(),
                                    ),
                                  ),
                                ),
                              );
                            }
                            return Column(
                              children: sessions.take(8).map((s) {
                                return Card(
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.play_arrow_rounded,
                                      color: AppColors.orange,
                                    ),
                                    title: Text(s.title),
                                    subtitle: Text(
                                      '${s.subtitle} · ${(s.progress * 100).toInt()}%',
                                    ),
                                    onTap: () => _openContinue(context, s),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const CertificatesScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.workspace_premium_outlined),
                          label: const Text('View certificates'),
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
