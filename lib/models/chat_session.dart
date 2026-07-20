import 'package:mpsc_combine_ai/models/chat_subject.dart';

/// Metadata for one AI Teacher chat session, stored at
/// `students/{uid}/chats/{id}`. The messages themselves live in the
/// `messages` subcollection underneath (see `ChatRepository`).
class ChatSession {
  const ChatSession({
    required this.id,
    required this.title,
    required this.subject,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final ChatSubject subject;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subject': subject.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ChatSession.fromMap(Map<String, dynamic> map, String id) {
    final createdAtRaw = map['createdAt'] as String?;
    final updatedAtRaw = map['updatedAt'] as String?;
    return ChatSession(
      id: id,
      title: map['title'] as String? ?? 'नवीन चॅट',
      subject: ChatSubjectX.fromName(map['subject'] as String?),
      createdAt:
          createdAtRaw != null ? DateTime.tryParse(createdAtRaw) ?? DateTime.now() : DateTime.now(),
      updatedAt:
          updatedAtRaw != null ? DateTime.tryParse(updatedAtRaw) ?? DateTime.now() : DateTime.now(),
    );
  }
}
