import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/smart_trick_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_screen.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/flashcard_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/smart_trick_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Revision hub: smart cards from notes, flashcards, AI summary shortcut,
/// memory tricks, and a revision timer.
class RevisionHubScreen extends StatelessWidget {
  const RevisionHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Revision')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HubTile(
            icon: Icons.style_rounded,
            title: 'Smart Cards',
            subtitle: 'Revision points from your chapter notes',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _SmartCardsScreen()),
            ),
          ),
          _HubTile(
            icon: Icons.flip_rounded,
            title: 'Flashcards',
            subtitle: 'Front/back recall from keywords & points',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _FlashcardsScreen()),
            ),
          ),
          _HubTile(
            icon: Icons.auto_awesome_rounded,
            title: 'AI Summary',
            subtitle: 'Ask AI Teacher for a quick revision summary',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AiTeacherScreen()),
            ),
          ),
          _HubTile(
            icon: Icons.psychology_alt_rounded,
            title: 'Memory Tricks',
            subtitle: 'Mnemonics & recall tips for MPSC topics',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _MemoryTricksScreen()),
            ),
          ),
          _HubTile(
            icon: Icons.timer_rounded,
            title: 'Revision Timer',
            subtitle: 'Pomodoro-style focused revision session',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _RevisionTimerScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: AppColors.navy),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.orange),
        onTap: onTap,
      ),
    );
  }
}

class _RevisionPack {
  _RevisionPack({
    required this.subject,
    required this.chapter,
    required this.note,
  });

  final SubjectItem subject;
  final ChapterItem chapter;
  final NoteItem note;
}

Future<List<_RevisionPack>> _loadRevisionPacks() async {
  final subjects = await notesRepository.watchPublishedSubjects().first;
  final packs = <_RevisionPack>[];
  for (final subject in subjects) {
    final chapters = await notesRepository.watchPublishedChapters(subject.id).first;
    for (final chapter in chapters) {
      final note = await notesRepository.getNoteForChapter(chapter.id);
      if (note == null || !note.published) continue;
      final hasContent = note.revisionSummary.isNotEmpty ||
          note.importantPoints.isNotEmpty ||
          note.keywords.isNotEmpty ||
          note.aiSummary.isNotEmpty ||
          chapter.revisionNotes.isNotEmpty;
      if (!hasContent) continue;
      packs.add(_RevisionPack(subject: subject, chapter: chapter, note: note));
    }
  }
  return packs;
}

Future<void> _markRevisionProgress(String title) async {
  final uid = authService.currentUser?.uid;
  if (uid == null) return;
  try {
    await studentProgressRepository.markGoalTask(
      uid: uid,
      task: 'revision',
      done: true,
      sessionType: 'revision',
      sessionTitle: title,
    );
    await studentProgressRepository.upsertContinueSession(
      uid: uid,
      id: 'revision',
      type: 'revision',
      title: 'Revision',
      subtitle: title,
      progress: 0.5,
    );
  } catch (_) {}
}

class _SmartCardsScreen extends StatelessWidget {
  const _SmartCardsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Cards')),
      body: FutureBuilder<List<_RevisionPack>>(
        future: _loadRevisionPacks(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Could not load cards.\n${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.orange));
          }
          final packs = snapshot.data!;
          if (packs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No revision summaries yet.\nAsk admin to add notes with revision points.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: packs.length,
            itemBuilder: (context, i) {
              final p = packs[i];
              final points = p.note.revisionSummary.isNotEmpty
                  ? p.note.revisionSummary
                  : p.note.importantPoints;
              return Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.style_rounded, color: AppColors.orange),
                  title: Text(p.chapter.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(p.subject.title),
                  children: [
                    ...points.map(
                      (line) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.chevron_right, size: 16),
                        title: Text(line),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _markRevisionProgress(p.chapter.title),
                      child: const Text('Mark revised'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _FlashcardsScreen extends StatefulWidget {
  const _FlashcardsScreen();

  @override
  State<_FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<_FlashcardsScreen> {
  late final Future<List<_FlashCard>> _future = _buildCards();
  int _index = 0;
  bool _flipped = false;

  Future<List<_FlashCard>> _buildCards() async {
    final published = await flashcardRepository.watchPublished().first;
    if (published.isNotEmpty) {
      return [
        for (final c in published)
          _FlashCard(front: c.front, back: c.back, explanation: c.explanation),
      ];
    }
    final packs = await _loadRevisionPacks();
    final cards = <_FlashCard>[];
    for (final p in packs) {
      for (final kw in p.note.keywords) {
        cards.add(
          _FlashCard(
            front: kw,
            back: '${p.chapter.title} · ${p.subject.title}',
          ),
        );
      }
      final points = p.note.importantPoints.isNotEmpty
          ? p.note.importantPoints
          : p.note.revisionSummary;
      for (final point in points.take(8)) {
        cards.add(
          _FlashCard(
            front: p.chapter.title,
            back: point,
          ),
        );
      }
    }
    return cards;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flashcards')),
      body: FutureBuilder<List<_FlashCard>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.orange));
          }
          final cards = snapshot.data!;
          if (cards.isEmpty) {
            return const Center(
              child: Text(
                'No flashcards yet. Add keywords/points to notes in Admin.',
                textAlign: TextAlign.center,
              ),
            );
          }
          final card = cards[_index % cards.length];
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('${(_index % cards.length) + 1} / ${cards.length}'),
                const SizedBox(height: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _flipped = !_flipped),
                    child: Card(
                      color: _flipped
                          ? AppColors.navy.withValues(alpha: 0.06)
                          : Colors.white,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _flipped
                                ? (card.explanation.isNotEmpty
                                    ? '${card.back}\n\n${card.explanation}'
                                    : card.back)
                                : card.front,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Tap card to flip', style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          _index = (_index - 1) < 0 ? cards.length - 1 : _index - 1;
                          _flipped = false;
                        }),
                        child: const Text('Previous'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          setState(() {
                            _index++;
                            _flipped = false;
                          });
                          await _markRevisionProgress('Flashcards');
                        },
                        child: const Text('Next'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FlashCard {
  const _FlashCard({
    required this.front,
    required this.back,
    this.explanation = '',
  });
  final String front;
  final String back;
  final String explanation;
}

class _MemoryTricksScreen extends StatelessWidget {
  const _MemoryTricksScreen();

  static const _fallback = [
    (
      'Polity acronyms',
      'Remember DPSPs with “EQUALITY”: Education, Quotas, Uniform civil code, Alcohol prohibition, Living wage, Integrity of courts, Temp workers, Youth.',
    ),
    (
      'Geography pegs',
      'Link rivers west→east (Narmada/Tapi west; Godavari/Krishna/Kaveri east) using a simple left-right hand map.',
    ),
    (
      'History timelines',
      'Chunk modern India into 1857 → 1885 → 1905 → 1919 → 1942 → 1947 “stepping stones”.',
    ),
    (
      'Economy ratios',
      'Convert % schemes into “per 100 people” stories so numbers stick longer than bare figures.',
    ),
    (
      'Ask AI for mnemonics',
      'Open AI Summary and request a Marathi mnemonic for the exact topic you are revising.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Memory Tricks')),
      body: StreamBuilder<List<SmartTrickItem>>(
        stream: smartTrickRepository.watchPublished(),
        builder: (context, snapshot) {
          final published = snapshot.data ?? const <SmartTrickItem>[];
          if (published.isNotEmpty) {
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: published.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final t = published[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.psychology_alt_rounded,
                      color: AppColors.orange,
                    ),
                    title: Text(
                      t.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        [
                          t.memoryTrick,
                          if (t.explanation.isNotEmpty) t.explanation,
                          if (t.example.isNotEmpty) 'e.g. ${t.example}',
                        ].join('\n'),
                        style: const TextStyle(height: 1.35),
                      ),
                    ),
                    isThreeLine: true,
                    onTap: () => _markRevisionProgress(t.title),
                  ),
                );
              },
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _fallback.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final t = _fallback[i];
              return Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.psychology_alt_rounded,
                    color: AppColors.orange,
                  ),
                  title: Text(
                    t.$1,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(t.$2, style: const TextStyle(height: 1.35)),
                  ),
                  isThreeLine: true,
                  onTap: () => _markRevisionProgress(t.$1),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _RevisionTimerScreen extends StatefulWidget {
  const _RevisionTimerScreen();

  @override
  State<_RevisionTimerScreen> createState() => _RevisionTimerScreenState();
}

class _RevisionTimerScreenState extends State<_RevisionTimerScreen> {
  static const _sessionSeconds = 25 * 60;
  int _remaining = _sessionSeconds;
  Timer? _timer;
  bool _running = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining <= 1) {
        t.cancel();
        setState(() {
          _remaining = 0;
          _running = false;
        });
        _markRevisionProgress('Revision timer complete');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Revision session complete!')),
        );
        return;
      }
      setState(() => _remaining--);
    });
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _remaining = _sessionSeconds;
      _running = false;
    });
  }

  String get _label {
    final m = _remaining ~/ 60;
    final s = _remaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = 1 - (_remaining / _sessionSeconds);
    return Scaffold(
      appBar: AppBar(title: const Text('Revision Timer')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(
              _label,
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 10,
                color: AppColors.orange,
                backgroundColor: AppColors.navy.withValues(alpha: 0.08),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '25-minute focused revision block',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reset,
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _toggle,
                    child: Text(_running ? 'Pause' : 'Start'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
