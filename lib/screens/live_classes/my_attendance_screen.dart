import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/live_class_attendance_item.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/live_class_attendance_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/date_format.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Attendance UI (student-facing): every live class this student has ever
/// been marked present for, most recent first.
class MyAttendanceScreen extends StatelessWidget {
  const MyAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = authService.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Attendance', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: uid == null
            ? const EmptyState(
                message: 'उपस्थिती पाहण्यासाठी लॉगिन आवश्यक आहे.\n(Login is required to view attendance.)',
                icon: Icons.lock_outline_rounded,
              )
            : StreamBuilder<List<LiveClassAttendanceItem>>(
                stream: liveClassAttendanceRepository.watchForStudent(uid),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return ErrorState(message: 'लोड करता आले नाही. (Could not load: ${snapshot.error})');
                  }
                  if (!snapshot.hasData) return const LoadingState();
                  final entries = snapshot.data!;
                  if (entries.isEmpty) {
                    return const EmptyState(
                      message:
                          'अजून कोणतीही उपस्थिती नोंदवली गेली नाही.\nएखादा लाइव्ह वर्ग जॉईन करा!\n'
                          '(No attendance recorded yet. Join a live class!)',
                      icon: Icons.fact_check_outlined,
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.check_circle_rounded, color: Colors.green),
                          ),
                          title: Text(
                            entry.liveClassTitle,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(formatFriendlyDateTime(entry.markedAt)),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}
