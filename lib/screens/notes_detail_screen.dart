import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';
import 'package:mpsc_combine_ai/widgets/notes_widgets.dart';

class NotesDetailScreen extends StatelessWidget {
  const NotesDetailScreen({
    super.key,
    required this.subjectTitle,
    required this.chapter,
    required this.topicNumber,
  });

  final String subjectTitle;
  final ChapterItem chapter;
  final int topicNumber;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NotesAppBar(title: subjectTitle),
      body: StreamBuilder<NoteItem?>(
        stream: notesRepository.watchNoteForChapter(chapter.id),
        builder: (context, snapshot) {
          final notes = snapshot.data;
          return ResponsiveScrollView(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'अध्याय $topicNumber',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: AppColors.orange,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        chapter.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              height: 1.3,
                            ),
                      ),
                      if (snapshot.hasData && notes == null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'या विषयाच्या सविस्तर नोट्स लवकरच उपलब्ध होतील.\n'
                          '(Detailed notes for this chapter will be available soon.)',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.5,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (snapshot.hasError)
                const ErrorState(
                  message: 'नोट्स लोड करता आल्या नाहीत.\n(Could not load notes.)',
                )
              else if (!snapshot.hasData && notes == null)
                const LoadingState()
              else if (notes != null) ...[
                _ContentSection(
                  title: 'महत्त्वाचे मुद्दे',
                  icon: Icons.star_rounded,
                  points: notes.importantPoints,
                ),
                const SizedBox(height: 16),
                _ContentSection(
                  title: 'पुनरावलोकन सारांश',
                  icon: Icons.summarize_rounded,
                  points: notes.revisionSummary,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ContentSection extends StatelessWidget {
  const _ContentSection({
    required this.title,
    required this.icon,
    required this.points,
  });

  final String title;
  final IconData icon;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.navy, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...points.map(
              (point) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 7),
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        point,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.45,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
