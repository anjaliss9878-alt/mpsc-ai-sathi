import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/live_classes/widgets/live_class_list_scaffold.dart';

class LiveNowScreen extends StatelessWidget {
  const LiveNowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveClassListScaffold(
      title: 'Live Now',
      icon: Icons.podcasts_rounded,
      emptyMessage: 'सध्या कोणताही वर्ग लाइव्ह नाही.\n(No class is live right now.)',
      filter: (item) => item.status == 'live',
      sort: (a, b) => a.title.compareTo(b.title),
    );
  }
}
