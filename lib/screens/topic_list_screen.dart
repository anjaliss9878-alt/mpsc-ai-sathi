import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/screens/notes_detail_screen.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';
import 'package:mpsc_combine_ai/widgets/notes_widgets.dart';

class TopicListScreen extends StatefulWidget {
  const TopicListScreen({super.key, required this.subject});

  final SubjectItem subject;

  @override
  State<TopicListScreen> createState() => _TopicListScreenState();
}

class _TopicListScreenState extends State<TopicListScreen> {
  String _query = '';

  List<ChapterItem> _filter(List<ChapterItem> chapters) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return chapters;
    return chapters.where((c) {
      return c.title.toLowerCase().contains(q) ||
          c.description.toLowerCase().contains(q) ||
          c.titleEn.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    return Scaffold(
      appBar: NotesAppBar(title: subject.title),
      body: StreamBuilder<List<ChapterItem>>(
        stream: notesRepository.watchPublishedChapters(subject.id),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <ChapterItem>[];
          final chapters = _filter(all);
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
                    'एकूण ${all.length} टॉपिक',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'टॉपिक शोधा… / Search topics',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 24),
              const NotesSectionTitle(title: 'टॉपिक निवडा'),
              const SizedBox(height: 12),
              if (snapshot.hasError)
                ErrorState(
                  message:
                      'टॉपिक लोड करता आले नाहीत.\n'
                      '(Could not load topics.)\n'
                      '${snapshot.error}',
                )
              else if (!snapshot.hasData)
                const LoadingState()
              else if (all.isEmpty)
                const EmptyState(
                  message:
                      'या विषयासाठी अजून प्रकाशित टॉपिक नाहीत.\n'
                      'Admin ने Published केलेले Topics येथे लगेच दिसतील '
                      '(Draft दिसणार नाहीत).\n'
                      '(No published topics for this subject yet.)',
                  icon: Icons.menu_book_outlined,
                )
              else if (chapters.isEmpty)
                const EmptyState(
                  message: 'शोध निकष जुळले नाहीत.\n(No topics match your search.)',
                  icon: Icons.search_off_rounded,
                )
              else
                ...List.generate(chapters.length, (index) {
                  final chapter = chapters[index];
                  final minutes = chapter.estimatedStudyMinutes;
                  // Keep original topic number from the full published list.
                  final topicNumber = all.indexOf(chapter) + 1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: NotesListTile(
                      title: chapter.title,
                      subtitle: minutes > 0
                          ? 'टॉपिक $topicNumber · ~$minutes मिनिटे'
                          : 'टॉपिक $topicNumber',
                      leading: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$topicNumber',
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
                              topicNumber: topicNumber,
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
