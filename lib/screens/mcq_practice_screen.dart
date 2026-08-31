import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/screens/mcq_set_screen.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/feature_screen_scaffold.dart';

/// A group of [McqItem]s sharing the same [McqItem.setTitle] — computed
/// client-side from the flat `mcqs` collection, so the Admin Panel never
/// needs a separate "sets" collection to manage.
class _McqSet {
  _McqSet(this.title) : questions = [];

  final String title;
  final List<McqItem> questions;

  String get subject => questions.isEmpty ? '' : questions.first.subject;
  String get difficulty => questions.isEmpty ? '' : questions.first.difficulty;
}

List<_McqSet> _groupBySet(List<McqItem> items) {
  final map = <String, _McqSet>{};
  for (final item in items) {
    map.putIfAbsent(item.setTitle, () => _McqSet(item.setTitle)).questions.add(item);
  }
  return map.values.toList();
}

class McqPracticeScreen extends StatelessWidget {
  const McqPracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<McqItem>>(
      stream: mcqRepository.watchPublished(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <McqItem>[];
        final sets = _groupBySet(items);

        return FeatureScreenScaffold(
          title: 'MCQ Practice',
          icon: Icons.quiz_rounded,
          description:
              'Practice multiple-choice questions topic-wise with instant feedback to strengthen your preparation.',
          headerAction: Row(
            children: [
              _StatChip(label: 'Sets', value: '${sets.length}'),
              const SizedBox(width: 8),
              _StatChip(label: 'Questions', value: '${items.length}'),
            ],
          ),
          isLoading: !snapshot.hasData && !snapshot.hasError,
          emptyMessage: snapshot.hasError
              ? 'MCQ संच लोड करता आले नाहीत. (Could not load MCQ sets.)'
              : 'Pick a set below to start practicing.',
          items: snapshot.hasError
              ? const [
                  PlaceholderListItem(
                    title: 'Could not load MCQs',
                    subtitle: 'Please check your connection and try again.',
                    icon: Icons.cloud_off_rounded,
                  ),
                ]
              : sets.isEmpty
                  ? const [
                      PlaceholderListItem(
                        title: 'No MCQ sets yet',
                        subtitle: 'Check back soon for new practice sets.',
                        icon: Icons.inbox_rounded,
                      ),
                    ]
                  : sets
                      .map(
                        (set) => PlaceholderListItem(
                          title: set.title,
                          subtitle:
                              '${set.questions.length} questions · ${set.subject}'
                              '${set.difficulty.isNotEmpty ? ' · ${set.difficulty}' : ''}',
                          icon: Icons.gavel_rounded,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => McqSetScreen(
                                  setTitle: set.title,
                                  questions: set.questions,
                                ),
                              ),
                            );
                          },
                        ),
                      )
                      .toList(),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.orange,
                fontSize: 16,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
