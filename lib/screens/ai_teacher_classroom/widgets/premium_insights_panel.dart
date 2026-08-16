import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/classroom_theme.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/teaching_sequence.dart';

/// MPSC premium pack shown after topics — PYQ, tips, mistakes, revision.
/// Safe no-op UI when [lesson.premium] is empty (older lessons).
///
/// During concept teaching, [spotlight] highlights the live card being narrated.
class PremiumInsightsPanel extends StatelessWidget {
  const PremiumInsightsPanel({
    super.key,
    required this.lesson,
    this.spotlight = PremiumSpotlight.none,
    this.spotlightText = '',
  });

  final GeneratedLesson lesson;
  final PremiumSpotlight spotlight;
  final String spotlightText;

  @override
  Widget build(BuildContext context) {
    final p = lesson.premium;
    final showLiveCue = spotlight != PremiumSpotlight.none &&
        spotlightText.trim().isNotEmpty;

    if (!p.hasContent && !showLiveCue) {
      return const SizedBox.shrink();
    }

    final sections = <_Section>[
      if (p.pyqInsight.isNotEmpty || spotlight == PremiumSpotlight.pyq)
        _Section(
          'PYQ Insight',
          Icons.history_edu_rounded,
          p.pyqInsight.isNotEmpty
              ? p.pyqInsight
              : [spotlightText],
          PremiumSpotlight.pyq,
        ),
      if (p.examTips.isNotEmpty || spotlight == PremiumSpotlight.examTip)
        _Section(
          'Exam Tips',
          Icons.lightbulb_rounded,
          p.examTips.isNotEmpty ? p.examTips : [spotlightText],
          PremiumSpotlight.examTip,
        ),
      if (p.commonMistakes.isNotEmpty ||
          spotlight == PremiumSpotlight.commonMistake)
        _Section(
          'Common Mistakes',
          Icons.warning_amber_rounded,
          p.commonMistakes.isNotEmpty ? p.commonMistakes : [spotlightText],
          PremiumSpotlight.commonMistake,
        ),
      if (p.memoryTricks.isNotEmpty ||
          spotlight == PremiumSpotlight.memoryTrick)
        _Section(
          'Memory Tricks',
          Icons.psychology_alt_rounded,
          p.memoryTricks.isNotEmpty ? p.memoryTricks : [spotlightText],
          PremiumSpotlight.memoryTrick,
        ),
      if (p.importantFacts.isNotEmpty)
        _Section(
          'Important Facts',
          Icons.star_rounded,
          p.importantFacts,
          PremiumSpotlight.none,
        ),
      if (spotlight == PremiumSpotlight.aiMcq || lesson.mcqs.isNotEmpty)
        _Section(
          'AI MCQ',
          Icons.quiz_rounded,
          [
            if (spotlightText.trim().isNotEmpty) spotlightText.trim(),
            '${lesson.mcqs.length} practice MCQs ready',
          ].where((e) => e.trim().isNotEmpty).toList(),
          PremiumSpotlight.aiMcq,
        ),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: ClassroomTheme.softCard,
        borderRadius: ClassroomTheme.radiusLg,
        boxShadow: ClassroomTheme.softShadow,
        border: Border.all(
          color: showLiveCue
              ? ClassroomTheme.sky.withValues(alpha: 0.45)
              : ClassroomTheme.sky.withValues(alpha: 0.12),
          width: showLiveCue ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ClassroomTheme.sky.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.workspace_premium_rounded,
                    color: ClassroomTheme.sky, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'MPSC Premium Pack',
                  style: ClassroomTheme.display(context).copyWith(fontSize: 18),
                ),
              ),
            ],
          ),
          if (showLiveCue) ...[
            const SizedBox(height: 12),
            _LiveSpotlightBanner(
              spotlight: spotlight,
              text: spotlightText.trim(),
            ),
          ],
          const SizedBox(height: 14),
          if (p.onePageSummary.trim().isNotEmpty) ...[
            Text(
              'One Page Summary',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: ClassroomTheme.navy,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              p.onePageSummary.trim(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ClassroomTheme.navyMid,
                    height: 1.45,
                  ),
            ),
            const SizedBox(height: 14),
          ],
          if (p.quickRevision.trim().isNotEmpty) ...[
            Text(
              'Quick Revision',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: ClassroomTheme.navy,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              p.quickRevision.trim(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ClassroomTheme.navyMid,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 14),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final s in sections)
                _ChipCard(
                  section: s,
                  active: s.spotlight == spotlight &&
                      spotlight != PremiumSpotlight.none,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveSpotlightBanner extends StatelessWidget {
  const _LiveSpotlightBanner({required this.spotlight, required this.text});

  final PremiumSpotlight spotlight;
  final String text;

  String get _label {
    switch (spotlight) {
      case PremiumSpotlight.pyq:
        return 'PYQ Insight';
      case PremiumSpotlight.examTip:
        return 'Exam Tip';
      case PremiumSpotlight.memoryTrick:
        return 'Memory Trick';
      case PremiumSpotlight.commonMistake:
        return 'Common Mistake';
      case PremiumSpotlight.aiMcq:
        return 'AI MCQ';
      case PremiumSpotlight.none:
        return 'Insight';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 360),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ClassroomTheme.sky.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ClassroomTheme.sky.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Now teaching · $_label',
            style: const TextStyle(
              color: ClassroomTheme.sky,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              color: ClassroomTheme.navyMid,
              height: 1.4,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section {
  const _Section(this.title, this.icon, this.items, this.spotlight);
  final String title;
  final IconData icon;
  final List<String> items;
  final PremiumSpotlight spotlight;
}

class _ChipCard extends StatelessWidget {
  const _ChipCard({required this.section, this.active = false});
  final _Section section;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, minWidth: 220),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        decoration: BoxDecoration(
          borderRadius: ClassroomTheme.radiusMd,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: ClassroomTheme.sky.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: active
              ? ClassroomTheme.sky.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.85),
          borderRadius: ClassroomTheme.radiusMd,
          child: InkWell(
            borderRadius: ClassroomTheme.radiusMd,
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (context) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(section.icon, color: ClassroomTheme.sky),
                        const SizedBox(width: 8),
                        Text(
                          section.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: ClassroomTheme.navy,
                            fontSize: 17,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final item in section.items) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  ',
                              style: TextStyle(
                                  color: ClassroomTheme.sky,
                                  fontWeight: FontWeight.w800)),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(
                                color: ClassroomTheme.navyMid,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: ClassroomTheme.radiusMd,
                border: Border.all(
                  color: active
                      ? ClassroomTheme.sky.withValues(alpha: 0.55)
                      : Colors.transparent,
                  width: active ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(section.icon, color: ClassroomTheme.sky, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      section.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: ClassroomTheme.navy,
                      ),
                    ),
                  ),
                  Text(
                    '${section.items.length}',
                    style: TextStyle(
                      color: ClassroomTheme.navy.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
