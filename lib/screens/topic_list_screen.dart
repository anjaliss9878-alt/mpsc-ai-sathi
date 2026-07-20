import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/screens/notes_detail_screen.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';
import 'package:mpsc_combine_ai/widgets/notes_widgets.dart';

class TopicListScreen extends StatelessWidget {
  const TopicListScreen({super.key, required this.subject});

  final SubjectItem subject;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NotesAppBar(title: subject.title),
      body: StreamBuilder<List<ChapterItem>>(
        stream: notesRepository.watchChapters(subject.id),
        builder: (context, snapshot) {
          final chapters = snapshot.data ?? const <ChapterItem>[];
          return ResponsiveScrollView(
            children: [
              NotesHeaderCard(
                icon: subject.icon,
                title: subject.title,
                description: subject.subtitle,
                trailing: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'एकूण ${chapters.length} अध्याय',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const NotesSectionTitle(title: 'अध्याय निवडा'),
              const SizedBox(height: 12),
              if (snapshot.hasError)
                const ErrorState(
                  message: 'अध्याय लोड करता आले नाहीत.\n(Could not load chapters.)',
                )
              else if (!snapshot.hasData)
                const LoadingState()
              else if (chapters.isEmpty)
                const EmptyState(
                  message: 'या विषयासाठी अजून अध्याय जोडलेले नाहीत.\n'
                      '(No chapters added yet for this subject.)',
                  icon: Icons.menu_book_outlined,
                )
              else
                ...List.generate(chapters.length, (index) {
                  final chapter = chapters[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: NotesListTile(
                      title: chapter.title,
                      subtitle: 'अध्याय ${index + 1}',
                      leading: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => NotesDetailScreen(
                              subjectTitle: subject.title,
                              chapter: chapter,
                              topicNumber: index + 1,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
