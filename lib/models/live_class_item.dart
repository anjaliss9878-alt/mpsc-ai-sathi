/// A live class entry (stored as a meeting link, no video hosting), stored
/// in Firestore at `liveClasses/{id}`.
class LiveClassItem {
  const LiveClassItem({
    required this.id,
    required this.title,
    required this.subject,
    required this.meetingUrl,
    required this.platform,
    required this.scheduleText,
    required this.status,
  });

  final String id;
  final String title;
  final String subject;
  final String meetingUrl;
  final String platform;

  /// Free-text schedule shown to students (e.g. "Today, 7:00 PM"). Kept as
  /// text rather than a strict DateTime so admins can describe recurring or
  /// approximate schedules without fighting a date picker.
  final String scheduleText;

  /// One of: upcoming, live, completed.
  final String status;

  factory LiveClassItem.fromMap(Map<String, dynamic> map, String id) {
    return LiveClassItem(
      id: id,
      title: map['title'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      meetingUrl: map['meetingUrl'] as String? ?? '',
      platform: map['platform'] as String? ?? 'Google Meet',
      scheduleText: map['scheduleText'] as String? ?? '',
      status: map['status'] as String? ?? 'upcoming',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subject': subject,
      'meetingUrl': meetingUrl,
      'platform': platform,
      'scheduleText': scheduleText,
      'status': status,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}

const List<String> liveClassStatuses = ['upcoming', 'live', 'completed'];
const List<String> liveClassPlatforms = [
  'Google Meet',
  'Zoom',
  'YouTube Live',
  'Other',
];
