import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/chat_message.dart';
import 'package:mpsc_combine_ai/models/chat_session.dart';
import 'package:mpsc_combine_ai/models/chat_subject.dart';

/// Reads/writes AI Teacher chat sessions and their messages in Firestore:
///
/// - `students/{uid}/chats/{chatId}` — session metadata (title, subject, dates).
/// - `students/{uid}/chats/{chatId}/messages/{messageId}` — the messages.
///
/// Every method is designed to be called defensively from the UI (wrap in
/// try/catch) — a Firestore hiccup here must never block the chat itself.
class ChatRepository {
  ChatRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String studentsCollection = 'students';
  static const String chatsSubcollection = 'chats';
  static const String messagesSubcollection = 'messages';

  CollectionReference<Map<String, dynamic>> _chatsRef(String uid) {
    return _firestore
        .collection(studentsCollection)
        .doc(uid)
        .collection(chatsSubcollection);
  }

  /// Live list of the student's chat sessions, most recently updated first.
  Stream<List<ChatSession>> watchSessions(String uid) {
    return _chatsRef(uid).orderBy('updatedAt', descending: true).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => ChatSession.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  /// The student's most recently active chat, if any — used to resume the
  /// last conversation automatically when the AI Teacher screen opens.
  Future<ChatSession?> getMostRecentSession(String uid) async {
    final snapshot =
        await _chatsRef(uid).orderBy('updatedAt', descending: true).limit(1).get();
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return ChatSession.fromMap(doc.data(), doc.id);
  }

  Future<String> createSession(
    String uid, {
    required String title,
    required ChatSubject subject,
  }) async {
    final now = DateTime.now();
    final doc = await _chatsRef(uid).add(
      ChatSession(
        id: '',
        title: title,
        subject: subject,
        createdAt: now,
        updatedAt: now,
      ).toMap(),
    );
    return doc.id;
  }

  Future<void> touchSession(
    String uid,
    String chatId, {
    String? title,
    ChatSubject? subject,
  }) async {
    await _chatsRef(uid).doc(chatId).set(
      {
        'title': ?title,
        'subject': ?subject?.name,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deleteSession(String uid, String chatId) async {
    final chatDoc = _chatsRef(uid).doc(chatId);
    final messages = await chatDoc.collection(messagesSubcollection).get();
    final batch = _firestore.batch();
    for (final doc in messages.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(chatDoc);
    await batch.commit();
  }

  Future<List<ChatMessage>> getMessages(String uid, String chatId) async {
    final snapshot = await _chatsRef(uid)
        .doc(chatId)
        .collection(messagesSubcollection)
        .orderBy('timestamp')
        .get();
    return snapshot.docs
        .map((doc) => ChatMessage.fromMap(doc.data(), doc.id))
        .toList();
  }

  Future<String> addMessage(String uid, String chatId, ChatMessage message) async {
    final doc = await _chatsRef(uid)
        .doc(chatId)
        .collection(messagesSubcollection)
        .add(message.toMap());
    return doc.id;
  }

  Future<void> updateMessageContent(
    String uid,
    String chatId,
    String messageId,
    String content, {
    List<Map<String, dynamic>>? citations,
  }) async {
    final data = <String, dynamic>{
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (citations != null) {
      data['citations'] = citations;
    }
    await _chatsRef(uid)
        .doc(chatId)
        .collection(messagesSubcollection)
        .doc(messageId)
        .update(data);
  }
}

/// Shared instance used by the AI Teacher screen.
final ChatRepository chatRepository = ChatRepository();
