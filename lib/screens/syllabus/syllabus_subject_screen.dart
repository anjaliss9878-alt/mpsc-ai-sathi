import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/syllabus/syllabus_tracker_screen.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// One subject: chapter/topic rows with Not started / In progress / Completed.
class SyllabusSubjectScreen extends StatefulWidget {
  const SyllabusSubjectScreen({super.key, required this.subjectId});

  final String subjectId;

  @override
  State<SyllabusSubjectScreen> createState() => _SyllabusSubjectScreenState();
}

class _SyllabusSubjectScreenState extends State<SyllabusSubjectScreen> {
  final _busy = <String>{};
  String? _saveError;
  SyllabusTopicStatus? _failedStatus;
  String? _failedChapterId;
  Stream<SyllabusProgressSnapshot>? _stream;
  int _retry = 0;

  String? get _uid => authService.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    final uid = _uid;
    _stream = uid == null ? null : syllabusProgressTracker.watch(uid);
  }

  void _reload() {
    final uid = _uid;
    setState(() {
      _retry++;
      _saveError = null;
      if (uid != null) {
        _stream = syllabusProgressTracker.watch(uid);
      }
    });
  }

  Future<void> _setStatus(
    SyllabusTopicProgress topic,
    SyllabusTopicStatus status,
  ) async {
    final uid = _uid;
    if (uid == null) return;
    setState(() {
      _busy.add(topic.chapterId);
      _saveError = null;
      _failedStatus = null;
      _failedChapterId = null;
    });
    try {
      await syllabusProgressTracker.setTopicStatus(
        uid: uid,
        topic: topic,
        status: status,
        source: 'manual',
      );
      if (!mounted) return;
      if (status == SyllabusTopicStatus.completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${topic.chapterTitle} पूर्ण. प्लॅनर व प्रगती अद्ययावत.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saveError = 'स्थिती जतन करता आली नाही.\n$e';
        _failedStatus = status;
        _failedChapterId = topic.chapterId;
      });
    } finally {
      if (mounted) {
        setState(() => _busy.remove(topic.chapterId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) {
      return const Scaffold(
        body: ErrorState(message: 'साइन इन करा.'),
      );
    }
    return StreamBuilder<SyllabusProgressSnapshot>(
      key: ValueKey(_retry),
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('विषय')),
            body: ErrorState(
              message: 'विषय लोड करता आला नाही.\n${snapshot.error}',
              onRetry: _reload,
            ),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('विषय')),
            body: const LoadingState(),
          );
        }
        final row = snapshot.data!.subjectById(widget.subjectId);
        if (row == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('विषय')),
            body: const EmptyState(
              message: 'हा विषय प्रकाशित नाही किंवा टॉपिक नाहीत.',
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(row.subject.title)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${row.completedTopics} / ${row.totalTopics} टॉपिक · '
                '${row.percent.round()}% · ${row.statusLabel}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: row.totalTopics == 0
                      ? 0
                      : row.completedTopics / row.totalTopics,
                  minHeight: 8,
                  backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                  color: AppColors.sky,
                ),
              ),
              if (_saveError != null) ...[
                const SizedBox(height: 10),
                Text(_saveError!, style: const TextStyle(color: Colors.red)),
                TextButton.icon(
                  onPressed: () {
                    final id = _failedChapterId;
                    final status = _failedStatus;
                    if (id == null || status == null) {
                      _reload();
                      return;
                    }
                    SyllabusTopicProgress? topic;
                    for (final t in row.topics) {
                      if (t.chapterId == id) topic = t;
                    }
                    if (topic == null) {
                      _reload();
                      return;
                    }
                    _setStatus(topic, status);
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('पुन्हा प्रयत्न करा'),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'प्रकरण → टॉपिक',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'प्रत्येक टॉपिकची स्थिती बदला. पूर्ण केल्यास आजच्या प्लॅनतील संबंधित कामे पूर्ण होतात.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              if (row.topics.isEmpty)
                const EmptyState(message: 'या विषयात प्रकाशित टॉपिक नाहीत.')
              else
                for (final topic in row.topics)
                  _TopicStatusCard(
                    topic: topic,
                    busy: _busy.contains(topic.chapterId),
                    onStatus: (status) => _setStatus(topic, status),
                    onOpen: () => openSyllabusTopicNotes(context, topic),
                    onRevise: topic.isCompleted
                        ? () => openSyllabusRevision(context)
                        : null,
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _TopicStatusCard extends StatelessWidget {
  const _TopicStatusCard({
    required this.topic,
    required this.busy,
    required this.onStatus,
    required this.onOpen,
    this.onRevise,
  });

  final SyllabusTopicProgress topic;
  final bool busy;
  final ValueChanged<SyllabusTopicStatus> onStatus;
  final VoidCallback onOpen;
  final VoidCallback? onRevise;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _StatusGlyph(status: topic.status),
              title: Text(
                topic.chapterTitle,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                [
                  topic.status == SyllabusTopicStatus.completed
                      ? 'पूर्ण'
                      : topic.status == SyllabusTopicStatus.inProgress
                          ? 'सुरू आहे'
                          : 'सुरू नाही',
                  if (topic.lastStudiedAt != null)
                    'शेवट: ${_shortDate(topic.lastStudiedAt!)}',
                  if (topic.revisionCount > 0)
                    'पुनरावृत्ती ${topic.revisionCount}',
                  if (topic.studyMinutes > 0) '${topic.studyMinutes} मि',
                ].join(' · '),
              ),
              trailing: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'नोट्स',
                      onPressed: onOpen,
                      icon: const Icon(Icons.menu_book_outlined),
                    ),
            ),
            Wrap(
              spacing: 6,
              children: [
                _StatusChip(
                  label: 'सुरू नाही',
                  selected: topic.status == SyllabusTopicStatus.pending,
                  onTap: busy
                      ? null
                      : () => onStatus(SyllabusTopicStatus.pending),
                ),
                _StatusChip(
                  label: 'सुरू आहे',
                  selected: topic.status == SyllabusTopicStatus.inProgress,
                  onTap: busy
                      ? null
                      : () => onStatus(SyllabusTopicStatus.inProgress),
                ),
                _StatusChip(
                  label: 'पूर्ण',
                  selected: topic.status == SyllabusTopicStatus.completed,
                  onTap: busy
                      ? null
                      : () => onStatus(SyllabusTopicStatus.completed),
                ),
                if (onRevise != null)
                  TextButton(
                    onPressed: onRevise,
                    child: const Text('पुनरावृत्ती'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _shortDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}

class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.status});

  final SyllabusTopicStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case SyllabusTopicStatus.completed:
        return const Icon(Icons.check_circle_rounded, color: Colors.green);
      case SyllabusTopicStatus.inProgress:
        return const Icon(Icons.timelapse_rounded, color: AppColors.orange);
      case SyllabusTopicStatus.pending:
        return Icon(
          Icons.circle_outlined,
          color: AppColors.textSecondary.withValues(alpha: 0.8),
        );
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap!(),
      selectedColor: AppColors.sky.withValues(alpha: 0.18),
      checkmarkColor: AppColors.navy,
    );
  }
}
