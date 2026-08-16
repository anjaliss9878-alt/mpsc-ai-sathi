import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/models/audit_log_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/date_format.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

IconData _iconForAction(String action) {
  switch (action) {
    case 'create':
      return Icons.add_circle_outline_rounded;
    case 'update':
      return Icons.edit_outlined;
    case 'delete':
      return Icons.delete_outline_rounded;
    case 'block':
      return Icons.block_rounded;
    case 'unblock':
      return Icons.check_circle_outline_rounded;
    case 'send':
      return Icons.notifications_active_outlined;
    case 'bulk_upload':
      return Icons.upload_file_rounded;
    case 'rollback':
      return Icons.undo_rounded;
    default:
      return Icons.history_rounded;
  }
}

/// Read-only trail of every Admin Panel action (who did what, to what, and
/// when), sourced live from `auditLogs/{id}`.
class AdminAuditLogScreen extends StatelessWidget {
  const AdminAuditLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Audit Log',
      body: StreamBuilder<List<AuditLogItem>>(
        stream: auditLogRepository.watchRecent(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load audit log: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const EmptyState(
              message: 'No admin actions recorded yet.',
              icon: Icons.history_rounded,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_iconForAction(item.action), color: AppColors.navy),
                  ),
                  title: Text(
                    '${item.module} · ${item.action}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    [
                      if (item.targetLabel.isNotEmpty) item.targetLabel,
                      if (item.details.isNotEmpty) item.details,
                      item.adminEmail,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    formatFriendlyDateTime(item.createdAt),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
