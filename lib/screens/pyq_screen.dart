import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/services/link_launcher.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/widgets/feature_screen_scaffold.dart';

class PyqScreen extends StatelessWidget {
  const PyqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PyqItem>>(
      stream: pyqRepository.watchAll(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <PyqItem>[];
        return FeatureScreenScaffold(
          title: 'Previous Year Questions',
          icon: Icons.history_edu_rounded,
          description:
              'Solve authentic MPSC Combine previous year question papers with detailed solutions and analysis.',
          isLoading: !snapshot.hasData && !snapshot.hasError,
          emptyMessage: snapshot.hasError
              ? 'प्रश्नपत्रिका लोड करता आल्या नाहीत. (Could not load question papers.)'
              : 'Tap a paper to open it.',
          items: snapshot.hasError
              ? const [
                  PlaceholderListItem(
                    title: 'Could not load PYQs',
                    subtitle: 'Please check your connection and try again.',
                    icon: Icons.cloud_off_rounded,
                  ),
                ]
              : items.isEmpty
                  ? const [
                      PlaceholderListItem(
                        title: 'No question papers yet',
                        subtitle: 'Check back soon for previous year papers.',
                        icon: Icons.inbox_rounded,
                      ),
                    ]
                  : items
                      .map(
                        (item) => PlaceholderListItem(
                          title: item.title,
                          subtitle: item.subtitle,
                          icon: Icons.description_rounded,
                          onTap: item.fileUrl.isEmpty
                              ? null
                              : () => openExternalLink(context, item.fileUrl),
                        ),
                      )
                      .toList(),
        );
      },
    );
  }
}
