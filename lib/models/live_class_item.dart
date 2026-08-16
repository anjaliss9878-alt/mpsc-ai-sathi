/// A live class entry, stored in Firestore at `liveClasses/{id}`.
///
/// Joining today always falls back to a plain external [meetingUrl]
/// (Zoom/Meet/YouTube Live) opened via `link_launcher.dart` — see
/// `live_class_video_service.dart` for the seam that lets a real video SDK
/// (100ms) take over the "Join" flow later without any model/UI change.
/// [roomId] is reserved for that later step and is simply unused today.
class LiveClassItem {
  LiveClassItem({
    required this.id,
    required this.title,
    required this.subject,
    required this.meetingUrl,
    required this.platform,
    required this.scheduleText,
    required this.status,
    this.description = '',
    this.facultyId = '',
    this.facultyName = '',
    this.bannerImageUrl = '',
    this.roomId = '',
    this.recordingUrl = '',
    this.notesUrl = '',
    this.durationMinutes = 60,
    this.attendanceCount = 0,
    DateTime? scheduledAt,
  }) : scheduledAt = scheduledAt ?? _epoch;

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String title;
  final String subject;
  final String meetingUrl;
  final String platform;

  /// Free-text schedule shown to students (e.g. "Today, 7:00 PM") — kept
  /// alongside [scheduledAt] so admins can still add a human-friendly note
  /// (e.g. "Recurring every Monday") without fighting the date picker.
  final String scheduleText;

  /// One of: upcoming, live, completed.
  final String status;

  final String description;

  /// Optional link to a `faculty/{id}` document; [facultyName] is
  /// denormalized alongside it so student screens never need a second read.
  final String facultyId;
  final String facultyName;

  /// Shown as the class's card/home banner image.
  final String bannerImageUrl;

  /// Reserved for a future 100ms room id — empty until that SDK is wired in.
  final String roomId;

  /// Playback link for a completed/recorded class.
  final String recordingUrl;

  /// Optional class notes PDF / Storage URL.
  final String notesUrl;

  /// Real start time — powers the Join screen's countdown. Falls back to
  /// the Unix epoch (clearly "unscheduled") if never set.
  final DateTime scheduledAt;

  final int durationMinutes;

  /// Reserved for a future cached attendance count. The live count is
  /// always derived from `liveClassAttendance` (see
  /// `LiveClassAttendanceRepository.watchForClass`) rather than written
  /// here, since only admins may write to this document.
  final int attendanceCount;

  DateTime get scheduledEnd => scheduledAt.add(Duration(minutes: durationMinutes));
  bool get hasSchedule => scheduledAt.millisecondsSinceEpoch > 0;

  factory LiveClassItem.fromMap(Map<String, dynamic> map, String id) {
    return LiveClassItem(
      id: id,
      title: map['title'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      meetingUrl: map['meetingUrl'] as String? ?? '',
      platform: map['platform'] as String? ?? 'Google Meet',
      scheduleText: map['scheduleText'] as String? ?? '',
      status: map['status'] as String? ?? 'upcoming',
      description: map['description'] as String? ?? '',
      facultyId: map['facultyId'] as String? ?? '',
      facultyName: map['facultyName'] as String? ?? '',
      bannerImageUrl: map['bannerImageUrl'] as String? ?? '',
      roomId: map['roomId'] as String? ?? '',
      recordingUrl: map['recordingUrl'] as String? ?? '',
      notesUrl: map['notesUrl'] as String? ?? '',
      durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? 60,
      attendanceCount: (map['attendanceCount'] as num?)?.toInt() ?? 0,
      scheduledAt: DateTime.tryParse(map['scheduledAt'] as String? ?? ''),
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
      'description': description,
      'facultyId': facultyId,
      'facultyName': facultyName,
      'bannerImageUrl': bannerImageUrl,
      'roomId': roomId,
      'recordingUrl': recordingUrl,
      'notesUrl': notesUrl,
      'durationMinutes': durationMinutes,
      'attendanceCount': attendanceCount,
      'scheduledAt': scheduledAt.toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  LiveClassItem copyWith({int? attendanceCount}) {
    return LiveClassItem(
      id: id,
      title: title,
      subject: subject,
      meetingUrl: meetingUrl,
      platform: platform,
      scheduleText: scheduleText,
      status: status,
      description: description,
      facultyId: facultyId,
      facultyName: facultyName,
      bannerImageUrl: bannerImageUrl,
      roomId: roomId,
      recordingUrl: recordingUrl,
      notesUrl: notesUrl,
      durationMinutes: durationMinutes,
      attendanceCount: attendanceCount ?? this.attendanceCount,
      scheduledAt: scheduledAt,
    );
  }
}

const List<String> liveClassStatuses = ['upcoming', 'live', 'completed'];
const List<String> liveClassPlatforms = [
  'Google Meet',
  'Zoom',
  'YouTube Live',
  'Other',
];
