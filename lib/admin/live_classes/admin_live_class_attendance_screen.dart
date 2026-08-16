import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/models/live_class_attendance_item.dart';
import 'package:mpsc_combine_ai/models/live_class_item.dart';
import 'package:mpsc_combine_ai/services/live_class_attendance_repository.dart';
import 'package:mpsc_combine_ai/services/live_class_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/date_format.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Admin "Attendance" — pick a class, see everyone who marked themselves
/// present for it (populated by the student Join screen).
class AdminLiveClassAttendanceScreen extends StatefulWidget {
  const AdminLiveClassAttendanceScreen({super.key});

  @override
  State<AdminLiveClassAttendanceScreen> createState() =>
      _AdminLiveClassAttendanceScreenState();
}

class _AdminLiveClassAttendanceScreenState extends State<AdminLiveClassAttendanceScreen> {
  String? _selectedClassId;

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Attendance',
      body: StreamBuilder<List<LiveClassItem>>(
        stream: liveClassRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load classes: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final classes = snapshot.data!;
          if (classes.isEmpty) {
            return const EmptyState(
              message: 'No live classes yet — add one first.',
              icon: Icons.live_tv_outlined,
            );
          }
          final validSelection =
              classes.any((c) => c.id == _selectedClassId) ? _selectedClassId : null;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: validSelection,
                  decoration: const InputDecoration(labelText: 'Select a class'),
                  items: classes
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.title)))
                      .toList(),
                  onChanged: (value) => setState(() => _selectedClassId = value),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: validSelection == null
                      ? const EmptyState(
                          message: 'Select a class above to view its attendance.',
                          icon: Icons.fact_check_outlined,
                        )
                      : _AttendanceList(classId: validSelection),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AttendanceList extends StatelessWidget {
  const _AttendanceList({required this.classId});

  final String classId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LiveClassAttendanceItem>>(
      stream: liveClassAttendanceRepository.watchForClass(classId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorState(message: 'Could not load attendance: ${snapshot.error}');
        }
        if (!snapshot.hasData) return const LoadingState();
        final entries = snapshot.data!;
        if (entries.isEmpty) {
          return const EmptyState(
            message: 'No student has marked attendance for this class yet.',
            icon: Icons.people_outline_rounded,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${entries.length} student${entries.length == 1 ? '' : 's'} attended',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return ListTile(
                    leading: const Icon(Icons.check_circle_rounded, color: Colors.green),
                    title: Text(
                      entry.studentName.isEmpty ? entry.studentEmail : entry.studentName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      entry.studentEmail.isEmpty
                          ? formatFriendlyDateTime(entry.markedAt)
                          : '${entry.studentEmail} · ${formatFriendlyDateTime(entry.markedAt)}',
                    ),
                    trailing: Text(
                      '#${index + 1}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
