import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/job_alert.dart';
import 'package:mpsc_combine_ai/services/job_alerts_repository.dart';
import 'package:mpsc_combine_ai/services/link_launcher.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/date_format.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';
import 'package:mpsc_combine_ai/widgets/feature_screen_scaffold.dart';

/// Published MPSC recruitment / exam alerts from the Admin Panel.
class JobAlertsScreen extends StatelessWidget {
  const JobAlertsScreen({super.key, this.repository});

  final JobAlertsRepository? repository;

  Stream<List<JobAlert>>? _stream() {
    try {
      return (repository ?? jobAlertsRepository).watchPublished();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    const description =
        'Official MPSC recruitment, vacancy, and exam-related updates published by administrators.';
    final stream = _stream();
    if (stream == null) {
      return const FeatureScreenScaffold(
        title: 'Job Alerts',
        icon: Icons.work_outline_rounded,
        description: description,
        sectionTitle: 'Published alerts',
        emptyMessage:
            'Could not connect to Firestore. Sign in and try again. Automatic external job feeds are not enabled.',
        items: [],
      );
    }

    return StreamBuilder<List<JobAlert>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Job Alerts')),
            body: ErrorState(
              message:
                  'Could not load job alerts. Check your connection and try again.\n${snapshot.error}',
            ),
          );
        }
        final loading = !snapshot.hasData;
        final alerts = snapshot.data ?? const <JobAlert>[];
        return FeatureScreenScaffold(
          title: 'Job Alerts',
          icon: Icons.work_outline_rounded,
          description: description,
          sectionTitle: loading
              ? 'Published alerts'
              : alerts.isEmpty
                  ? 'Published alerts'
                  : '${alerts.length} published alert${alerts.length == 1 ? '' : 's'}',
          emptyMessage: loading
              ? 'Loading published alerts…'
              : 'No published job alerts yet. Administrators add recruitment notices from the Admin Panel. Automatic external job feeds are not enabled.',
          isLoading: loading,
          items: [
            for (final alert in alerts)
              PlaceholderListItem(
                title: '${alert.statusLabel} · ${alert.title}',
                subtitle: _subtitle(alert),
                icon: _iconFor(alert.lifecycle()),
                onTap: () => _openDetail(context, alert),
              ),
          ],
        );
      },
    );
  }

  String _subtitle(JobAlert alert) {
    final parts = <String>[
      if (alert.organization.isNotEmpty) alert.organization,
      if (alert.post.isNotEmpty) alert.post,
      if (alert.lastDate.isNotEmpty) 'Last date ${alert.lastDate}',
    ];
    return parts.isEmpty ? 'Tap for eligibility, dates, and the official link.' : parts.join(' · ');
  }

  IconData _iconFor(JobAlertLifecycle status) {
    return switch (status) {
      JobAlertLifecycle.newlyPosted => Icons.new_releases_outlined,
      JobAlertLifecycle.closingSoon => Icons.timer_outlined,
      JobAlertLifecycle.closed => Icons.event_busy_rounded,
      JobAlertLifecycle.active => Icons.campaign_rounded,
      JobAlertLifecycle.draft => Icons.work_outline_rounded,
    };
  }

  Future<void> _openDetail(BuildContext context, JobAlert alert) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.title,
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text(alert.statusLabel)),
                      if (alert.organization.isNotEmpty)
                        Chip(label: Text(alert.organization)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (alert.post.isNotEmpty) _row('Post', alert.post),
                  if (alert.eligibility.isNotEmpty)
                    _row('Eligibility', alert.eligibility),
                  if (alert.applicationStartDate.isNotEmpty)
                    _row('Application start', alert.applicationStartDate),
                  if (alert.lastDate.isNotEmpty)
                    _row('Last date', alert.lastDate),
                  if (alert.importantDates.isNotEmpty)
                    _row('Important dates', alert.importantDates),
                  if (alert.createdAt != null)
                    _row('Posted', formatShortDate(alert.createdAt!)),
                  if (alert.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      alert.description,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (alert.applicationUrl.isNotEmpty)
                    FilledButton.icon(
                      onPressed: () =>
                          openExternalLink(ctx, alert.applicationUrl),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Official application'),
                    )
                  else
                    const Text(
                      'No official application URL was provided.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          Text(value, style: const TextStyle(height: 1.35)),
        ],
      ),
    );
  }
}
