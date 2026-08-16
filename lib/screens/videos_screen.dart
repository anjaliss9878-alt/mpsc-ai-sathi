import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/study_plan.dart';
import 'package:mpsc_combine_ai/models/video_item.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/link_launcher.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/video_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key});

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  String? _subjectFilter;
  double _defaultSpeed = 1.0;

  @override
  Widget build(BuildContext context) {
    final uid = authService.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Videos'),
        actions: [
          PopupMenuButton<double>(
            tooltip: 'Default playback speed',
            initialValue: _defaultSpeed,
            onSelected: (v) => setState(() => _defaultSpeed = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 0.75, child: Text('0.75x')),
              PopupMenuItem(value: 1.0, child: Text('1.0x')),
              PopupMenuItem(value: 1.25, child: Text('1.25x')),
              PopupMenuItem(value: 1.5, child: Text('1.5x')),
              PopupMenuItem(value: 2.0, child: Text('2.0x')),
            ],
            icon: const Icon(Icons.speed_rounded),
          ),
        ],
      ),
      body: StreamBuilder<List<VideoItem>>(
        stream: videoRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
              message: 'Could not load videos.\n${snapshot.error}',
            );
          }
          if (!snapshot.hasData) return const LoadingState();

          final all = snapshot.data!;
          final subjects = all
              .map((v) => v.subject.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          final items = _subjectFilter == null
              ? all
              : all.where((v) => v.subject == _subjectFilter).toList();

          return Column(
            children: [
              if (subjects.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All topics'),
                        selected: _subjectFilter == null,
                        onSelected: (_) =>
                            setState(() => _subjectFilter = null),
                      ),
                      const SizedBox(width: 8),
                      ...subjects.map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(s),
                            selected: _subjectFilter == s,
                            onSelected: (_) =>
                                setState(() => _subjectFilter = s),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (uid != null)
                StreamBuilder<List<VideoProgress>>(
                  stream: studentProgressRepository.watchVideoProgress(uid),
                  builder: (context, progSnap) {
                    final cont = (progSnap.data ?? const <VideoProgress>[])
                        .where((p) => !p.completed && p.progress > 0)
                        .take(3)
                        .toList();
                    if (cont.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Continue watching',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          ...cont.map(
                            (p) => ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.play_circle_outline_rounded,
                                color: AppColors.orange,
                              ),
                              title: Text(p.title),
                              subtitle: Text(
                                '${(p.progress * 100).toInt()}% · ${p.playbackSpeed}x',
                              ),
                              onTap: () {
                                final match = all
                                    .where((v) => v.id == p.videoId)
                                    .toList();
                                if (match.isNotEmpty) {
                                  _openVideo(context, match.first, p);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              Expanded(
                child: items.isEmpty
                    ? const EmptyState(
                        message: 'No videos yet.',
                        icon: Icons.smart_display_outlined,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final progressStream = uid == null
                              ? null
                              : studentProgressRepository
                                  .watchOneVideoProgress(uid, item.id);
                          return Card(
                            child: progressStream == null
                                ? _videoTile(context, item, null)
                                : StreamBuilder<VideoProgress?>(
                                    stream: progressStream,
                                    builder: (context, pSnap) =>
                                        _videoTile(context, item, pSnap.data),
                                  ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _videoTile(
    BuildContext context,
    VideoItem item,
    VideoProgress? progress,
  ) {
    final pct = progress?.progress ?? 0;
    final done = progress?.completed ?? false;
    return ListTile(
      leading: Icon(
        done ? Icons.check_circle_rounded : Icons.play_circle_fill_rounded,
        color: done ? Colors.green : AppColors.navy,
      ),
      title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.subject.isEmpty
                ? item.description
                : '${item.subject} · ${item.description}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (pct > 0) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              color: AppColors.orange,
              backgroundColor: AppColors.navy.withValues(alpha: 0.08),
            ),
          ],
        ],
      ),
      isThreeLine: pct > 0,
      trailing: IconButton(
        tooltip: 'Bookmark',
        icon: const Icon(Icons.bookmark_border_rounded),
        onPressed: () async {
          final uid = authService.currentUser?.uid;
          if (uid == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sign in to bookmark videos.')),
            );
            return;
          }
          await studentProgressRepository.toggleBookmark(
            uid: uid,
            id: 'video_${item.id}',
            type: 'video',
            title: item.title,
            subtitle: item.subject,
            refId: item.id,
            meta: {'videoUrl': item.videoUrl},
          );
        },
      ),
      onTap: item.videoUrl.isEmpty
          ? null
          : () => _openVideo(context, item, progress),
    );
  }

  Future<void> _openVideo(
    BuildContext context,
    VideoItem item,
    VideoProgress? existing,
  ) async {
    final uid = authService.currentUser?.uid;
    final speed = existing?.playbackSpeed ?? _defaultSpeed;
    await openExternalLink(context, item.videoUrl);
    if (uid == null) return;
    final nextProgress = ((existing?.progress ?? 0) + 0.25).clamp(0.0, 1.0);
    await studentProgressRepository.upsertVideoProgress(
      uid: uid,
      videoId: item.id,
      title: item.title,
      subject: item.subject,
      progress: nextProgress,
      completed: nextProgress >= 0.95,
      playbackSpeed: speed,
    );
  }
}
