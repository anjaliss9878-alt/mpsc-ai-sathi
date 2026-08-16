import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/notification_item.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/services/admin_repository.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/notification_repository.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/date_format.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Compose + history for in-app student notifications. Restricted to
/// `admin`/`superadmin` roles — an `editor` can manage content but not mass
/// -message every student.
class AdminNotificationsScreen extends StatelessWidget {
  const AdminNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = authService.currentUser?.uid;
    return AdminScaffold(
      title: 'Notifications',
      body: FutureBuilder<String>(
        future: uid == null ? Future.value('admin') : adminRepository.getRole(uid),
        builder: (context, roleSnapshot) {
          if (!roleSnapshot.hasData) return const LoadingState();
          final canSend = adminRepository.roleCanSendNotifications(roleSnapshot.data!);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: canSend
                        ? () => showDialog<void>(
                              context: context,
                              builder: (_) => const _ComposeDialog(),
                            )
                        : () => showAdminMessage(
                              context,
                              'Your role does not have permission to send notifications.',
                            ),
                    icon: const Icon(Icons.campaign_rounded),
                    label: const Text('Compose Notification'),
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<NotificationItem>>(
                  stream: notificationRepository.watchSentHistory(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return ErrorState(message: 'Could not load history: ${snapshot.error}');
                    }
                    if (!snapshot.hasData) return const LoadingState();
                    final items = snapshot.data!;
                    if (items.isEmpty) {
                      return const EmptyState(
                        message: 'No notifications sent yet.',
                        icon: Icons.notifications_none_rounded,
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.notifications_active_outlined, color: AppColors.navy),
                            title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${item.body}\n${item.targetType == 'all' ? 'Sent to all students' : 'Sent to ${item.targetUids.length} student(s)'} · ${item.sentByEmail}',
                              maxLines: 3,
                            ),
                            trailing: Text(
                              formatFriendlyDateTime(item.createdAt),
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ComposeDialog extends StatefulWidget {
  const _ComposeDialog();

  @override
  State<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<_ComposeDialog> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  String _targetType = 'all';
  final Set<String> _selectedUids = {};
  bool _isSending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_titleController.text.trim().isEmpty || _bodyController.text.trim().isEmpty) {
      showAdminMessage(context, 'Title and message are required.');
      return;
    }
    if (_targetType == 'selected' && _selectedUids.isEmpty) {
      showAdminMessage(context, 'Select at least one student.');
      return;
    }
    setState(() => _isSending = true);
    try {
      final count = await notificationRepository.send(
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        targetType: _targetType,
        targetUids: _selectedUids.toList(),
        sentByEmail: authService.currentUser?.email ?? 'admin',
      );
      await auditLogRepository.log(
        action: 'send',
        module: 'Notifications',
        targetLabel: _titleController.text.trim(),
        details: 'Delivered to $count student(s)',
      );
      if (mounted) {
        Navigator.of(context).pop();
        showAdminMessage(context, 'Notification sent to $count student(s).');
      }
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Compose Notification'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyController,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Message'),
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('All students')),
                  ButtonSegment(value: 'selected', label: Text('Selected students')),
                ],
                selected: {_targetType},
                onSelectionChanged: (s) => setState(() => _targetType = s.first),
              ),
              if (_targetType == 'selected') ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: StreamBuilder<List<StudentProfile>>(
                    stream: profileRepository.watchAllStudents(),
                    builder: (context, snapshot) {
                      final students = snapshot.data ?? const <StudentProfile>[];
                      if (students.isEmpty) {
                        return const Center(child: Text('No students yet.'));
                      }
                      return ListView.builder(
                        itemCount: students.length,
                        itemBuilder: (context, index) {
                          final s = students[index];
                          return CheckboxListTile(
                            dense: true,
                            title: Text(s.name.isEmpty ? s.email : s.name),
                            subtitle: Text(s.email),
                            value: _selectedUids.contains(s.uid),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selectedUids.add(s.uid);
                              } else {
                                _selectedUids.remove(s.uid);
                              }
                            }),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSending ? null : _send,
          child: _isSending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Send'),
        ),
      ],
    );
  }
}
