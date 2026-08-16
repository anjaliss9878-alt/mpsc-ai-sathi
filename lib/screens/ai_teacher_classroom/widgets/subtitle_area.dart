import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Caption/subtitle strip under the avatar — shows the current dummy
/// caption line (during Play) or the last "doubt" question/answer,
/// fading between lines. Shows a neutral hint when there's nothing to
/// display yet.
class SubtitleArea extends StatelessWidget {
  const SubtitleArea({super.key, required this.text, this.label = 'CC'});

  final String? text;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.navyDark.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                (text == null || text!.trim().isEmpty)
                    ? 'Press Play to start the lesson, or tap "Ask Doubt" to ask a question.'
                    : text!,
                key: ValueKey(text),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: text == null ? 0.6 : 0.96),
                  fontSize: 13.5,
                  height: 1.4,
                  fontStyle: text == null ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
