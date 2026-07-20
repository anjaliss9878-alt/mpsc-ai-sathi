import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/current_affair_item.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/date_format.dart';
import 'package:mpsc_combine_ai/widgets/feature_screen_scaffold.dart';

class CurrentAffairsScreen extends StatelessWidget {
  const CurrentAffairsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CurrentAffairItem>>(
      stream: currentAffairsRepository.watchAll(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <CurrentAffairItem>[];
        return FeatureScreenScaffold(
          title: 'Daily Current Affairs',
          icon: Icons.newspaper_rounded,
          description:
              'Stay updated with daily current affairs, monthly digests, and exam-focused news summaries.',
          isLoading: !snapshot.hasData && !snapshot.hasError,
          emptyMessage: snapshot.hasError
              ? 'चालू घडामोडी लोड करता आल्या नाहीत. (Could not load current affairs.)'
              : 'Tap an entry to read the full summary.',
          items: snapshot.hasError
              ? const [
                  PlaceholderListItem(
                    title: 'Could not load current affairs',
                    subtitle: 'Please check your connection and try again.',
                    icon: Icons.cloud_off_rounded,
                  ),
                ]
              : items.isEmpty
                  ? const [
                      PlaceholderListItem(
                        title: 'No current affairs yet',
                        subtitle: 'Check back soon for daily updates.',
                        icon: Icons.inbox_rounded,
                      ),
                    ]
                  : items
                      .map(
                        (item) => PlaceholderListItem(
                          title: item.title,
                          subtitle: '${formatShortDate(item.date)} · ${item.category}',
                          icon: Icons.today_rounded,
                          onTap: () => _showDetail(context, item),
                        ),
                      )
                      .toList(),
        );
      },
    );
  }

  void _showDetail(BuildContext context, CurrentAffairItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.category,
                    style: const TextStyle(
                      color: AppColors.orange,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  formatLongDate(item.date),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 16),
                Text(
                  item.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
