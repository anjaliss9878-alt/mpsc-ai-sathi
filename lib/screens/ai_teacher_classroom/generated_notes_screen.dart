import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Displays the AI-generated revision notes for a lesson — architecture
/// step: "Generate Notes".
class GeneratedNotesScreen extends StatelessWidget {
  const GeneratedNotesScreen({
    super.key,
    required this.topicName,
    required this.summary,
    required this.notes,
  });

  final String topicName;
  final String summary;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Notes · $topicName', style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (summary.trim().isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.fact_check_rounded, color: AppColors.navy, size: 18),
                        SizedBox(width: 8),
                        Text('Summary', style: TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(summary, style: const TextStyle(fontSize: 13.5, height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            const Text('Key Points', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            if (notes.isEmpty)
              const Text('No notes available for this lesson yet.', style: TextStyle(color: AppColors.textSecondary))
            else
              ...notes.map(
                (note) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: AppColors.orange, borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(note, style: const TextStyle(fontSize: 14.5, height: 1.4))),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
