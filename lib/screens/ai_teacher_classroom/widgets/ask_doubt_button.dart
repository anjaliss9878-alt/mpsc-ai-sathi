import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Prominent "Ask Doubt" voice button — the primary, explicit entry point
/// for interrupting the lesson to ask a question. Shares the same local
/// "listening" toggle as the mic button inside [AskQuestionBar] (both drive
/// the same avatar state), so either control works.
class AskDoubtButton extends StatelessWidget {
  const AskDoubtButton({super.key, required this.isListening, required this.onPressed});

  final bool isListening;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: isListening ? AppColors.orange : AppColors.orange.withValues(alpha: 0.12),
          foregroundColor: isListening ? Colors.white : AppColors.orange,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        icon: Icon(isListening ? Icons.graphic_eq_rounded : Icons.mic_rounded),
        label: Text(isListening ? 'Listening… tap to stop' : 'Ask Doubt'),
      ),
    );
  }
}
