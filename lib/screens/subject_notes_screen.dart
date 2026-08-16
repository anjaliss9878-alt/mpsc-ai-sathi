import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/screens/topic_list_screen.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';
import 'package:mpsc_combine_ai/widgets/notes_widgets.dart';

/// Student subject list — live Firestore only (`subjects`, `published == true`).
/// Static `subject_notes_data.dart` is Admin seed import only, never used here.
class SubjectNotesScreen extends StatefulWidget {
  const SubjectNotesScreen({super.key});

  @override
  State<SubjectNotesScreen> createState() => _SubjectNotesScreenState();
}

class _SubjectNotesScreenState extends State<SubjectNotesScreen> {
  String _query = '';

  List<SubjectItem> _filter(List<SubjectItem> subjects) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return subjects;
    return subjects.where((s) {
      return s.title.toLowerCase().contains(q) ||
          s.subtitle.toLowerCase().contains(q) ||
          s.nameEn.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const NotesAppBar(title: 'विषयवार नोट्स'),
      body: StreamBuilder<List<SubjectItem>>(
        stream: notesRepository.watchPublishedSubjects(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <SubjectItem>[];
          final subjects = _filter(all);
          return ResponsiveScrollView(
            children: [
              const NotesHeaderCard(
                icon: Icons.library_books_rounded,
                title: 'विषयवार नोट्स',
                description:
                    'MPSC Combine पूर्व परीक्षा आणि मुख्य परीक्षेसाठी विषयनिहाय संरचित नोट्स.',
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'विषय शोधा… / Search subjects',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 24),
              const NotesSectionTitle(title: 'विषय निवडा'),
              const SizedBox(height: 12),
              if (snapshot.hasError)
                ErrorState(
                  message:
                      'विषय लोड करता आले नाहीत.\n'
                      '(Could not load subjects.)\n'
                      '${snapshot.error}',
                )
              else if (!snapshot.hasData)
                const LoadingState()
              else if (all.isEmpty)
                const EmptyState(
                  message:
                      'अजून प्रकाशित विषय नाहीत.\n'
                      'Admin Panel मधून Subject तयार करा आणि Published करा — '
                      'ते येथे लगेच दिसतील.\n'
                      '(No published subjects yet.)',
                  icon: Icons.library_books_outlined,
                )
              else if (subjects.isEmpty)
                const EmptyState(
                  message: 'शोध निकष जुळले नाहीत.\n(No subjects match your search.)',
                  icon: Icons.search_off_rounded,
                )
              else
                ...subjects.map(
                  (subject) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: NotesListTile(
                      title: subject.title,
                      subtitle: subject.subtitle,
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          subject.icon,
                          color: AppColors.navy,
                          size: 22,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => TopicListScreen(subject: subject),
                          ),
                        );
                      },
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
