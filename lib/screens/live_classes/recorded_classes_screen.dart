import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/live_classes/widgets/live_class_list_scaffold.dart';

class RecordedClassesScreen extends StatelessWidget {
  const RecordedClassesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveClassListScaffold(
      title: 'Recorded Classes',
      icon: Icons.smart_display_rounded,
      emptyMessage: 'अजून कोणतेही रेकॉर्डिंग उपलब्ध नाही.\n(No recordings available yet.)',
      filter: (item) => item.status == 'completed',
      sort: (a, b) => b.scheduledAt.compareTo(a.scheduledAt),
    );
  }
}
