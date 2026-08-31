import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';

/// Current Exam → Group → Subject → Chapter → Topic selection.
class ContentIndexSelection {
  const ContentIndexSelection({
    this.examId = kDefaultExamId,
    this.targetGroup = TargetGroup.groupB,
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
    this.subjectTitle = '',
    this.chapterTitle = '',
    this.topicTitle = '',
  });

  final String examId;
  final TargetGroup targetGroup;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final String subjectTitle;
  final String chapterTitle;
  final String topicTitle;

  bool get isComplete =>
      examId.isNotEmpty && subjectId.isNotEmpty && chapterId.isNotEmpty && topicId.isNotEmpty;
}

/// Reuses Part 1 `exams` / `subjects` / `chapters`. Group B/C is a field,
/// not a new collection.
class ContentIndexPicker extends StatefulWidget {
  const ContentIndexPicker({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final ContentIndexSelection initial;
  final ValueChanged<ContentIndexSelection> onChanged;

  @override
  State<ContentIndexPicker> createState() => _ContentIndexPickerState();
}

class _ContentIndexPickerState extends State<ContentIndexPicker> {
  late ContentIndexSelection _value;
  List<ExamItem> _exams = const [];
  List<SubjectItem> _subjects = const [];
  List<ChapterItem> _rootChapters = const [];
  List<ChapterItem> _topics = const [];

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
    _load();
  }

  Future<void> _load() async {
    await notesRepository.ensureDefaultExam();
    final exams = await notesRepository.getExamsOnce();
    final subjects = await notesRepository.getSubjectsOnce();
    if (!mounted) return;
    setState(() {
      _exams = exams.isEmpty ? [ExamItem.mpscCombine()] : exams;
      _subjects = subjects;
    });
    await _loadChapters(_value.subjectId, keepChapter: true);
  }

  Future<void> _loadChapters(String subjectId, {bool keepChapter = false}) async {
    if (subjectId.isEmpty) {
      setState(() {
        _rootChapters = const [];
        _topics = const [];
      });
      return;
    }
    final all = await notesRepository.getChaptersOnce(subjectId);
    final roots = all.where((c) => c.parentChapterId.isEmpty).toList();
    var chapterId = keepChapter ? _value.chapterId : '';
    if (chapterId.isNotEmpty && !roots.any((c) => c.id == chapterId)) {
      final current = all.where((c) => c.id == chapterId);
      if (current.isNotEmpty && current.first.parentChapterId.isNotEmpty) {
        chapterId = current.first.parentChapterId;
      }
    }
    if (chapterId.isEmpty && roots.length == 1) chapterId = roots.first.id;
    final topics = chapterId.isEmpty
        ? const <ChapterItem>[]
        : all.where((c) => c.parentChapterId == chapterId).toList();
    var topicId = keepChapter ? _value.topicId : '';
    if (topicId.isEmpty && topics.length == 1) topicId = topics.first.id;
    if (topicId.isEmpty && topics.isEmpty && chapterId.isNotEmpty) {
      topicId = chapterId;
    }
    if (!mounted) return;
    setState(() {
      _rootChapters = roots.isEmpty ? all : roots;
      _topics = topics;
    });
    _emit(
      _value.subjectId == subjectId && keepChapter
          ? _value.copy(
              chapterId: chapterId,
              topicId: topicId,
              chapterTitle: _titleOf(_rootChapters, chapterId),
              topicTitle: _titleOf(
                _topics.isEmpty ? _rootChapters : _topics,
                topicId,
              ),
            )
          : ContentIndexSelection(
              examId: _value.examId,
              targetGroup: _value.targetGroup,
              subjectId: subjectId,
              chapterId: chapterId,
              topicId: topicId,
              subjectTitle: _subjectTitle(subjectId),
              chapterTitle: _titleOf(_rootChapters, chapterId),
              topicTitle: _titleOf(_topics.isEmpty ? _rootChapters : _topics, topicId),
            ),
    );
  }

  String _subjectTitle(String id) {
    for (final s in _subjects) {
      if (s.id == id) return s.title;
    }
    return _value.subjectTitle;
  }

  String _titleOf(List<ChapterItem> list, String id) {
    for (final c in list) {
      if (c.id == id) return c.title;
    }
    return '';
  }

  void _emit(ContentIndexSelection next) {
    _value = next;
    widget.onChanged(next);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final exams = _exams.isEmpty ? [ExamItem.mpscCombine()] : _exams;
    final subjects = _subjects
        .where((s) => s.examId == _value.examId || s.examId.isEmpty)
        .toList();
    final topicItems = _topics.isEmpty && _value.chapterId.isNotEmpty
        ? [
            ChapterItem(
              id: _value.chapterId,
              subjectId: _value.subjectId,
              title: '${_value.chapterTitle.isEmpty ? "Chapter" : _value.chapterTitle} (use as topic)',
              order: 0,
            ),
          ]
        : _topics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: exams.any((e) => e.id == _value.examId) ? _value.examId : exams.first.id,
          decoration: const InputDecoration(labelText: 'Exam'),
          items: [
            for (final e in exams)
              DropdownMenuItem(value: e.id, child: Text(e.title)),
          ],
          onChanged: (v) {
            if (v == null) return;
            _emit(
              ContentIndexSelection(
                examId: v,
                targetGroup: _value.targetGroup,
              ),
            );
            _loadChapters('');
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<TargetGroup>(
          value: _value.targetGroup,
          decoration: const InputDecoration(labelText: 'Target'),
          items: [
            for (final g in TargetGroup.values)
              DropdownMenuItem(value: g, child: Text(targetGroupLabel(g))),
          ],
          onChanged: (v) {
            if (v == null) return;
            _emit(
              _value.copy(targetGroup: v),
            );
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: subjects.any((s) => s.id == _value.subjectId) ? _value.subjectId : null,
          decoration: const InputDecoration(labelText: 'Subject'),
          items: [
            for (final s in subjects)
              DropdownMenuItem(value: s.id, child: Text(s.title)),
          ],
          onChanged: (v) {
            if (v == null) return;
            _emit(
              ContentIndexSelection(
                examId: _value.examId,
                targetGroup: _value.targetGroup,
                subjectId: v,
                subjectTitle: _subjectTitle(v),
              ),
            );
            _loadChapters(v);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _rootChapters.any((c) => c.id == _value.chapterId)
              ? _value.chapterId
              : null,
          decoration: const InputDecoration(labelText: 'Chapter'),
          items: [
            for (final c in _rootChapters)
              DropdownMenuItem(value: c.id, child: Text(c.title)),
          ],
          onChanged: (v) {
            if (v == null) return;
            _loadChapters(_value.subjectId, keepChapter: false).then((_) async {
              final all = await notesRepository.getChaptersOnce(_value.subjectId);
              final topics = all.where((c) => c.parentChapterId == v).toList();
              if (!mounted) return;
              setState(() => _topics = topics);
              _emit(
                _value.copy(
                  chapterId: v,
                  topicId: topics.length == 1
                      ? topics.first.id
                      : (topics.isEmpty ? v : ''),
                  chapterTitle: _titleOf(_rootChapters, v),
                  topicTitle: topics.length == 1
                      ? topics.first.title
                      : (topics.isEmpty ? _titleOf(_rootChapters, v) : ''),
                ),
              );
            });
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: topicItems.any((t) => t.id == _value.topicId) ? _value.topicId : null,
          decoration: const InputDecoration(labelText: 'Topic'),
          items: [
            for (final t in topicItems)
              DropdownMenuItem(value: t.id, child: Text(t.title)),
          ],
          onChanged: (v) {
            if (v == null) return;
            _emit(
              _value.copy(
                topicId: v,
                topicTitle: _titleOf(topicItems, v),
              ),
            );
          },
        ),
      ],
    );
  }
}

extension on ContentIndexSelection {
  ContentIndexSelection copy({
    String? examId,
    TargetGroup? targetGroup,
    String? subjectId,
    String? chapterId,
    String? topicId,
    String? subjectTitle,
    String? chapterTitle,
    String? topicTitle,
  }) {
    return ContentIndexSelection(
      examId: examId ?? this.examId,
      targetGroup: targetGroup ?? this.targetGroup,
      subjectId: subjectId ?? this.subjectId,
      chapterId: chapterId ?? this.chapterId,
      topicId: topicId ?? this.topicId,
      subjectTitle: subjectTitle ?? this.subjectTitle,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      topicTitle: topicTitle ?? this.topicTitle,
    );
  }
}
