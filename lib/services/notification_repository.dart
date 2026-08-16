import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/notification_item.dart';

/// Sends and reads Admin Panel notifications.
///
/// True OS-level push delivery (a notification appearing outside the app,
/// even when it's closed) needs a server-side component — either a Cloud
/// Function reacting to new `notifications/{id}` documents, or a backend
/// calling the FCM HTTP v1 API with a service-account credential, since
/// that credential can never be safely embedded in a client app. Neither of
/// those exists in this Flutter-only project yet.
///
/// What *is* fully real and working end-to-end here: every notification is
/// fanned out to `students/{uid}/inbox/{id}`, and the student app shows it
/// live (unread badge + inbox list) via a normal Firestore listener — the
/// same "instant update, no app rebuild" guarantee as every other content
/// type in this app. Wiring real OS push on top later is a drop-in addition
/// (a Cloud Function trigger on `notifications/{id}` creation) that needs
/// no changes here.
class NotificationRepository {
  NotificationRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'notifications';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<NotificationItem>> watchSentHistory() {
    return _ref.orderBy('createdAt', descending: true).snapshots().map(
          (snap) =>
              snap.docs.map((d) => NotificationItem.fromMap(d.data(), d.id)).toList(),
        );
  }

  /// Sends [title]/[body] either to every student ([targetType] = `all`) or
  /// to [targetUids] ([targetType] = `selected`), fanning out an inbox copy
  /// to each targeted student in batches (Firestore caps a batch at 500
  /// writes).
  Future<int> send({
    required String title,
    required String body,
    required String targetType,
    required List<String> targetUids,
    required String sentByEmail,
  }) async {
    final createdAt = DateTime.now();
    final sendDoc = await _ref.add(
      NotificationItem(
        id: '',
        title: title,
        body: body,
        targetType: targetType,
        targetUids: targetType == 'selected' ? targetUids : const [],
        createdAt: createdAt,
        sentByEmail: sentByEmail,
      ).toMap(),
    );

    List<String> recipients = targetUids;
    if (targetType == 'all') {
      final studentsSnap = await _firestore.collection('students').get();
      recipients = studentsSnap.docs.map((d) => d.id).toList();
    }

    const chunkSize = 400;
    for (var i = 0; i < recipients.length; i += chunkSize) {
      final chunk = recipients.skip(i).take(chunkSize);
      final batch = _firestore.batch();
      for (final uid in chunk) {
        final inboxRef = _firestore
            .collection('students')
            .doc(uid)
            .collection('inbox')
            .doc(sendDoc.id);
        batch.set(inboxRef, {
          'title': title,
          'body': body,
          'createdAt': createdAt.toIso8601String(),
          'isRead': false,
        });
      }
      await batch.commit();
    }
    return recipients.length;
  }

  Stream<List<NotificationItem>> watchInbox(String uid) {
    return _firestore
        .collection('students')
        .doc(uid)
        .collection('inbox')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => NotificationItem.fromMap(d.data(), d.id)).toList(),
        );
  }

  Future<void> markRead(String uid, String notificationId) async {
    await _firestore
        .collection('students')
        .doc(uid)
        .collection('inbox')
        .doc(notificationId)
        .set({'isRead': true}, SetOptions(merge: true));
  }
}

/// Shared instance used by both the Admin Panel and the student app.
final NotificationRepository notificationRepository = NotificationRepository();
