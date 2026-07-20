import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/screens/topic_list_screen.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';
import 'package:mpsc_combine_ai/widgets/notes_widgets.dart';

class SubjectNotesScreen extends StatelessWidget {
  const SubjectNotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const NotesAppBar(title: 'विषयवार नोट्स'),
      body: StreamBuilder<List<SubjectItem>>(
        stream: notesRepository.watchSubjects(),
        builder: (context, snapshot) {
          return ResponsiveScrollView(
            children: [
              const NotesHeaderCard(
                icon: Icons.library_books_rounded,
                title: 'विषयवार नोट्स',
                description:
                    'MPSC Combine पूर्व परीक्षा आणि मुख्य परीक्षेसाठी विषयनिहाय संरचित नोट्स.',
              ),
              const SizedBox(height: 24),
              const NotesSectionTitle(title: 'विषय निवडा'),
              const SizedBox(height: 12),
              if (snapshot.hasError)
                ErrorState(
                  message: 'विषय लोड करता आले नाहीत.\n(Could not load subjects.)',
                )
              else if (!snapshot.hasData)
                const LoadingState()
              else if (snapshot.data!.isEmpty)
                const EmptyState(
                  message: 'अजून कोणतेही विषय जोडले नाहीत.\n'
                      '(No subjects added yet.)',
                  icon: Icons.library_books_outlined,
                )
              else
                ...snapshot.data!.map(
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
