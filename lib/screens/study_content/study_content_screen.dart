import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_select_field.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/study_content_session_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/pyq_authenticity.dart';
import 'package:mpsc_combine_ai/widgets/rag_citation_block.dart';
import 'package:mpsc_combine_ai/widgets/rag_study_tool_sheets.dart';

/// Student: enter an MPSC topic → approved RAG notes → follow-up tools.
class StudyContentScreen extends StatefulWidget {
  const StudyContentScreen({
    super.key,
    this.initialTopic = '',
    this.subjectTitle = '',
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
  });

  final String initialTopic;
  final String subjectTitle;
  final String subjectId;
  final String chapterId;
  final String topicId;

  @override
  State<StudyContentScreen> createState() => _StudyContentScreenState();
}

enum _StudyTab { notes, mcqs, pyqs, explanation, revision }

class _StudyContentScreenState extends State<StudyContentScreen> {
  late final TextEditingController _topic;
  StudyContentSession? _session;
  _StudyTab _tab = _StudyTab.notes;
  bool _loading = false;
  bool _followUpBusy = false;
  bool _submitting = false;
  String? _error;

  List<SubjectItem> _subjects = const [];
  List<ChapterItem> _chapters = const [];
  List<ChapterItem> _topics = const [];
  String _subjectId = '';
  String _chapterId = '';
  String _topicId = '';
  String _subjectTitle = '';

  @override
  void initState() {
    super.initState();
    _topic = TextEditingController(text: widget.initialTopic);
    _subjectId = widget.subjectId;
    _chapterId = widget.chapterId;
    _topicId = widget.topicId;
    _subjectTitle = widget.subjectTitle;
    _loadIndex();
    if (widget.initialTopic.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
    }
  }

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  Future<void> _loadIndex() async {
    final subjects = await notesRepository.getSubjectsOnce(
      examId: kGroupBCombinedExamId,
    );
    final published = subjects.where((s) => s.published).toList();
    if (!mounted) return;
    setState(() => _subjects = published);
    if (_subjectId.isNotEmpty) await _loadChapters(_subjectId);
  }

  Future<void> _loadChapters(String subjectId) async {
    if (subjectId.isEmpty) {
      setState(() {
        _chapters = const [];
        _topics = const [];
      });
      return;
    }
    final all = await notesRepository.getChaptersOnce(subjectId);
    final roots = all.where((c) => c.parentChapterId.isEmpty).toList();
    if (!mounted) return;
    setState(() {
      _chapters = roots.isEmpty ? all.where((c) => c.isStudentLeaf).toList() : roots;
    });
    await _loadTopics(_chapterId, all);
  }

  Future<void> _loadTopics(String chapterId, [List<ChapterItem>? all]) async {
    final rows = all ??
        (_subjectId.isEmpty
            ? const <ChapterItem>[]
            : await notesRepository.getChaptersOnce(_subjectId));
    final topics = chapterId.isEmpty
        ? rows.where((c) => c.isStudentLeaf).toList()
        : rows
            .where(
              (c) =>
                  c.parentChapterId == chapterId ||
                  (c.id == chapterId && c.isStudentLeaf),
            )
            .toList();
    if (topics.isEmpty && chapterId.isNotEmpty) {
      final self = rows.where((c) => c.id == chapterId).toList();
      if (!mounted) return;
      setState(() => _topics = self);
      return;
    }
    if (!mounted) return;
    setState(() => _topics = topics);
  }

  Future<void> _generate() async {
    final topic = _topic.text.trim();
    if (topic.isEmpty) {
      setState(() => _error = 'Select a topic or enter an MPSC Combine topic.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _session = null;
      _tab = _StudyTab.notes;
    });
    try {
      final session = await studyContentSessionService.open(
        topic: topic,
        subjectTitle: _subjectTitle,
        subjectId: _subjectId,
        chapterId: _chapterId,
        topicId: _topicId,
      );
      if (!mounted) return;
      setState(() => _session = session);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openTab(_StudyTab tab) async {
    final session = _session;
    if (session == null || session.insufficient) return;
    setState(() => _tab = tab);
    setState(() => _followUpBusy = true);
    try {
      switch (tab) {
        case _StudyTab.notes:
          break;
        case _StudyTab.mcqs:
          await studyContentSessionService.loadMcqs(session);
          break;
        case _StudyTab.pyqs:
          await studyContentSessionService.loadPyqs(session);
          break;
        case _StudyTab.explanation:
          await studyContentSessionService.loadExplanation(session);
          break;
        case _StudyTab.revision:
          await studyContentSessionService.loadRevision(session);
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _followUpBusy = false);
    }
  }

  Future<void> _submitDraft() async {
    final session = _session;
    if (session == null || session.insufficient) return;
    setState(() => _submitting = true);
    try {
      await studyContentSessionService.submitForAdminReview(session);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Submitted for admin review as a draft. It is not published.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'AI Study Content',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_subjects.isNotEmpty) ...[
                    AdminSelectField(
                      label: 'Subject',
                      value: _subjectId,
                      items: [
                        for (final s in _subjects)
                          AdminSelectItem(id: s.id, label: s.title),
                      ],
                      onChanged: (id) async {
                        final subject = _subjects.where((s) => s.id == id);
                        setState(() {
                          _subjectId = id;
                          _subjectTitle =
                              subject.isEmpty ? '' : subject.first.title;
                          _chapterId = '';
                          _topicId = '';
                          _topics = const [];
                        });
                        await _loadChapters(id);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_chapters.isNotEmpty) ...[
                    AdminSelectField(
                      label: 'Chapter',
                      value: _chapters.any((c) => c.id == _chapterId)
                          ? _chapterId
                          : '',
                      items: [
                        for (final c in _chapters)
                          AdminSelectItem(id: c.id, label: c.title),
                      ],
                      onChanged: (id) async {
                        setState(() {
                          _chapterId = id;
                          _topicId = '';
                        });
                        await _loadTopics(id);
                        final chapter = _chapters.where((c) => c.id == id);
                        if (chapter.isNotEmpty &&
                            (_topics.isEmpty ||
                                (_topics.length == 1 && _topics.first.id == id))) {
                          setState(() {
                            _topicId = id;
                            _topic.text = chapter.first.title;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_topics.isNotEmpty) ...[
                    AdminSelectField(
                      label: 'Topic',
                      value: _topics.any((t) => t.id == _topicId)
                          ? _topicId
                          : '',
                      items: [
                        for (final t in _topics)
                          AdminSelectItem(id: t.id, label: t.title),
                      ],
                      onChanged: (id) {
                        final match = _topics.where((t) => t.id == id);
                        setState(() {
                          _topicId = id;
                          if (match.isNotEmpty) {
                            _topic.text = match.first.title;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: _topic,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _generate(),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Article 14, Maharashtra soils, monsoon',
                      prefixIcon: Icon(Icons.menu_book_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _generate,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navy,
                      ),
                      child: Text(_loading ? 'Retrieving approved notes…' : 'Generate notes'),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _body(session)),
          ],
        ),
      ),
    );
  }

  Widget _body(StudyContentSession? session) {
    if (session == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Enter an MPSC Combine topic. Notes are generated only from published, indexed reference material.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.45),
          ),
        ),
      );
    }
    if (session.insufficient) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline_rounded, color: AppColors.navy, size: 36),
            SizedBox(height: 12),
            Text(
              kStudyContentInsufficient,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: AppColors.navy,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'No published + Ready reference material was found for this topic. Generic AI knowledge was not used.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.45),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final tab in _StudyTab.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_tabLabel(tab)),
                    selected: _tab == tab,
                    onSelected: (_) => _openTab(tab),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _submitting ? null : _submitDraft,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.rate_review_outlined),
              label: const Text('Submit for admin review (draft)'),
            ),
          ),
        ),
        if (_followUpBusy) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _tabBody(session)),
      ],
    );
  }

  String _tabLabel(_StudyTab tab) {
    switch (tab) {
      case _StudyTab.notes:
        return 'Notes';
      case _StudyTab.mcqs:
        return 'MCQs';
      case _StudyTab.pyqs:
        return kAiPyqConnectionLabel;
      case _StudyTab.explanation:
        return 'Explanation';
      case _StudyTab.revision:
        return 'Quick Revision';
    }
  }

  Widget _tabBody(StudyContentSession session) {
    switch (_tab) {
      case _StudyTab.notes:
        return RagSummaryView(summary: session.notes);
      case _StudyTab.mcqs:
        final mcqs = session.mcqs;
        if (mcqs == null) return const SizedBox.shrink();
        if (mcqs.isEmpty) {
          return const _Hint(kStudyContentInsufficient);
        }
        return RagMcqView(
          questions: mcqs,
          title: session.topic,
          subjectId: session.subjectId,
          chapterId: session.chapterId,
        );
      case _StudyTab.pyqs:
        final pyqs = session.pyqs;
        if (pyqs == null) return const SizedBox.shrink();
        return RagPyqView(items: pyqs);
      case _StudyTab.explanation:
        final answer = session.explanation;
        if (answer == null) return const SizedBox.shrink();
        if (answer.insufficient) {
          return const _Hint(kStudyContentInsufficient);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            MarkdownBody(data: answer.markdown),
            RagCitationBlock(citations: answer.citations),
          ],
        );
      case _StudyTab.revision:
        final revision = session.revision;
        if (revision == null) return const SizedBox.shrink();
        return RagRevisionView(revision: revision);
    }
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.45),
        ),
      ),
    );
  }
}
