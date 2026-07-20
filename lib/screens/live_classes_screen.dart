import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/live_class_item.dart';
import 'package:mpsc_combine_ai/services/link_launcher.dart';
import 'package:mpsc_combine_ai/services/live_class_repository.dart';
import 'package:mpsc_combine_ai/widgets/feature_screen_scaffold.dart';

IconData _iconForStatus(String status) {
  switch (status) {
    case 'live':
      return Icons.podcasts_rounded;
    case 'completed':
      return Icons.smart_display_rounded;
    case 'upcoming':
    default:
      return Icons.event_rounded;
  }
}

String _labelForStatus(String status) {
  switch (status) {
    case 'live':
      return 'LIVE NOW';
    case 'completed':
      return 'Recorded';
    case 'upcoming':
    default:
      return 'Upcoming';
  }
}

class LiveClassesScreen extends StatelessWidget {
  const LiveClassesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LiveClassItem>>(
      stream: liveClassRepository.watchAll(),
      builder: (context, snapshot) {
        final items = List<LiveClassItem>.from(snapshot.data ?? const []);
        // Live first, then upcoming, then completed.
        const order = {'live': 0, 'upcoming': 1, 'completed': 2};
        items.sort(
          (a, b) => (order[a.status] ?? 3).compareTo(order[b.status] ?? 3),
        );

        return FeatureScreenScaffold(
          title: 'Live Classes',
          icon: Icons.live_tv_rounded,
          description:
              'Join live, interactive MPSC Combine classes with expert faculty and revise with recorded sessions.',
          isLoading: !snapshot.hasData && !snapshot.hasError,
          emptyMessage: snapshot.hasError
              ? 'लाइव्ह वर्ग लोड करता आले नाहीत. (Could not load live classes.)'
              : 'Tap a class to join or watch the recording.',
          items: snapshot.hasError
              ? const [
                  PlaceholderListItem(
                    title: 'Could not load live classes',
                    subtitle: 'Please check your connection and try again.',
                    icon: Icons.cloud_off_rounded,
                  ),
                ]
              : items.isEmpty
                  ? const [
                      PlaceholderListItem(
                        title: 'No live classes scheduled',
                        subtitle: 'Check back soon for upcoming sessions.',
                        icon: Icons.inbox_rounded,
                      ),
                    ]
                  : items
                      .map(
                        (item) => PlaceholderListItem(
                          title: item.title,
                          subtitle:
                              '${_labelForStatus(item.status)} · ${item.subject} · ${item.scheduleText}',
                          icon: _iconForStatus(item.status),
                          onTap: item.meetingUrl.isEmpty
                              ? null
                              : () => openExternalLink(context, item.meetingUrl),
                        ),
                      )
                      .toList(),
        );
      },
    );
  }
}
