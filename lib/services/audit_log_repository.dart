import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/audit_log_item.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';

/// Writes an immutable trail of every Admin Panel action to Firestore at
/// `auditLogs/{id}` and lets the Admin Panel's "Audit Log" screen read it
/// back. Logging never blocks or fails the action it is recording — a
/// logging error is swallowed so a Firestore hiccup here can never stop an
/// admin from saving their real work.
class AuditLogRepository {
  AuditLogRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'auditLogs';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Future<void> log({
    required String action,
    required String module,
    String targetLabel = '',
    String details = '',
  }) async {
    try {
      final user = authService.currentUser;
      await _ref.add(
        AuditLogItem(
          id: '',
          adminUid: user?.uid ?? 'unknown',
          adminEmail: user?.email ?? 'unknown',
          action: action,
          module: module,
          targetLabel: targetLabel,
          details: details,
          createdAt: DateTime.now(),
        ).toMap(),
      );
    } catch (_) {
      // Never let audit logging break the admin action it is recording.
    }
  }

  Stream<List<AuditLogItem>> watchRecent({int limit = 200}) {
    return _ref
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => AuditLogItem.fromMap(d.data(), d.id))
            .toList());
  }
}

/// Shared instance used across the Admin Panel.
final AuditLogRepository auditLogRepository = AuditLogRepository();
