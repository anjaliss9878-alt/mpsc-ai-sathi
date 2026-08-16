import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Interactive teaching controls under the AI Video Teacher player.
class TeachingActionBar extends StatelessWidget {
  const TeachingActionBar({
    super.key,
    required this.onExplainAgain,
    required this.onAnotherExample,
    required this.onAskDoubt,
    required this.onMoreMcqs,
    this.enabled = true,
    this.busyLabel,
  });

  final VoidCallback onExplainAgain;
  final VoidCallback onAnotherExample;
  final VoidCallback onAskDoubt;
  final VoidCallback onMoreMcqs;
  final bool enabled;
  final String? busyLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (busyLabel != null && busyLabel!.trim().isNotEmpty) ...[
          Text(
            busyLabel!,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Action(
              icon: Icons.replay_circle_filled_rounded,
              label: 'Explain Again',
              onTap: enabled ? onExplainAgain : null,
            ),
            _Action(
              icon: Icons.lightbulb_outline_rounded,
              label: 'Give Another Example',
              onTap: enabled ? onAnotherExample : null,
            ),
            _Action(
              icon: Icons.help_outline_rounded,
              label: 'Ask Doubt',
              onTap: enabled ? onAskDoubt : null,
            ),
            _Action(
              icon: Icons.quiz_outlined,
              label: 'Generate More MCQs',
              onTap: enabled ? onMoreMcqs : null,
              emphasize: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final bg = emphasize
        ? AppColors.navy.withValues(alpha: 0.08)
        : AppColors.background;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: onTap == null
                    ? AppColors.textSecondary
                    : (emphasize ? AppColors.navy : AppColors.orange),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: onTap == null
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
