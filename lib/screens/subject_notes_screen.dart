import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/data/student_curriculum.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/screens/topic_list_screen.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';
import 'package:mpsc_combine_ai/widgets/notes_widgets.dart';

/// Student subject-wise notes — live Firestore (`subjects`, `published`).
/// Drill-down uses exam → stage → paper → subject from existing exam docs.
class SubjectNotesScreen extends StatefulWidget {
  const SubjectNotesScreen({
    super.key,
    this.examId = '',
    this.stageId = '',
    this.paperId = '',
  });

  final String examId;
  final String stageId;
  final String paperId;

  @override
  State<SubjectNotesScreen> createState() => _SubjectNotesScreenState();
}

class _SubjectNotesScreenState extends State<SubjectNotesScreen> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(notesRepository.ensureDefaultExam());
  }

  List<T> _filterNamed<T>(
    List<T> items,
    String Function(T) titleOf,
    String Function(T)? extraOf,
  ) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((item) {
      final extra = extraOf == null ? '' : extraOf(item);
      return titleOf(item).toLowerCase().contains(q) ||
          extra.toLowerCase().contains(q);
    }).toList();
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  void _openPaperSubjects({
    required ExamItem exam,
    required ExamStageSpec stage,
    required ExamPaperSpec paper,
    required List<SubjectItem> subjects,
  }) {
    final forPaper = subjectsForPaper(
      subjects: subjects,
      examId: exam.id,
      stageId: stage.id,
      paperId: paper.id,
    );
    if (forPaper.length == 1) {
      _open(TopicListScreen(subject: forPaper.first));
      return;
    }
    _open(
      SubjectNotesScreen(
        examId: exam.id,
        stageId: stage.id,
        paperId: paper.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NotesAppBar(title: _appBarTitle()),
      body: StreamBuilder<List<ExamItem>>(
        stream: notesRepository.watchExams(),
        builder: (context, examSnap) {
          return StreamBuilder<List<SubjectItem>>(
            stream: notesRepository.watchPublishedSubjects(
              examId: widget.examId.isEmpty
                  ? kGroupBCombinedExamId
                  : widget.examId,
            ),
            builder: (context, subjectSnap) {
              if (examSnap.hasError || subjectSnap.hasError) {
                return ResponsiveScrollView(
                  children: [
                    ErrorState(
                      message:
                          'विषय लोड करता आले नाहीत.\n'
                          '(Could not load subjects.)\n'
                          '${examSnap.error ?? subjectSnap.error}',
                    ),
                  ],
                );
              }
              if (!examSnap.hasData || !subjectSnap.hasData) {
                return const ResponsiveScrollView(children: [LoadingState()]);
              }
              final exams = examSnap.data!;
              final subjects = subjectSnap.data!;
              return _buildBody(exams, subjects);
            },
          );
        },
      ),
    );
  }

  String _appBarTitle() {
    if (widget.paperId.isNotEmpty) return 'विषय निवडा';
    if (groupBStageShowsPrelimsAreas(widget.examId, widget.stageId)) {
      return 'विषय / क्षेत्र निवडा';
    }
    if (widget.stageId.isNotEmpty) return 'पेपर निवडा';
    if (widget.examId.isNotEmpty) return 'टप्पा निवडा';
    return 'विषयवार नोट्स';
  }

  Widget _buildBody(List<ExamItem> exams, List<SubjectItem> subjects) {
    if (widget.examId.isEmpty) {
      final effectiveExams = [
        _examById(exams, kGroupBCombinedExamId),
      ];
      return _listPage(
        headerTitle: 'विषयवार नोट्स',
        headerDescription:
            'MPSC Group B Combined पूर्व परीक्षा आणि मुख्य परीक्षेसाठी विषयनिहाय संरचित नोट्स.',
        sectionTitle: 'परीक्षा निवडा',
        hint: 'परीक्षा शोधा… / Search exams',
        emptyAll: 'अजून प्रकाशित परीक्षा नाहीत.',
        tiles: _filterNamed(effectiveExams, (e) => e.title, (e) => e.titleEn).map((exam) {
          return NotesListTile(
            title: exam.title,
            subtitle: exam.titleEn.isNotEmpty && exam.titleEn != exam.title
                ? exam.titleEn
                : (exam.stages.isEmpty ? 'विषय' : 'पूर्व / मुख्य'),
            leading: _iconBox(Icons.school_rounded),
            onTap: () => _open(SubjectNotesScreen(examId: exam.id)),
          );
        }),
      );
    }

    final exam = _examById(exams, widget.examId);

    if (widget.stageId.isEmpty && exam.stages.isNotEmpty) {
      return _listPage(
        headerTitle: exam.title,
        headerDescription: 'टप्पा निवडा (Prelims / Mains).',
        sectionTitle: 'टप्पा निवडा',
        hint: 'टप्पा शोधा… / Search stages',
        emptyAll: 'या परीक्षेसाठी टप्पे उपलब्ध नाहीत.',
        tiles: _filterNamed(exam.stages, (s) => s.title, null).map((stage) {
          return NotesListTile(
            title: stage.title,
            subtitle: stage.id,
            leading: _iconBox(Icons.layers_rounded),
            onTap: () => _open(
              SubjectNotesScreen(examId: exam.id, stageId: stage.id),
            ),
          );
        }),
      );
    }

    if (groupBStageShowsPrelimsAreas(exam.id, widget.stageId)) {
      final gat = subjects.where((s) => s.id == kGroupBSubjectPrelimsGatId);
      final gatSubject = gat.isEmpty ? null : gat.first;
      if (gatSubject == null) {
        return _listPage(
          headerTitle: 'Preliminary Examination',
          headerDescription:
              'General Ability Test areas. Official paper remains General Ability Test.',
          sectionTitle: 'विषय / क्षेत्र निवडा',
          hint: 'क्षेत्र शोधा… / Search areas',
          emptyAll: 'GAT विषय उपलब्ध नाही.',
          tiles: const [],
        );
      }
      return StreamBuilder<List<ChapterItem>>(
        stream: notesRepository.watchPublishedChapters(gatSubject.id),
        builder: (context, chapterSnap) {
          final chapters = chapterSnap.data ?? const <ChapterItem>[];
          final tiles = _filterNamed(
            kGroupBPrelimsAreaIds,
            syllabusAreaTitle,
            null,
          ).map((areaId) {
            final count = chaptersForSyllabusArea(chapters, areaId).length;
            return NotesListTile(
              title: syllabusAreaTitle(areaId),
              subtitle: count > 0 ? '$count chapters' : 'General Ability Test',
              leading: _iconBox(_areaIcon(areaId)),
              onTap: () => _open(
                TopicListScreen(
                  subject: gatSubject,
                  syllabusAreaId: areaId,
                ),
              ),
            );
          });
          return _listPage(
            headerTitle: 'Preliminary Examination',
            headerDescription:
                'Select a General Ability Test area. These cards are UI groups only.',
            sectionTitle: 'विषय / क्षेत्र निवडा',
            hint: 'क्षेत्र शोधा… / Search areas',
            emptyAll: 'क्षेत्र उपलब्ध नाहीत.',
            tiles: tiles,
          );
        },
      );
    }

    if (widget.stageId.isNotEmpty && widget.paperId.isEmpty) {
      final stage = _stageById(exam, widget.stageId);
      final papers = exam.papers
          .where((p) => p.stageId == widget.stageId)
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      if (papers.isNotEmpty) {
        return _listPage(
          headerTitle: stage?.title ?? exam.title,
          headerDescription: 'पेपर निवडा.',
          sectionTitle: 'पेपर निवडा',
          hint: 'पेपर शोधा… / Search papers',
          emptyAll: 'या टप्प्यासाठी पेपर उपलब्ध नाहीत.',
          tiles: _filterNamed(papers, (p) => p.title, null).map((paper) {
            return NotesListTile(
              title: paper.title,
              subtitle: paper.medium.isNotEmpty ? paper.medium : paper.id,
              leading: _iconBox(Icons.description_rounded),
              onTap: () => _openPaperSubjects(
                exam: exam,
                stage: stage ??
                    ExamStageSpec(id: widget.stageId, title: widget.stageId),
                paper: paper,
                subjects: subjects,
              ),
            );
          }),
        );
      }
    }

    final scoped = widget.paperId.isNotEmpty
        ? subjectsForPaper(
            subjects: subjects,
            examId: exam.id,
            stageId: widget.stageId,
            paperId: widget.paperId,
          )
        : subjectsForExam(subjects, exam.id);

    final filtered = _filterNamed(
      scoped,
      (s) => s.title,
      (s) => '${s.subtitle} ${s.nameEn}',
    );

    return _listPage(
      headerTitle: exam.title,
      headerDescription:
          widget.paperId.isNotEmpty
              ? 'या पेपरचे विषय.'
              : 'MPSC Group B Combined पूर्व परीक्षा आणि मुख्य परीक्षेसाठी विषयनिहाय संरचित नोट्स.',
      sectionTitle: 'विषय निवडा',
      hint: 'विषय शोधा… / Search subjects',
      emptyAll:
          'अजून प्रकाशित विषय नाहीत.\n'
          'Admin Panel मधून Subject तयार करा आणि Published करा — '
          'ते येथे लगेच दिसतील.\n'
          '(No published subjects yet.)',
      tiles: filtered.map((subject) {
        return NotesListTile(
          title: subject.title,
          subtitle: subject.subtitle,
          leading: _iconBox(subject.icon),
          onTap: () => _open(TopicListScreen(subject: subject)),
        );
      }),
    );
  }

  Widget _listPage({
    required String headerTitle,
    required String headerDescription,
    required String sectionTitle,
    required String hint,
    required String emptyAll,
    required Iterable<Widget> tiles,
  }) {
    final tileList = tiles.toList();
    return ResponsiveScrollView(
      children: [
        NotesHeaderCard(
          icon: Icons.library_books_rounded,
          title: headerTitle,
          description: headerDescription,
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search_rounded),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 24),
        NotesSectionTitle(title: sectionTitle),
        const SizedBox(height: 12),
        if (tileList.isEmpty)
          EmptyState(
            message: _query.trim().isEmpty
                ? emptyAll
                : 'शोध निकष जुळले नाहीत.\n(No subjects match your search.)',
            icon: _query.trim().isEmpty
                ? Icons.library_books_outlined
                : Icons.search_off_rounded,
          )
        else
          ...tileList.map(
            (tile) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: tile,
            ),
          ),
      ],
    );
  }

  ExamItem _examById(List<ExamItem> exams, String id) {
    if (id == kGroupBCombinedExamId || id.isEmpty) {
      // Always use the canonical Group B stages/papers so an incomplete
      // Firestore exam doc cannot skip to the legacy flat subject list.
      return ExamItem.groupBCombined();
    }
    for (final exam in exams) {
      if (exam.id == id) return exam;
    }
    return ExamItem.mpscCombine();
  }

  ExamStageSpec? _stageById(ExamItem exam, String stageId) {
    for (final stage in exam.stages) {
      if (stage.id == stageId) return stage;
    }
    return null;
  }

  Widget _iconBox(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: AppColors.navy, size: 22),
    );
  }

  IconData _areaIcon(String areaId) {
    switch (areaId) {
      case 'current_affairs':
        return Icons.newspaper_rounded;
      case 'history':
        return Icons.history_edu_rounded;
      case 'geography':
        return Icons.public_rounded;
      case 'economy':
        return Icons.trending_up_rounded;
      case 'polity':
        return Icons.account_balance_rounded;
      case 'general_science':
        return Icons.science_rounded;
      case 'intelligence_arithmetic':
        return Icons.calculate_rounded;
      default:
        return Icons.menu_book_rounded;
    }
  }
}
