import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// 📚 Sources — Subject → Chapter → Topic → Page (omits unknown pages).
class RagCitationBlock extends StatelessWidget {
  const RagCitationBlock({super.key, required this.citations});

  final List<RagCitation> citations;

  @override
  Widget build(BuildContext context) {
    if (citations.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📚 Sources',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < citations.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Text(
              citations[i].breadcrumb,
              style: const TextStyle(
                height: 1.35,
                fontSize: 12.5,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String citationsShareText(List<RagCitation> citations) {
  if (citations.isEmpty) return '';
  final buf = StringBuffer('\n\n📚 Sources\n');
  for (final c in citations) {
    buf.writeln(c.breadcrumb.replaceAll('\n→ ', ' → '));
  }
  return buf.toString();
}
