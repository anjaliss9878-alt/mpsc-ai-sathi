import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/data/student_curriculum.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/screens/notes_detail_screen.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';
import 'package:mpsc_combine_ai/widgets/notes_widgets.dart';

class TopicListScreen extends StatefulWidget {
  const TopicListScreen({
    super.key,
    required this.subject,
    this.syllabusAreaId = '',
    this.parentChapter,
  });

  final SubjectItem subject;
  final String syllabusAreaId;
  final ChapterItem? parentChapter;

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
          c.titleEn.toLowerCase().contains(q) ||
          syllabusAreaTitle(chapterSyllabusAreaId(c)).toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openChapter(ChapterItem chapter, int topicNumber) async {
    final children = (await notesRepository.getChildChaptersOnce(chapter.id))
        .where((c) => c.published)
        .toList();
    if (!mounted) return;
    if (children.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TopicListScreen(
            subject: widget.subject,
            syllabusAreaId: widget.syllabusAreaId,
            parentChapter: chapter,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotesDetailScreen(
          subjectTitle: widget.syllabusAreaId.isNotEmpty
              ? syllabusAreaTitle(widget.syllabusAreaId)
              : widget.subject.title,
          chapter: chapter,
          topicNumber: topicNumber,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    final parent = widget.parentChapter;
    final showAreas = shouldShowGroupBPrelimsAreaPicker(
      subject: subject,
      syllabusAreaId: widget.syllabusAreaId,
      parentChapterId: parent?.id ?? '',
    );
    final title = parent != null
        ? parent.title
        : (widget.syllabusAreaId.isNotEmpty
            ? syllabusAreaTitle(widget.syllabusAreaId)
            : subject.title);
    return Scaffold(
      appBar: NotesAppBar(title: title),
      body: StreamBuilder<List<ChapterItem>>(
        stream: parent != null
            ? notesRepository.watchChildChapters(parent.id)
            : notesRepository.watchPublishedChapters(subject.id),
        builder: (context, snapshot) {
          final raw = snapshot.data ?? const <ChapterItem>[];
          if (showAreas) {
            if (snapshot.hasError) {
              return const ResponsiveScrollView(
                children: [
                  ErrorState(
                    message:
                        'टॉपिक लोड करता आले नाहीत.\n(Could not load topics.)',
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const ResponsiveScrollView(children: [LoadingState()]);
            }
            return _areaPage(raw);
          }
          final scoped = parent != null
              ? raw.where((c) => c.published).toList()
              : (widget.syllabusAreaId.isNotEmpty
                  ? chaptersForSyllabusArea(raw, widget.syllabusAreaId)
                  : raw);
          if (showAreas && snapshot.hasData) {
            return _areaPage(raw);
          }
          final chapters = _filter(scoped);
          final groups = groupChaptersBySyllabusArea(chapters);
          final showAreaHeaders =
              widget.syllabusAreaId.isEmpty && parent == null && groups.length > 1;
          final showingChapters =
              scoped.isNotEmpty && scoped.every((c) => c.isGroupingChapter);
          return ResponsiveScrollView(
            children: [
              NotesHeaderCard(
                icon: subject.icon,
                title: title,
                description: parent != null
                    ? 'Topics in this chapter'
                    : (widget.syllabusAreaId.isNotEmpty
                        ? subject.title
                        : subject.subtitle),
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
                    showingChapters
                        ? 'एकूण ${scoped.length} अध्याय'
                        : 'एकूण ${scoped.length} टॉपिक',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  hintText: showingChapters
                      ? 'अध्याय शोधा… / Search chapters'
                      : 'टॉपिक शोधा… / Search topics',
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 24),
              NotesSectionTitle(
                title: showingChapters ? 'अध्याय निवडा' : 'टॉपिक निवडा',
              ),
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
              else if (scoped.isEmpty)
                const EmptyState(
                  message:
                      'या विषयासाठी अजून प्रकाशित अध्याय नाहीत.\n'
                      'Admin ने Published केलेले Chapters येथे दिसतील '
                      '(Draft दिसणार नाहीत).\n'
                      '(No published chapters for this subject yet.)',
                  icon: Icons.menu_book_outlined,
                )
              else if (chapters.isEmpty)
                const EmptyState(
                  message: 'शोध निकष जुळले नाहीत.\n(No topics match your search.)',
                  icon: Icons.search_off_rounded,
                )
              else
                ..._chapterTiles(
                  groups: groups,
                  showAreaHeaders: showAreaHeaders,
                  all: scoped,
                  subject: subject,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _areaPage(List<ChapterItem> all) {
    final q = _query.trim().toLowerCase();
    final areas = kGroupBPrelimsAreaIds.where((id) {
      if (q.isEmpty) return true;
      return syllabusAreaTitle(id).toLowerCase().contains(q);
    });
    return ResponsiveScrollView(
      children: [
        NotesHeaderCard(
          icon: widget.subject.icon,
          title: 'General Ability Test',
          description:
              'Select an area. Official Prelims paper remains General Ability Test.',
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(
            hintText: 'क्षेत्र शोधा… / Search areas',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 24),
        const NotesSectionTitle(title: 'विषय / क्षेत्र निवडा'),
        const SizedBox(height: 12),
        for (final areaId in areas)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: NotesListTile(
              title: syllabusAreaTitle(areaId),
              subtitle:
                  '${chaptersForSyllabusArea(all, areaId).length} chapters',
              leading: _numBox(kGroupBPrelimsAreaIds.indexOf(areaId) + 1),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TopicListScreen(
                      subject: widget.subject,
                      syllabusAreaId: areaId,
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  List<Widget> _chapterTiles({
    required List<MapEntry<String, List<ChapterItem>>> groups,
    required bool showAreaHeaders,
    required List<ChapterItem> all,
    required SubjectItem subject,
  }) {
    final out = <Widget>[];
    for (final group in groups) {
      if (showAreaHeaders && group.key.isNotEmpty) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: NotesSectionTitle(title: syllabusAreaTitle(group.key)),
          ),
        );
      }
      for (final chapter in group.value) {
        final minutes = chapter.estimatedStudyMinutes;
        final topicNumber = all.indexOf(chapter) + 1;
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: NotesListTile(
              title: chapter.title,
              subtitle: minutes > 0
                  ? 'अध्याय $topicNumber · ~$minutes मिनिटे'
                  : 'अध्याय $topicNumber',
              leading: _numBox(topicNumber),
              onTap: () => _openChapter(chapter, topicNumber),
            ),
          ),
        );
      }
    }
    return out;
  }

  Widget _numBox(int n) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$n',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
      ),
    );
  }
}
