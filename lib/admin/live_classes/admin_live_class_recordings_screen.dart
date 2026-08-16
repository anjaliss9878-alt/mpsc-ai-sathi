import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/live_classes/admin_live_class_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/live_class_item.dart';
import 'package:mpsc_combine_ai/services/live_class_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Admin "Recordings" — a filtered view of completed classes for quickly
/// attaching/updating a recording link. Editing reuses the same
/// Create/Edit Live Class form (it already has a Recording URL field), so
/// this screen stays a thin, purpose-built list rather than a duplicate
/// editor.
class AdminLiveClassRecordingsScreen extends StatelessWidget {
  const AdminLiveClassRecordingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Recordings',
      body: StreamBuilder<List<LiveClassItem>>(
        stream: liveClassRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load recordings: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final items = snapshot.data!.where((c) => c.status == 'completed').toList()
            ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
          if (items.isEmpty) {
            return const EmptyState(
              message:
                  'No completed classes yet. Mark a class "completed" from Live Classes '
                  'to manage its recording here.',
              icon: Icons.smart_display_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final hasRecording = item.recordingUrl.trim().isNotEmpty;
              return AdminListTile(
                title: item.title,
                subtitle: hasRecording
                    ? 'Recording linked · ${item.recordingUrl}'
                    : 'No recording link yet — tap to add one.',
                icon: hasRecording
                    ? Icons.smart_display_rounded
                    : Icons.smart_display_outlined,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminLiveClassFormScreen(existing: item),
                  ),
                ),
                onEdit: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminLiveClassFormScreen(existing: item),
                  ),
                ),
                onDelete: hasRecording
                    ? () async {
                        final confirmed =
                            await confirmDelete(context, '${item.title} — recording link');
                        if (!confirmed) return;
                        try {
                          await liveClassRepository.update(
                            LiveClassItem(
                              id: item.id,
                              title: item.title,
                              subject: item.subject,
                              meetingUrl: item.meetingUrl,
                              platform: item.platform,
                              scheduleText: item.scheduleText,
                              status: item.status,
                              description: item.description,
                              facultyId: item.facultyId,
                              facultyName: item.facultyName,
                              bannerImageUrl: item.bannerImageUrl,
                              roomId: item.roomId,
                              recordingUrl: '',
                              durationMinutes: item.durationMinutes,
                              attendanceCount: item.attendanceCount,
                              scheduledAt: item.scheduledAt,
                            ),
                          );
                          if (context.mounted) {
                            showAdminMessage(context, 'Recording link removed.');
                          }
                        } catch (e) {
                          if (context.mounted) showAdminError(context, e);
                        }
                      }
                    : () => showAdminMessage(context, 'No recording link to remove yet.'),
              );
            },
          );
        },
      ),
    );
  }
}
