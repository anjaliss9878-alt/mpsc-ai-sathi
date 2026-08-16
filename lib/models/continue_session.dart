/// A "Continue Learning" resume card stored at
/// `students/{uid}/continueLearning/{id}`.
class ContinueSession {
  const ContinueSession({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.progress,
    this.payload = const {},
    this.updatedAt,
  });

  /// One of: `notes`, `mcq`, `classroom`, `current_affairs`, `test`, `revision`.
  final String id;
  final String type;
  final String title;
  final String subtitle;
  final double progress;
  final Map<String, dynamic> payload;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() => {
        'type': type,
        'title': title,
        'subtitle': subtitle,
        'progress': progress,
        'payload': payload,
        'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  factory ContinueSession.fromMap(Map<String, dynamic> map, String id) {
    return ContinueSession(
      id: id,
      type: map['type'] as String? ?? '',
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      progress: (map['progress'] as num?)?.toDouble() ?? 0,
      payload: Map<String, dynamic>.from(map['payload'] as Map? ?? const {}),
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? ''),
    );
  }
}
