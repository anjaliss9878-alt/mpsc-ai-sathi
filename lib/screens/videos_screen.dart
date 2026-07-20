import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/video_item.dart';
import 'package:mpsc_combine_ai/services/link_launcher.dart';
import 'package:mpsc_combine_ai/services/video_repository.dart';
import 'package:mpsc_combine_ai/widgets/feature_screen_scaffold.dart';

class VideosScreen extends StatelessWidget {
  const VideosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VideoItem>>(
      stream: videoRepository.watchAll(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <VideoItem>[];
        return FeatureScreenScaffold(
          title: 'Videos',
          icon: Icons.smart_display_rounded,
          description:
              'Watch concept videos and revision lectures curated for the MPSC Combine syllabus.',
          isLoading: !snapshot.hasData && !snapshot.hasError,
          emptyMessage: snapshot.hasError
              ? 'व्हिडिओ लोड करता आले नाहीत. (Could not load videos.)'
              : 'Tap a video to watch it.',
          items: snapshot.hasError
              ? const [
                  PlaceholderListItem(
                    title: 'Could not load videos',
                    subtitle: 'Please check your connection and try again.',
                    icon: Icons.cloud_off_rounded,
                  ),
                ]
              : items.isEmpty
                  ? const [
                      PlaceholderListItem(
                        title: 'No videos yet',
                        subtitle: 'Check back soon for new lectures.',
                        icon: Icons.inbox_rounded,
                      ),
                    ]
                  : items
                      .map(
                        (item) => PlaceholderListItem(
                          title: item.title,
                          subtitle: item.subject.isEmpty
                              ? item.description
                              : '${item.subject} · ${item.description}',
                          icon: Icons.play_circle_fill_rounded,
                          onTap: item.videoUrl.isEmpty
                              ? null
                              : () => openExternalLink(context, item.videoUrl),
                        ),
                      )
                      .toList(),
        );
      },
    );
  }
}
