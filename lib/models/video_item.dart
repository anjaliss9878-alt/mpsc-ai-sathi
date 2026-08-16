/// A study video entry, stored in Firestore at `videos/{id}`.
///
/// Supports either an uploaded video file (Firebase Storage) or an
/// external YouTube/Vimeo/other link — [sourceType] tells the player which
/// one [videoUrl] points to.
class VideoItem {
  const VideoItem({
    required this.id,
    required this.title,
    required this.subject,
    required this.videoUrl,
    required this.description,
    this.sourceType = 'youtube',
    this.thumbnailUrl = '',
    this.durationSeconds = 0,
    this.isFree = true,
  });

  final String id;
  final String title;
  final String subject;
  final String videoUrl;
  final String description;

  /// One of: `youtube`, `vimeo`, `upload` (Firebase Storage), `other`.
  final String sourceType;

  final String thumbnailUrl;
  final int durationSeconds;

  /// Free videos are visible to every student; paid videos are reserved for
  /// enrolled/paying students once a payment flow exists — the flag is
  /// tracked from day one so no data migration is needed later.
  final bool isFree;

  factory VideoItem.fromMap(Map<String, dynamic> map, String id) {
    return VideoItem(
      id: id,
      title: map['title'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      videoUrl: map['videoUrl'] as String? ?? '',
      description: map['description'] as String? ?? '',
      sourceType: map['sourceType'] as String? ?? 'youtube',
      thumbnailUrl: map['thumbnailUrl'] as String? ?? '',
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      isFree: map['isFree'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subject': subject,
      'videoUrl': videoUrl,
      'description': description,
      'sourceType': sourceType,
      'thumbnailUrl': thumbnailUrl,
      'durationSeconds': durationSeconds,
      'isFree': isFree,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}

const List<String> videoSourceTypes = ['youtube', 'vimeo', 'upload', 'other'];

/// Best-effort YouTube thumbnail URL derived from a `watch?v=`, `youtu.be/`
/// or `embed/` link — used so admins don't have to source a thumbnail image
/// by hand for every YouTube video.
String? youtubeThumbnailFor(String url) {
  final id = youtubeVideoId(url);
  if (id == null) return null;
  return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
}

String? youtubeVideoId(String url) {
  final patterns = [
    RegExp(r'youtu\.be/([\w-]{6,})'),
    RegExp(r'v=([\w-]{6,})'),
    RegExp(r'embed/([\w-]{6,})'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(url);
    if (match != null) return match.group(1);
  }
  return null;
}
