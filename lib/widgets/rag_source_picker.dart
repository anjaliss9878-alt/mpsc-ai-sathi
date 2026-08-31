import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Reusable NotebookLM-style source picker for AI Teacher / Ask AI.
class RagSourcePicker extends StatelessWidget {
  const RagSourcePicker({
    super.key,
    required this.sources,
    required this.filter,
    required this.onChanged,
  });

  final List<RagSource> sources;
  final RagSourceFilter filter;
  final ValueChanged<RagSourceFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = filter.sourceIds.toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All published'),
              selected: filter.scope == RagSourceScope.allPublished,
              onSelected: (_) => onChanged(const RagSourceFilter()),
            ),
            ChoiceChip(
              label: const Text('Selected sources'),
              selected: filter.scope == RagSourceScope.selectedSources,
              onSelected: (_) => onChanged(
                filter.copyWith(
                  scope: RagSourceScope.selectedSources,
                  sourceIds: selected.isEmpty
                      ? sources.map((s) => s.id).toList()
                      : selected.toList(),
                ),
              ),
            ),
            ChoiceChip(
              label: const Text('Subject / chapter'),
              selected: filter.scope == RagSourceScope.subjectChapter,
              onSelected: (_) => onChanged(
                filter.copyWith(scope: RagSourceScope.subjectChapter),
              ),
            ),
          ],
        ),
        if (filter.scope == RagSourceScope.selectedSources) ...[
          const SizedBox(height: 10),
          ...sources.map((s) {
            final on = selected.contains(s.id);
            return CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: on,
              title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  ragSourceTypeLabel(s.sourceType),
                  if (s.subject.isNotEmpty) s.subject,
                  if (s.chapter.isNotEmpty) s.chapter,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              onChanged: (v) {
                final next = {...selected};
                if (v == true) {
                  next.add(s.id);
                } else {
                  next.remove(s.id);
                }
                onChanged(
                  filter.copyWith(
                    scope: RagSourceScope.selectedSources,
                    sourceIds: next.toList(),
                  ),
                );
              },
            );
          }),
        ],
        if (filter.scope == RagSourceScope.subjectChapter) ...[
          const SizedBox(height: 10),
          _FilterField(
            label: 'Subject',
            value: filter.subject,
            onChanged: (v) => onChanged(filter.copyWith(subject: v)),
          ),
          const SizedBox(height: 8),
          _FilterField(
            label: 'Chapter',
            value: filter.chapter,
            onChanged: (v) => onChanged(filter.copyWith(chapter: v)),
          ),
        ],
      ],
    );
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
    );
  }
}
