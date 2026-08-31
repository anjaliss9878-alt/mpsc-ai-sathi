import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:mpsc_combine_ai/models/rag_study_pack.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/rag_citation_block.dart';

Future<void> showRagStudySheet({
  required BuildContext context,
  required String title,
  required Widget child,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final height = MediaQuery.sizeOf(ctx).height * 0.82;
      return SafeArea(
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: child),
            ],
          ),
        ),
      );
    },
  );
}

class RagSummaryView extends StatelessWidget {
  const RagSummaryView({super.key, required this.summary});

  final RagSourceSummary summary;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _MdSection(title: 'Detailed Summary', body: summary.detailed),
        _MdSection(title: 'Short Notes', body: summary.shortNotes),
        _MdSection(title: '5-Minute Revision', body: summary.fiveMinuteRevision),
        _BulletSection(title: 'Important Facts', items: summary.importantFacts),
        _BulletSection(title: 'Exam Points', items: summary.examPoints),
        _BulletSection(title: 'Common Mistakes', items: summary.commonMistakes),
        RagCitationBlock(citations: summary.citations),
      ],
    );
  }
}

class RagMcqView extends StatefulWidget {
  const RagMcqView({super.key, required this.questions});

  final List<RagGeneratedMcq> questions;

  @override
  State<RagMcqView> createState() => _RagMcqViewState();
}

class _RagMcqViewState extends State<RagMcqView> {
  int _index = 0;
  int? _picked;

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) {
      return const _EmptyHint(
        'निवडलेल्या स्रोतांमध्ये या प्रश्नाचे पुरेसे संदर्भ उपलब्ध नाहीत.',
      );
    }
    final q = widget.questions[_index];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          'Q${_index + 1}/${widget.questions.length} · ${q.difficulty} · ${q.topic}',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          q.question,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < q.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: () => setState(() => _picked = i),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: _optionColor(q, i),
                side: BorderSide(color: _optionColor(q, i)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              child: Text('${String.fromCharCode(65 + i)}. ${q.options[i]}'),
            ),
          ),
        if (_picked != null) ...[
          const SizedBox(height: 8),
          Text(
            'उत्तर: ${String.fromCharCode(65 + q.correctIndex)}. ${q.options[q.correctIndex]}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(q.explanation, style: const TextStyle(height: 1.4)),
          RagCitationBlock(citations: q.citations),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(
              onPressed: _index == 0
                  ? null
                  : () => setState(() {
                        _index--;
                        _picked = null;
                      }),
              child: const Text('Previous'),
            ),
            const Spacer(),
            TextButton(
              onPressed: _index >= widget.questions.length - 1
                  ? null
                  : () => setState(() {
                        _index++;
                        _picked = null;
                      }),
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }

  Color _optionColor(RagGeneratedMcq q, int i) {
    if (_picked == null) return AppColors.navy;
    if (i == q.correctIndex) return Colors.green.shade800;
    if (i == _picked) return Colors.red.shade700;
    return AppColors.navy;
  }
}

class RagFlashcardDeck extends StatefulWidget {
  const RagFlashcardDeck({super.key, required this.cards});

  final List<RagFlashcard> cards;

  @override
  State<RagFlashcardDeck> createState() => _RagFlashcardDeckState();
}

class _RagFlashcardDeckState extends State<RagFlashcardDeck> {
  int _index = 0;
  bool _showBack = false;
  final _difficult = <int>{};
  bool _reviewDifficultOnly = false;

  List<int> get _queue {
    if (!_reviewDifficultOnly) {
      return [for (var i = 0; i < widget.cards.length; i++) i];
    }
    final d = _difficult.toList()..sort();
    return d.isEmpty ? [for (var i = 0; i < widget.cards.length; i++) i] : d;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) {
      return const _EmptyHint(
        'निवडलेल्या स्रोतांमध्ये या प्रश्नाचे पुरेसे संदर्भ उपलब्ध नाहीत.',
      );
    }
    final queue = _queue;
    if (_index >= queue.length) _index = 0;
    final cardIndex = queue[_index];
    final card = widget.cards[cardIndex];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          'Card ${_index + 1}/${queue.length}',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.navy.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.front,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  height: 1.4,
                ),
              ),
              if (_showBack) ...[
                const Divider(height: 24),
                Text(card.back, style: const TextStyle(height: 1.45, fontSize: 15.5)),
                if (card.explanation.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    card.explanation,
                    style: const TextStyle(
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                RagCitationBlock(citations: card.citations),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: Text(_showBack ? 'Hide answer' : 'Show answer'),
              onPressed: () => setState(() => _showBack = !_showBack),
            ),
            ActionChip(
              avatar: const Icon(Icons.chevron_left_rounded, size: 18),
              label: const Text('Previous'),
              onPressed: () => setState(() {
                _index = (_index - 1 + queue.length) % queue.length;
                _showBack = false;
              }),
            ),
            ActionChip(
              avatar: const Icon(Icons.chevron_right_rounded, size: 18),
              label: const Text('Next'),
              onPressed: () => setState(() {
                _index = (_index + 1) % queue.length;
                _showBack = false;
              }),
            ),
            ActionChip(
              avatar: Icon(
                _difficult.contains(cardIndex)
                    ? Icons.flag_rounded
                    : Icons.flag_outlined,
                size: 18,
              ),
              label: Text(
                _difficult.contains(cardIndex) ? 'Marked difficult' : 'Mark difficult',
              ),
              onPressed: () => setState(() {
                if (!_difficult.add(cardIndex)) _difficult.remove(cardIndex);
              }),
            ),
            ActionChip(
              label: Text(
                _reviewDifficultOnly ? 'Review all' : 'Review again',
              ),
              onPressed: () => setState(() {
                _reviewDifficultOnly = !_reviewDifficultOnly;
                _index = 0;
                _showBack = false;
              }),
            ),
          ],
        ),
      ],
    );
  }
}

class RagRevisionView extends StatelessWidget {
  const RagRevisionView({super.key, required this.revision});

  final RagQuickRevision revision;

  @override
  Widget build(BuildContext context) {
    final empty = revision.keyFacts.isEmpty &&
        revision.terms.isEmpty &&
        revision.dates.isEmpty &&
        revision.articles.isEmpty &&
        revision.committees.isEmpty &&
        revision.personalities.isEmpty &&
        revision.examTraps.isEmpty;
    if (empty) {
      return const _EmptyHint(
        'निवडलेल्या स्रोतांमध्ये या प्रश्नाचे पुरेसे संदर्भ उपलब्ध नाहीत.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _BulletSection(title: 'Key facts', items: revision.keyFacts),
        _BulletSection(title: 'Important terms', items: revision.terms),
        _BulletSection(title: 'Dates', items: revision.dates),
        _BulletSection(title: 'Articles', items: revision.articles),
        _BulletSection(title: 'Committees', items: revision.committees),
        _BulletSection(title: 'Personalities', items: revision.personalities),
        _BulletSection(title: 'Exam traps', items: revision.examTraps),
        RagCitationBlock(citations: revision.citations),
      ],
    );
  }
}

class RagMemoryTricksView extends StatelessWidget {
  const RagMemoryTricksView({super.key, required this.tricks});

  final List<RagMemoryTrick> tricks;

  @override
  Widget build(BuildContext context) {
    if (tricks.isEmpty) {
      return const _EmptyHint(
        'निवडलेल्या स्रोतांमध्ये या प्रश्नाचे पुरेसे संदर्भ उपलब्ध नाहीत.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final t in tricks) ...[
          Text(t.trick, style: const TextStyle(height: 1.45, fontSize: 15)),
          RagCitationBlock(citations: t.citations),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class RagPyqView extends StatelessWidget {
  const RagPyqView({super.key, required this.items});

  final List<RagVerifiedPyq> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyHint('निवडलेल्या स्रोतांमध्ये संबंधित PYQ उपलब्ध नाहीत.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final p in items) ...[
          if (p.year != null || p.examName.isNotEmpty)
            Text(
              [
                if (p.year != null) '${p.year}',
                if (p.examName.isNotEmpty) p.examName,
              ].join(' · '),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            p.question,
            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4),
          ),
          if (p.answer.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('उत्तर: ${p.answer}', style: const TextStyle(height: 1.4)),
          ],
          if (p.explanation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(p.explanation, style: const TextStyle(height: 1.4)),
          ],
          RagCitationBlock(citations: p.citations),
          const Divider(height: 28),
        ],
      ],
    );
  }
}

class _MdSection extends StatelessWidget {
  const _MdSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    if (body.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 6),
          MarkdownBody(data: body, selectable: true),
        ],
      ),
    );
  }
}

class _BulletSection extends StatelessWidget {
  const _BulletSection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 6),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $item', style: const TextStyle(height: 1.4)),
            ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(height: 1.45)),
      ),
    );
  }
}
