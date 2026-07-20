/// A study video entry (stored as a link, no file upload), stored in
/// Firestore at `videos/{id}`.
class VideoItem {
  const VideoItem({
    required this.id,
    required this.title,
    required this.subject,
    required this.videoUrl,
    required this.description,
  });

  final String id;
  final String title;
  final String subject;
  final String videoUrl;
  final String description;

  factory VideoItem.fromMap(Map<String, dynamic> map, String id) {
    return VideoItem(
      id: id,
      title: map['title'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      videoUrl: map['videoUrl'] as String? ?? '',
      description: map['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subject': subject,
      'videoUrl': videoUrl,
      'description': description,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}
