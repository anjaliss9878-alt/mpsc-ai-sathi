import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/live_class_item.dart';
import 'package:mpsc_combine_ai/screens/live_classes/my_attendance_screen.dart';
import 'package:mpsc_combine_ai/screens/live_classes/widgets/live_class_card.dart';
import 'package:mpsc_combine_ai/screens/live_classes/widgets/live_class_countdown.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/link_launcher.dart';
import 'package:mpsc_combine_ai/services/live_class_attendance_repository.dart';
import 'package:mpsc_combine_ai/services/live_class_repository.dart';
import 'package:mpsc_combine_ai/services/live_class_video_service.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Join screen for a single live class — combines the Join action,
/// live-ticking Countdown (while [LiveClassItem.status] is "upcoming"), and
/// the Attendance UI (marks + shows attendance once the student joins a
/// "live" class).
///
/// Joining today always resolves to [LiveClassJoinMode.externalLink] via
/// [liveClassVideoProvider] — see `live_class_video_service.dart` for how a
/// 100ms-backed embedded call would plug in later without touching this
/// screen's layout.
class LiveClassJoinScreen extends StatefulWidget {
  const LiveClassJoinScreen({super.key, required this.liveClassId});

  final String liveClassId;

  @override
  State<LiveClassJoinScreen> createState() => _LiveClassJoinScreenState();
}

class _LiveClassJoinScreenState extends State<LiveClassJoinScreen> {
  bool _isJoining = false;
  bool _attendanceMarked = false;
  bool _checkedAttendance = false;

  String? get _uid => authService.currentUser?.uid;

  Future<void> _checkAttendance() async {
    final uid = _uid;
    if (uid == null || _checkedAttendance) return;
    try {
      final marked = await liveClassAttendanceRepository.hasMarked(widget.liveClassId, uid);
      if (!mounted) return;
      setState(() {
        _attendanceMarked = marked;
        _checkedAttendance = true;
      });
    } catch (_) {
      if (mounted) setState(() => _checkedAttendance = true);
    }
  }

  Future<void> _join(LiveClassItem item) async {
    setState(() => _isJoining = true);
    try {
      final result = await liveClassVideoProvider.prepareJoin(item);
      switch (result.mode) {
        case LiveClassJoinMode.externalLink:
          if (mounted) await openExternalLink(context, result.url!);
          await _markAttendance(item);
        case LiveClassJoinMode.embeddedRoom:
          // Reserved for a future 100ms-backed provider — no implementation
          // exists yet, so this branch is unreachable today.
          break;
        case LiveClassJoinMode.notReady:
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('Meeting link has not been added yet. Please check back soon.'),
                ),
              );
          }
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Future<void> _markAttendance(LiveClassItem item) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final profile = await profileRepository.getProfile(uid);
      final email = authService.currentUser?.email ?? profile?.email ?? '';
      await liveClassAttendanceRepository.markAttendance(
        liveClassId: item.id,
        liveClassTitle: item.title,
        uid: uid,
        studentName: profile?.name ?? '',
        studentEmail: email,
      );
      if (mounted) setState(() => _attendanceMarked = true);
    } catch (_) {
      // Attendance is best-effort — a Firestore hiccup must never block the
      // student from actually joining the class.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Join Class', style: TextStyle(fontWeight: FontWeight.w600))),
      body: SafeArea(
        child: StreamBuilder<LiveClassItem?>(
          stream: liveClassRepository.watchById(widget.liveClassId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorState(message: 'वर्ग लोड करता आला नाही. (Could not load class: ${snapshot.error})');
            }
            if (!snapshot.hasData) return const LoadingState();
            final item = snapshot.data;
            if (item == null) {
              return const EmptyState(
                message: 'हा वर्ग सापडला नाही किंवा हटवला गेला आहे.\n(This class was not found or was deleted.)',
                icon: Icons.event_busy_rounded,
              );
            }

            if (item.status == 'live' && !_checkedAttendance) {
              _checkAttendance();
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _HeaderCard(item: item),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _buildBody(context, item),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const MyAttendanceScreen()),
                  ),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('View My Attendance History'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, LiveClassItem item) {
    switch (item.status) {
      case 'live':
        return _buildLive(item);
      case 'completed':
        return _buildCompleted(item);
      case 'upcoming':
      default:
        return _buildUpcoming(item);
    }
  }

  Widget _buildUpcoming(LiveClassItem item) {
    return Column(
      children: [
        const Text(
          'वर्ग सुरू होण्यास बाकी वेळ (Time until class starts)',
          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 16),
        if (item.hasSchedule)
          LiveClassCountdown(target: item.scheduledAt)
        else
          const Text(
            'वेळ अद्याप ठरलेली नाही. (Schedule not set yet.)',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: null,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: const Icon(Icons.lock_clock_rounded),
            label: const Text('Join opens when the class goes live'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'तुमचे शिक्षक वेळेवर वर्ग सुरू करतील — तेव्हा हे बटण आपोआप सक्रिय होईल.\n'
          '(Your faculty will start the class on time — this button unlocks automatically.)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildLive(LiveClassItem item) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.podcasts_rounded, size: 15, color: Colors.red),
              SizedBox(width: 6),
              Text('LIVE NOW', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isJoining ? null : () => _join(item),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.orange,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _isJoining
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.video_call_rounded),
            label: Text(_isJoining ? 'Joining…' : 'Join Live Class'),
          ),
        ),
        if (_checkedAttendance) ...[
          const SizedBox(height: 12),
          _AttendanceStatus(marked: _attendanceMarked),
        ],
      ],
    );
  }

  Widget _buildCompleted(LiveClassItem item) {
    final hasRecording = item.recordingUrl.trim().isNotEmpty;
    final hasNotes = item.notesUrl.trim().isNotEmpty;
    return Column(
      children: [
        Icon(Icons.smart_display_rounded, size: 40, color: AppColors.navy.withValues(alpha: 0.5)),
        const SizedBox(height: 10),
        Text(
          hasRecording
              ? 'रेकॉर्डिंग उपलब्ध आहे. (Recording is available.)'
              : 'रेकॉर्डिंग अजून अपलोड केलेले नाही.\n(Recording has not been uploaded yet.)',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: hasRecording ? () => openExternalLink(context, item.recordingUrl) : null,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: const Icon(Icons.play_circle_fill_rounded),
            label: const Text('Watch Recording'),
          ),
        ),
        if (hasNotes) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => openExternalLink(context, item.notesUrl),
              icon: const Icon(Icons.menu_book_rounded),
              label: const Text('Class Notes'),
            ),
          ),
        ],
      ],
    );
  }
}

class _AttendanceStatus extends StatelessWidget {
  const _AttendanceStatus({required this.marked});

  final bool marked;

  @override
  Widget build(BuildContext context) {
    if (!marked) {
      return const Text(
        'सामील झाल्यावर उपस्थिती नोंदवली जाईल.\n(Attendance will be marked once you join.)',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
          SizedBox(width: 8),
          Text(
            'उपस्थिती नोंदवली गेली! (Attendance marked!)',
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.item});

  final LiveClassItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 140,
            width: double.infinity,
            child: item.bannerImageUrl.trim().isEmpty
                ? Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.navy, AppColors.navyLight],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        iconForStatus(item.status),
                        color: Colors.white.withValues(alpha: 0.85),
                        size: 40,
                      ),
                    ),
                  )
                : Image.network(
                    item.bannerImageUrl.trim(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(color: AppColors.navy),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (item.subject.isNotEmpty)
                      _MetaChip(icon: Icons.menu_book_rounded, label: item.subject),
                    if (item.facultyName.isNotEmpty)
                      _MetaChip(icon: Icons.person_rounded, label: item.facultyName),
                    _MetaChip(icon: Icons.timer_outlined, label: '${item.durationMinutes} min'),
                  ],
                ),
                if (item.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    item.description,
                    style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
      ],
    );
  }
}
