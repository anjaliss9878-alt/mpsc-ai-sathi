/// One recorded Admin Panel action, stored in Firestore at
/// `auditLogs/{id}`. Written automatically by [AuditLogRepository.log] every
/// time an admin creates, edits, deletes, or otherwise mutates content —
/// never edited or deleted by anyone through the app itself.
class AuditLogItem {
  const AuditLogItem({
    required this.id,
    required this.adminUid,
    required this.adminEmail,
    required this.action,
    required this.module,
    required this.targetLabel,
    required this.details,
    required this.createdAt,
  });

  final String id;
  final String adminUid;
  final String adminEmail;

  /// e.g. `create`, `update`, `delete`, `block`, `unblock`, `send`,
  /// `bulk_upload`, `rollback`.
  final String action;

  /// e.g. `Subjects`, `MCQs`, `Students`, `Notifications`, `Bulk Upload`.
  final String module;

  /// Human-readable label for the affected item, e.g. a question's text or
  /// a student's name — shown directly in the Audit Log list.
  final String targetLabel;

  final String details;
  final DateTime createdAt;

  factory AuditLogItem.fromMap(Map<String, dynamic> map, String id) {
    return AuditLogItem(
      id: id,
      adminUid: map['adminUid'] as String? ?? '',
      adminEmail: map['adminEmail'] as String? ?? '',
      action: map['action'] as String? ?? '',
      module: map['module'] as String? ?? '',
      targetLabel: map['targetLabel'] as String? ?? '',
      details: map['details'] as String? ?? '',
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'adminUid': adminUid,
      'adminEmail': adminEmail,
      'action': action,
      'module': module,
      'targetLabel': targetLabel,
      'details': details,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
