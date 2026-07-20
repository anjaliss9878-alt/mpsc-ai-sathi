/// Who a given AI Teacher chat message belongs to.
enum ChatRole { user, assistant }

/// A single message inside an AI Teacher chat session.
///
/// Persisted at `students/{uid}/chats/{chatId}/messages/{id}` once a session
/// exists in Firestore (see `ChatRepository`); [id] is null for messages that
/// only exist locally (e.g. the client-only welcome greeting, or a message
/// whose write to Firestore hasn't completed/succeeded yet).
class ChatMessage {
  const ChatMessage({
    this.id,
    required this.role,
    required this.content,
    required this.timestamp,
  });

  final String? id;
  final ChatRole role;
  final String content;
  final DateTime timestamp;

  bool get isUser => role == ChatRole.user;

  ChatMessage copyWith({String? id, String? content}) {
    return ChatMessage(
      id: id ?? this.id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'role': role.name,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map, String id) {
    final rawTimestamp = map['timestamp'] as String?;
    return ChatMessage(
      id: id,
      role: map['role'] == 'user' ? ChatRole.user : ChatRole.assistant,
      content: map['content'] as String? ?? '',
      timestamp:
          rawTimestamp != null ? DateTime.tryParse(rawTimestamp) ?? DateTime.now() : DateTime.now(),
    );
  }
}
