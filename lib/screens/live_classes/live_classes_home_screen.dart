import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/live_class_item.dart';
import 'package:mpsc_combine_ai/screens/live_classes/live_class_join_screen.dart';
import 'package:mpsc_combine_ai/screens/live_classes/live_now_screen.dart';
import 'package:mpsc_combine_ai/screens/live_classes/my_attendance_screen.dart';
import 'package:mpsc_combine_ai/screens/live_classes/recorded_classes_screen.dart';
import 'package:mpsc_combine_ai/screens/live_classes/upcoming_classes_screen.dart';
import 'package:mpsc_combine_ai/screens/live_classes/widgets/live_class_card.dart';
import 'package:mpsc_combine_ai/services/live_class_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Live Classes Home — entry point for the whole module. Shows a live
/// count of classes happening now, quick navigation into
/// Upcoming/Live-Now/Recorded/My-Attendance, and a preview list of what's
/// next so a student never has to dig through empty tabs.
class LiveClassesHomeScreen extends StatelessWidget {
  const LiveClassesHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Live Classes', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: StreamBuilder<List<LiveClassItem>>(
          stream: liveClassRepository.watchAll(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorState(message: 'लोड करता आले नाही. (Could not load: ${snapshot.error})');
            }
            if (!snapshot.hasData) return const LoadingState();

            final items = snapshot.data!;
            final live = items.where((i) => i.status == 'live').toList();
            final upcoming = items.where((i) => i.status == 'upcoming').toList()
              ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
            final recordedCount = items.where((i) => i.status == 'completed').length;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (live.isNotEmpty) ...[
                  const _SectionTitle(title: '🔴 Live Now'),
                  ...live.map(
                    (item) => LiveClassCard(item: item, onTap: () => _openJoin(context, item)),
                  ),
                  const SizedBox(height: 8),
                ],
                _QuickNavGrid(liveCount: live.length, recordedCount: recordedCount),
                const SizedBox(height: 20),
                const _SectionTitle(title: 'Coming Up Next'),
                if (upcoming.isEmpty)
                  const EmptyState(
                    message: 'सध्या कोणतेही आगामी वर्ग नाहीत.\n(No upcoming classes scheduled.)',
                    icon: Icons.event_rounded,
                  )
                else
                  ...upcoming.take(3).map(
                        (item) => LiveClassCard(item: item, onTap: () => _openJoin(context, item)),
                      ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openJoin(BuildContext context, LiveClassItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LiveClassJoinScreen(liveClassId: item.id)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary),
      ),
    );
  }
}

class _QuickNavGrid extends StatelessWidget {
  const _QuickNavGrid({required this.liveCount, required this.recordedCount});

  final int liveCount;
  final int recordedCount;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _NavCard(
          title: 'Upcoming Classes',
          icon: Icons.event_rounded,
          badge: null,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const UpcomingClassesScreen()),
          ),
        ),
        _NavCard(
          title: 'Live Now',
          icon: Icons.podcasts_rounded,
          badge: liveCount > 0 ? liveCount.toString() : null,
          badgeColor: Colors.red,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const LiveNowScreen()),
          ),
        ),
        _NavCard(
          title: 'Recorded Classes',
          icon: Icons.smart_display_rounded,
          badge: recordedCount > 0 ? recordedCount.toString() : null,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const RecordedClassesScreen()),
          ),
        ),
        _NavCard(
          title: 'My Attendance',
          icon: Icons.fact_check_outlined,
          badge: null,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MyAttendanceScreen()),
          ),
        ),
      ],
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.title,
    required this.icon,
    required this.onTap,
    this.badge,
    this.badgeColor = AppColors.orange,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: AppColors.navy, size: 22),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              if (badge != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      badge!,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
