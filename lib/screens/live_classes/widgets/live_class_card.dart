import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/live_class_item.dart';
import 'package:mpsc_combine_ai/screens/live_classes/widgets/live_class_countdown.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

Color colorForStatus(String status) {
  switch (status) {
    case 'live':
      return Colors.red;
    case 'completed':
      return AppColors.textSecondary;
    case 'upcoming':
    default:
      return AppColors.orange;
  }
}

String labelForStatus(String status) {
  switch (status) {
    case 'live':
      return 'LIVE NOW';
    case 'completed':
      return 'RECORDED';
    case 'upcoming':
    default:
      return 'UPCOMING';
  }
}

IconData iconForStatus(String status) {
  switch (status) {
    case 'live':
      return Icons.podcasts_rounded;
    case 'completed':
      return Icons.smart_display_rounded;
    case 'upcoming':
    default:
      return Icons.event_rounded;
  }
}

/// One live class summary card — used across Home/Upcoming/Live
/// Now/Recorded. Tapping always opens the Join screen; the Join screen
/// itself decides what "joining" means for the class's current status.
class LiveClassCard extends StatelessWidget {
  const LiveClassCard({super.key, required this.item, required this.onTap});

  final LiveClassItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = colorForStatus(item.status);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Banner(item: item, statusColor: statusColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (item.subject.isNotEmpty) ...[
                        Icon(Icons.menu_book_rounded, size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          item.subject,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (item.facultyName.isNotEmpty) ...[
                        Icon(Icons.person_rounded, size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.facultyName,
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.hasSchedule
                              ? _formatSchedule(item.scheduledAt)
                              : item.scheduleText,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.status == 'upcoming' && item.hasSchedule)
                        LiveClassCountdown(target: item.scheduledAt, compact: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSchedule(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} · $hour12:$minute $ampm';
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.item, required this.statusColor});

  final LiveClassItem item;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          height: 110,
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
                      size: 34,
                    ),
                  ),
                )
              : Image.network(
                  item.bannerImageUrl.trim(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    decoration: const BoxDecoration(color: AppColors.navy),
                    child: Center(
                      child: Icon(
                        iconForStatus(item.status),
                        color: Colors.white.withValues(alpha: 0.85),
                        size: 34,
                      ),
                    ),
                  ),
                ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              labelForStatus(item.status),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
