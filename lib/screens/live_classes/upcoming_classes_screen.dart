import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/live_classes/widgets/live_class_list_scaffold.dart';

class UpcomingClassesScreen extends StatelessWidget {
  const UpcomingClassesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveClassListScaffold(
      title: 'Upcoming Classes',
      icon: Icons.event_rounded,
      emptyMessage:
          'सध्या कोणतेही आगामी वर्ग नाहीत.\n(No upcoming classes scheduled right now.)',
      filter: (item) => item.status == 'upcoming',
      sort: (a, b) => a.scheduledAt.compareTo(b.scheduledAt),
    );
  }
}
