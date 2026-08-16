import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/notification_item.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/notification_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/date_format.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Student-facing inbox for notifications sent from the Admin Panel.
/// Reachable from the bell icon on the Home screen.
class NotificationsInboxScreen extends StatelessWidget {
  const NotificationsInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = authService.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: uid == null
          ? const EmptyState(message: 'Sign in to view notifications.', icon: Icons.login_rounded)
          : StreamBuilder<List<NotificationItem>>(
              stream: notificationRepository.watchInbox(uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorState(message: 'Could not load notifications: ${snapshot.error}');
                }
                if (!snapshot.hasData) return const LoadingState();
                final items = snapshot.data!;
                if (items.isEmpty) {
                  return const EmptyState(
                    message: 'No notifications yet.',
                    icon: Icons.notifications_none_rounded,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card(
                      color: item.isRead ? null : AppColors.orange.withValues(alpha: 0.06),
                      child: ListTile(
                        leading: Icon(
                          item.isRead ? Icons.notifications_none_rounded : Icons.notifications_active_rounded,
                          color: item.isRead ? AppColors.textSecondary : AppColors.orange,
                        ),
                        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(item.body),
                        trailing: Text(
                          formatFriendlyDateTime(item.createdAt),
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                        isThreeLine: true,
                        onTap: () => notificationRepository.markRead(uid, item.id),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
