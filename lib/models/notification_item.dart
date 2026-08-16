import 'package:mpsc_combine_ai/utils/json_list.dart';

/// A push/in-app notification composed from the Admin Panel, stored at
/// `notifications/{id}` (the send record) and fanned out to
/// `students/{uid}/inbox/{id}` for every targeted student.
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.targetType,
    required this.targetUids,
    required this.createdAt,
    required this.sentByEmail,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String body;

  /// `all` or `selected`.
  final String targetType;

  /// Only populated when [targetType] is `selected`.
  final List<String> targetUids;
  final DateTime createdAt;
  final String sentByEmail;

  /// Only meaningful on a student's own inbox copy.
  final bool isRead;

  factory NotificationItem.fromMap(Map<String, dynamic> map, String id) {
    return NotificationItem(
      id: id,
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      targetType: map['targetType'] as String? ?? 'all',
      targetUids: asStringList(map['targetUids']),
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      sentByEmail: map['sentByEmail'] as String? ?? '',
      isRead: map['isRead'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'body': body,
      'targetType': targetType,
      'targetUids': targetUids,
      'createdAt': createdAt.toIso8601String(),
      'sentByEmail': sentByEmail,
      'isRead': isRead,
    };
  }
}
