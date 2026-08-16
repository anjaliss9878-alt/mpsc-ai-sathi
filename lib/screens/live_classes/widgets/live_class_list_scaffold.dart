import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/live_class_item.dart';
import 'package:mpsc_combine_ai/screens/live_classes/live_class_join_screen.dart';
import 'package:mpsc_combine_ai/screens/live_classes/widgets/live_class_card.dart';
import 'package:mpsc_combine_ai/services/live_class_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Shared list screen used by Upcoming/Live Now/Recorded — each just
/// supplies a [filter]/[sort] over the same `liveClasses` stream so the
/// three screens stay pixel-consistent without duplicating boilerplate.
class LiveClassListScaffold extends StatelessWidget {
  const LiveClassListScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.emptyMessage,
    required this.filter,
    this.sort,
  });

  final String title;
  final IconData icon;
  final String emptyMessage;
  final bool Function(LiveClassItem item) filter;
  final int Function(LiveClassItem a, LiveClassItem b)? sort;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
      body: SafeArea(
        child: StreamBuilder<List<LiveClassItem>>(
          stream: liveClassRepository.watchAll(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorState(message: 'लोड करता आले नाही. (Could not load: ${snapshot.error})');
            }
            if (!snapshot.hasData) return const LoadingState();

            final items = snapshot.data!.where(filter).toList();
            if (sort != null) items.sort(sort);

            if (items.isEmpty) {
              return EmptyState(message: emptyMessage, icon: icon);
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return LiveClassCard(
                  item: item,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LiveClassJoinScreen(liveClassId: item.id),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
