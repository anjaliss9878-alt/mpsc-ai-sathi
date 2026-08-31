import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/utils/date_format.dart';

/// Shared search + filters used by Admin content lists.
class AdminContentFilterBar extends StatefulWidget {
  const AdminContentFilterBar({
    super.key,
    required this.queryHint,
    required this.onQueryChanged,
    this.status,
    this.onStatusChanged,
    this.targetGroup,
    this.onTargetGroupChanged,
    this.difficulty,
    this.onDifficultyChanged,
    this.language,
    this.onLanguageChanged,
    this.subjectId,
    this.onSubjectIdChanged,
    this.chapterId,
    this.onChapterIdChanged,
    this.topicId,
    this.onTopicIdChanged,
    this.date,
    this.onDateChanged,
    this.showIndexFilters = false,
    this.showSearch = true,
  });

  final String queryHint;
  final ValueChanged<String> onQueryChanged;
  final NoteWorkflowStatus? status;
  final ValueChanged<NoteWorkflowStatus?>? onStatusChanged;
  final String? targetGroup;
  final ValueChanged<String?>? onTargetGroupChanged;
  final String? difficulty;
  final ValueChanged<String?>? onDifficultyChanged;
  final String? language;
  final ValueChanged<String?>? onLanguageChanged;
  final String? subjectId;
  final ValueChanged<String?>? onSubjectIdChanged;
  final String? chapterId;
  final ValueChanged<String?>? onChapterIdChanged;
  final String? topicId;
  final ValueChanged<String?>? onTopicIdChanged;
  final DateTime? date;
  final ValueChanged<DateTime?>? onDateChanged;
  final bool showIndexFilters;
  final bool showSearch;

  @override
  State<AdminContentFilterBar> createState() => _AdminContentFilterBarState();
}

class _AdminContentFilterBarState extends State<AdminContentFilterBar> {
  List<SubjectItem> _subjects = const [];
  List<ChapterItem> _chapters = const [];
  List<ChapterItem> _topics = const [];

  @override
  void initState() {
    super.initState();
    if (widget.showIndexFilters) {
      _loadSubjects();
      if ((widget.subjectId ?? '').isNotEmpty) {
        _loadChapters(widget.subjectId!);
      }
      if ((widget.chapterId ?? '').isNotEmpty) {
        _loadTopics(widget.chapterId!);
      }
    }
  }

  @override
  void didUpdateWidget(covariant AdminContentFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showIndexFilters && oldWidget.subjectId != widget.subjectId) {
      _loadChapters(widget.subjectId ?? '');
    }
    if (widget.showIndexFilters && oldWidget.chapterId != widget.chapterId) {
      _loadTopics(widget.chapterId ?? '');
    }
  }

  Future<void> _loadSubjects() async {
    final items = await notesRepository.watchSubjects().first;
    if (mounted) setState(() => _subjects = items);
  }

  Future<void> _loadChapters(String subjectId) async {
    if (subjectId.isEmpty) {
      setState(() {
        _chapters = const [];
        _topics = const [];
      });
      return;
    }
    final items = await notesRepository.watchRootChapters(subjectId).first;
    if (mounted) setState(() => _chapters = items);
  }

  Future<void> _loadTopics(String chapterId) async {
    if (chapterId.isEmpty) {
      setState(() => _topics = const []);
      return;
    }
    final items = await notesRepository.watchChildChapters(chapterId).first;
    if (mounted) setState(() => _topics = items);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    widget.onDateChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          if (widget.showSearch) ...[
            TextField(
              decoration: InputDecoration(
                hintText: widget.queryHint,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onChanged: widget.onQueryChanged,
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.onTargetGroupChanged != null)
                DropdownButton<String?>(
                  value: widget.targetGroup,
                  hint: const Text('Group'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All groups')),
                    DropdownMenuItem(value: 'groupB', child: Text('Group B')),
                    DropdownMenuItem(value: 'groupC', child: Text('Group C')),
                    DropdownMenuItem(value: 'both', child: Text('Both')),
                  ],
                  onChanged: widget.onTargetGroupChanged,
                ),
              if (widget.showIndexFilters && widget.onSubjectIdChanged != null)
                DropdownButton<String?>(
                  value: widget.subjectId,
                  hint: const Text('Subject'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All subjects')),
                    for (final s in _subjects)
                      DropdownMenuItem(value: s.id, child: Text(s.title)),
                  ],
                  onChanged: (v) {
                    widget.onSubjectIdChanged?.call(v);
                    widget.onChapterIdChanged?.call(null);
                    widget.onTopicIdChanged?.call(null);
                  },
                ),
              if (widget.showIndexFilters && widget.onChapterIdChanged != null)
                DropdownButton<String?>(
                  value: widget.chapterId,
                  hint: const Text('Chapter'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All chapters')),
                    for (final c in _chapters)
                      DropdownMenuItem(value: c.id, child: Text(c.title)),
                  ],
                  onChanged: (v) {
                    widget.onChapterIdChanged?.call(v);
                    widget.onTopicIdChanged?.call(null);
                  },
                ),
              if (widget.showIndexFilters && widget.onTopicIdChanged != null)
                DropdownButton<String?>(
                  value: widget.topicId,
                  hint: const Text('Topic'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All topics')),
                    for (final t in _topics)
                      DropdownMenuItem(value: t.id, child: Text(t.title)),
                  ],
                  onChanged: widget.onTopicIdChanged,
                ),
              if (widget.onStatusChanged != null)
                DropdownButton<NoteWorkflowStatus?>(
                  value: widget.status,
                  hint: const Text('Status'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All statuses')),
                    for (final s in NoteWorkflowStatus.values)
                      DropdownMenuItem(
                        value: s,
                        child: Text(contentWorkflowStatusLabel(s)),
                      ),
                  ],
                  onChanged: widget.onStatusChanged,
                ),
              if (widget.onDifficultyChanged != null)
                DropdownButton<String?>(
                  value: widget.difficulty,
                  hint: const Text('Difficulty'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All difficulty')),
                    DropdownMenuItem(value: 'Easy', child: Text('Easy')),
                    DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'Hard', child: Text('Hard')),
                  ],
                  onChanged: widget.onDifficultyChanged,
                ),
              if (widget.onLanguageChanged != null)
                DropdownButton<String?>(
                  value: widget.language,
                  hint: const Text('Language'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All languages')),
                    DropdownMenuItem(value: 'mr', child: Text('Marathi')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                  ],
                  onChanged: widget.onLanguageChanged,
                ),
              if (widget.onDateChanged != null)
                InputChip(
                  avatar: const Icon(Icons.event_rounded, size: 16),
                  label: Text(
                    widget.date == null
                        ? 'Date'
                        : formatShortDate(widget.date!),
                  ),
                  onPressed: _pickDate,
                  onDeleted: widget.date == null
                      ? null
                      : () => widget.onDateChanged?.call(null),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
