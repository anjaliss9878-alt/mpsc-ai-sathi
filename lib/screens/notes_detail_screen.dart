import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/teaching_slide_deck_item.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/ai_teacher_classroom_screen.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/ai_lesson_studio.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/link_launcher.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/teaching_slide_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/student_media.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';
import 'package:mpsc_combine_ai/widgets/lesson_video_player.dart';
import 'package:mpsc_combine_ai/widgets/notes_widgets.dart';
import 'package:mpsc_combine_ai/widgets/storage_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mpsc_combine_ai/widgets/teaching_slide_viewer.dart';
import 'package:mpsc_combine_ai/widgets/topic_pdf_viewer.dart';

class NotesDetailScreen extends StatefulWidget {
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
  State<NotesDetailScreen> createState() => _NotesDetailScreenState();
}

class _NotesDetailScreenState extends State<NotesDetailScreen> {
  @override
  void initState() {
    super.initState();
    _trackOpen();
  }

  Future<void> _trackOpen() async {
    final uid = authService.currentUser?.uid;
    if (uid == null) return;
    try {
      await studentProgressRepository.markGoalTask(
        uid: uid,
        task: 'notes',
        done: true,
        sessionType: 'notes',
        sessionTitle: widget.chapter.title,
      );
      await studentProgressRepository.upsertContinueSession(
        uid: uid,
        id: 'chapter_${widget.chapter.id}',
        type: 'notes',
        title: widget.chapter.title,
        subtitle: widget.subjectTitle,
        progress: 0.35,
        payload: {
          'chapterId': widget.chapter.id,
          'subjectId': widget.chapter.subjectId,
        },
      );
    } catch (_) {}
  }

  Future<void> _toggleBookmark() async {
    final uid = authService.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('साइन इन करा आणि बुकमार्क जतन करा.')),
      );
      return;
    }
    try {
      await studentProgressRepository.toggleBookmark(
        uid: uid,
        id: 'chapter_${widget.chapter.id}',
        type: 'note',
        title: widget.chapter.title,
        subtitle: widget.subjectTitle,
        refId: widget.chapter.id,
        meta: {'subjectId': widget.chapter.subjectId},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('बुकमार्क अपडेट झाले.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('बुकमार्क जतन करता आला नाही. कृपया पुन्हा प्रयत्न करा.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = authService.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: NotesAppBar(
        title: widget.chapter.title,
        actions: [
          IconButton(
            tooltip: 'शेअर',
            onPressed: () {
              SharePlus.instance.share(
                ShareParams(
                  text: '${widget.chapter.title}\n${widget.subjectTitle}',
                  subject: widget.chapter.title,
                ),
              );
            },
            icon: const Icon(Icons.share_outlined),
          ),
          if (uid != null)
            StreamBuilder<bool>(
              stream: studentProgressRepository.watchIsBookmarked(
                uid,
                'chapter_${widget.chapter.id}',
              ),
              builder: (context, snapshot) {
                final bookmarked = snapshot.data ?? false;
                return IconButton(
                  tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark',
                  onPressed: _toggleBookmark,
                  icon: Icon(
                    bookmarked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                  ),
                );
              },
            ),
        ],
      ),
      body: StreamBuilder<NoteItem?>(
        stream: notesRepository.watchPublishedNoteForChapter(widget.chapter.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorState(
              message: 'नोट्स लोड करता आल्या नाहीत.\n(Could not load notes.)',
            );
          }
          // NoteItem? streams emit `null` when no note exists yet. AsyncSnapshot
          // treats null as !hasData, so gate Loading on connectionState only.
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingState();
          }

          final notes = snapshot.data;
          final chapter = widget.chapter;
          final pdfs = <NoteAttachment>[
            ...?notes?.attachments.where((a) => a.type == 'pdf' && a.url.trim().isNotEmpty),
            if ((notes?.pdfUrl ?? '').trim().isNotEmpty &&
                !(notes?.attachments.any((a) => a.url == notes.pdfUrl) ?? false))
              NoteAttachment(
                name: 'PDF Notes',
                url: notes!.pdfUrl.trim(),
                type: 'pdf',
              ),
            if (chapter.pdfUrl.isNotEmpty &&
                chapter.pdfUrl != notes?.pdfUrl &&
                !(notes?.attachments.any((a) => a.url == chapter.pdfUrl) ?? false))
              NoteAttachment(name: 'PDF Notes', url: chapter.pdfUrl, type: 'pdf'),
          ];
          final primaryPdf = pdfs.isNotEmpty ? pdfs.first : null;
          final extraPdfs = pdfs.length > 1 ? pdfs.skip(1).toList() : const <NoteAttachment>[];
          final images = [
            ...?notes?.attachments.where((a) => a.type == 'image' && a.url.trim().isNotEmpty),
            ...?notes?.imageUrls
                .where((u) =>
                    u.trim().isNotEmpty &&
                    !(notes.attachments.any((a) => a.url == u)))
                .map((u) => NoteAttachment(name: 'Image', url: u, type: 'image')),
          ];
          final videoFromNote = notes?.videoUrl.trim() ?? '';
          String videoUrl = videoFromNote;
          if (videoUrl.isEmpty && notes != null) {
            for (final a in notes.attachments) {
              if (a.type == 'video' && a.url.trim().isNotEmpty) {
                videoUrl = a.url.trim();
                break;
              }
            }
          }
          final otherFiles = notes?.attachments
                  .where((a) =>
                      a.type != 'pdf' &&
                      a.type != 'image' &&
                      a.type != 'video' &&
                      a.url.trim().isNotEmpty)
                  .toList() ??
              const [];
          final aiSummary = notes?.aiSummary.trim().isNotEmpty == true
              ? notes!.aiSummary.trim()
              : chapter.aiSummary.trim();
          final revisionExtra = chapter.revisionNotes.trim();
          final updatedAt = notes?.updatedAt ?? chapter.updatedAt;

          return ResponsiveScrollView(
            children: [
              _ChapterHero(
                chapter: widget.chapter,
                topicNumber: widget.topicNumber,
                title: (notes?.title.trim().isNotEmpty == true)
                    ? notes!.title.trim()
                    : widget.chapter.title,
                subtitle: widget.subjectTitle,
                updatedAt: updatedAt,
              ),
              if (widget.chapter.description.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  widget.chapter.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                ),
              ],
              if (notes == null &&
                  aiSummary.isEmpty &&
                  pdfs.isEmpty &&
                  videoUrl.isEmpty &&
                  revisionExtra.isEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Detailed notes for this topic will be available soon.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.5),
                ),
              ],
              const SizedBox(height: 16),
              _ChapterAiActions(
                chapter: widget.chapter,
                subjectTitle: widget.subjectTitle,
              ),
              if (aiSummary.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI सारांश',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 10),
                        MarkdownBody(data: aiSummary, selectable: true),
                      ],
                    ),
                  ),
                ),
              ],
              if (revisionExtra.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Revision Notes',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(revisionExtra, style: const TextStyle(height: 1.45)),
                      ],
                    ),
                  ),
                ),
              ],
              if (notes != null || pdfs.isNotEmpty || videoUrl.isNotEmpty) ...[
                const SizedBox(height: 16),
                if (primaryPdf != null) ...[
                  TopicPdfViewer(
                    url: primaryPdf.url,
                    fileName: primaryPdf.name,
                    title: 'PDF Notes',
                    height: 220,
                  ),
                  for (final extra in extraPdfs) ...[
                    const SizedBox(height: 12),
                    TopicPdfViewer(
                      url: extra.url,
                      fileName: extra.name,
                      title: 'More notes',
                      height: 180,
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
                if (videoUrl.isNotEmpty) ...[
                  LessonVideoPlayer(
                    source: videoUrl,
                    progressId: 'note_${widget.chapter.id}',
                    title: widget.chapter.title,
                    subjectTitle: widget.subjectTitle,
                    thumbnailUrl: widget.chapter.thumbnailUrl,
                  ),
                  const SizedBox(height: 16),
                ],
                // 2. Rich text notes (optional secondary)
                if (notes != null && notes.contentMarkdown.trim().isNotEmpty)
                  _MarkdownSection(markdown: notes.contentMarkdown),
                if (notes != null && notes.importantPoints.isNotEmpty) ...[
                  if (notes.contentMarkdown.trim().isNotEmpty) const SizedBox(height: 16),
                  _ContentSection(
                    title: 'महत्त्वाचे मुद्दे',
                    icon: Icons.star_rounded,
                    points: notes.importantPoints,
                  ),
                ],
                // 3. Images
                if (images.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _ImagesSection(images: images),
                ],
                if (otherFiles.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _OtherFilesSection(files: otherFiles),
                ],
                // Keywords
                if (notes != null && notes.keywords.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Keywords',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: notes.keywords
                                .map(
                                  (k) => Chip(
                                    label: Text(k),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                // 4. Summary
                if (notes != null && notes.revisionSummary.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _ContentSection(
                    title: 'पुनरावलोकन सारांश',
                    icon: Icons.summarize_rounded,
                    points: notes.revisionSummary,
                  ),
                ],
                // Chapter-authored MCQs
                if (notes != null && notes.mcqs.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _ChapterMcqsSection(mcqs: notes.mcqs),
                ],
              ],
              // Related subject MCQs (from MCQ Practice sets)
              const SizedBox(height: 16),
              _RelatedMcqsSection(
                subjectTitle: widget.subjectTitle,
                subjectId: widget.chapter.subjectId,
                chapterId: widget.chapter.id,
              ),
              const SizedBox(height: 16),
              StreamBuilder<TeachingSlideDeckItem?>(
                stream: teachingSlideRepository.watchForChapter(widget.chapter.id),
                builder: (context, slideSnapshot) {
                  final deck = slideSnapshot.data;
                  if (deck == null || deck.slides.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.slideshow_rounded, color: AppColors.orange),
                      title: const Text(
                        'शिक्षण स्लाइड्स पहा (View Teaching Slides)',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text('${deck.slides.length} slides'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showTeachingSlideViewer(
                        context,
                        title: deck.title,
                        slides: deck.slides,
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MarkdownSection extends StatelessWidget {
  const _MarkdownSection({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'नोट्स',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 12),
            MarkdownBody(data: markdown, selectable: true),
          ],
        ),
      ),
    );
  }
}

class _ImagesSection extends StatelessWidget {
  const _ImagesSection({required this.images});

  final List<NoteAttachment> images;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Images',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 12),
            ...images.map(
              (img) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: StorageImage(
                        storedUrl: img.url,
                        fit: BoxFit.contain,
                        height: 180,
                      ),
                    ),
                    if (friendlyAttachmentName(img.name, fallback: '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        friendlyAttachmentName(img.name, fallback: 'Image'),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
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

class _ChapterHero extends StatelessWidget {
  const _ChapterHero({
    required this.chapter,
    required this.topicNumber,
    required this.title,
    required this.subtitle,
    this.updatedAt,
  });

  final ChapterItem chapter;
  final int topicNumber;
  final String title;
  final String subtitle;
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    final thumb = chapter.thumbnailUrl.trim();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumb.isNotEmpty)
                  StorageImage(storedUrl: thumb, fit: BoxFit.cover)
                else
                  const ColoredBox(color: AppColors.navy),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x33071530), Color(0xE60A1F44)],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.orange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Topic $topicNumber',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (updatedAt != null)
            ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Text(
                  'Updated ${updatedAt!.day.toString().padLeft(2, '0')}/'
                  '${updatedAt!.month.toString().padLeft(2, '0')}/'
                  '${updatedAt!.year}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OtherFilesSection extends StatelessWidget {
  const _OtherFilesSection({required this.files});

  final List<NoteAttachment> files;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'इतर फाईल्स',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
            ),
            ...files.map(
              (f) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_rounded, color: AppColors.navy),
                title: Text(
                  friendlyAttachmentName(f.name, fallback: 'Document'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => openExternalLink(context, f.url),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterMcqsSection extends StatefulWidget {
  const _ChapterMcqsSection({required this.mcqs});

  final List<NoteMcq> mcqs;

  @override
  State<_ChapterMcqsSection> createState() => _ChapterMcqsSectionState();
}

class _ChapterMcqsSectionState extends State<_ChapterMcqsSection> {
  final Map<int, int?> _selected = {};
  final Set<int> _revealed = {};

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MCQs (${widget.mcqs.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 12),
            ...List.generate(widget.mcqs.length, (qi) {
              final mcq = widget.mcqs[qi];
              final selected = _selected[qi];
              final revealed = _revealed.contains(qi);
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${qi + 1}. ${mcq.question}',
                      style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(mcq.options.length, (oi) {
                      final isCorrect = oi == mcq.correctIndex;
                      final isSelected = selected == oi;
                      Color? color;
                      if (revealed && isCorrect) color = Colors.green;
                      if (revealed && isSelected && !isCorrect) color = Colors.red;
                      return RadioListTile<int>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: oi,
                        groupValue: selected,
                        title: Text(
                          mcq.options[oi],
                          style: TextStyle(color: color, fontWeight: revealed && isCorrect ? FontWeight.w700 : null),
                        ),
                        onChanged: revealed
                            ? null
                            : (v) => setState(() {
                                  _selected[qi] = v;
                                  _revealed.add(qi);
                                }),
                      );
                    }),
                    if (revealed && mcq.explanation.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          mcq.explanation,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _RelatedMcqsSection extends StatelessWidget {
  const _RelatedMcqsSection({
    required this.subjectTitle,
    required this.subjectId,
    required this.chapterId,
  });

  final String subjectTitle;
  final String subjectId;
  final String chapterId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<McqItem>>(
      stream: mcqRepository.watchAll(),
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final all = snapshot.data!.where((q) => q.published).toList();
        final byChapter = all.where((q) => q.chapterId == chapterId).toList();
        final bySubjectId = all.where((q) => q.subjectId == subjectId).toList();
        final byName = all.where((q) {
          final needle = subjectTitle.trim().toLowerCase();
          if (needle.isEmpty) return false;
          final s = q.subject.trim().toLowerCase();
          return s == needle || s.contains(needle) || needle.contains(s);
        }).toList();
        final mcqs = byChapter.isNotEmpty
            ? byChapter
            : (bySubjectId.isNotEmpty ? bySubjectId : byName);
        if (mcqs.isEmpty) return const SizedBox.shrink();
        final preview = mcqs.take(5).toList();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MCQ सराव (${mcqs.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                ),
                const SizedBox(height: 8),
                ...preview.map(
                  (q) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.quiz_rounded, size: 18, color: AppColors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            q.question,
                            style: const TextStyle(height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (mcqs.length > preview.length)
                  Text(
                    '+ ${mcqs.length - preview.length} अधिक MCQ Practice मध्ये',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
        );
      },
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

class _ChapterAiActions extends StatelessWidget {
  const _ChapterAiActions({
    required this.chapter,
    required this.subjectTitle,
  });

  final ChapterItem chapter;
  final String subjectTitle;

  void _open(BuildContext context, AiLessonStudioTab tab) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiTeacherClassroomScreen(
          chapter: chapter,
          subjectTitle: subjectTitle,
          autoTeachChapter: true,
          initialTab: tab,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = <({IconData icon, String label, VoidCallback onTap})>[
      (
        icon: Icons.play_circle_fill_rounded,
        label: 'AI Lesson',
        onTap: () => _open(context, AiLessonStudioTab.video),
      ),
      (
        icon: Icons.menu_book_rounded,
        label: 'Notes',
        onTap: () {},
      ),
      (
        icon: Icons.picture_as_pdf_outlined,
        label: 'PDF',
        onTap: () => _open(context, AiLessonStudioTab.notes),
      ),
      (
        icon: Icons.style_rounded,
        label: 'Revision',
        onTap: () => _open(context, AiLessonStudioTab.revision),
      ),
      (
        icon: Icons.quiz_rounded,
        label: 'MCQ',
        onTap: () => _open(context, AiLessonStudioTab.mcqs),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI शिक्षक',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in actions)
              ActionChip(
                avatar: Icon(a.icon, size: 18, color: AppColors.navy),
                label: Text(a.label),
                backgroundColor: Colors.white,
                side: BorderSide(color: AppColors.navy.withValues(alpha: 0.12)),
                onPressed: a.onTap,
              ),
          ],
        ),
      ],
    );
  }
}
