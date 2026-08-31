import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/jobs/admin_job_alert_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_preview.dart';
import 'package:mpsc_combine_ai/models/job_alert.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/job_alerts_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminJobAlertsScreen extends StatefulWidget {
  const AdminJobAlertsScreen({super.key});

  @override
  State<AdminJobAlertsScreen> createState() => _AdminJobAlertsScreenState();
}

class _AdminJobAlertsScreenState extends State<AdminJobAlertsScreen> {
  String _query = '';
  bool? _publishedOnly;

  Future<void> _setPublished(JobAlert item, bool published) async {
    try {
      await jobAlertsRepository.update(item.copyWith(published: published));
      await auditLogRepository.log(
        action: published ? 'publish' : 'unpublish',
        module: 'Job Alerts',
        targetLabel: item.title,
      );
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  List<JobAlert> _filter(List<JobAlert> all) {
    final q = _query.trim().toLowerCase();
    return all.where((item) {
      if (_publishedOnly == true && !item.published) return false;
      if (_publishedOnly == false && item.published) return false;
      if (q.isEmpty) return true;
      return item.title.toLowerCase().contains(q) ||
          item.organization.toLowerCase().contains(q) ||
          item.post.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Job Alerts',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const AdminJobAlertFormScreen(),
          ),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<JobAlert>>(
        stream: jobAlertsRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
              message: 'Could not load job alerts: ${snapshot.error}',
            );
          }
          if (!snapshot.hasData) return const LoadingState();
          final all = snapshot.data!;
          if (all.isEmpty) {
            return const EmptyState(
              message: 'No job alerts yet. Tap + to add a recruitment notice.',
              icon: Icons.work_outline_rounded,
            );
          }
          final items = _filter(all);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search exam, organization, post…',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected: _publishedOnly == null,
                          onSelected: (_) =>
                              setState(() => _publishedOnly = null),
                        ),
                        ChoiceChip(
                          label: const Text('Published'),
                          selected: _publishedOnly == true,
                          onSelected: (_) =>
                              setState(() => _publishedOnly = true),
                        ),
                        ChoiceChip(
                          label: const Text('Unpublished'),
                          selected: _publishedOnly == false,
                          onSelected: (_) =>
                              setState(() => _publishedOnly = false),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const EmptyState(
                        message: 'No job alerts match these filters.',
                        icon: Icons.search_off_rounded,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final status = item.lifecycle();
                          final last = item.lastDate.isEmpty
                              ? 'No last date'
                              : item.lastDate;
                          return AdminListTile(
                            title: item.title,
                            subtitle:
                                '${status.label} · ${item.published ? 'Published' : 'Unpublished'} · '
                                '${item.organization.isEmpty ? item.post : item.organization} · Last date $last',
                            icon: Icons.work_outline_rounded,
                            isActive: item.published,
                            onPreview: () => showJobAlertPreview(context, item),
                            onToggleActive: () =>
                                _setPublished(item, !item.published),
                            onEdit: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    AdminJobAlertFormScreen(existing: item),
                              ),
                            ),
                            onDelete: () async {
                              final confirmed =
                                  await confirmDelete(context, item.title);
                              if (!confirmed) return;
                              try {
                                await jobAlertsRepository.delete(item.id);
                                await auditLogRepository.log(
                                  action: 'delete',
                                  module: 'Job Alerts',
                                  targetLabel: item.title,
                                );
                                if (context.mounted) {
                                  showAdminMessage(context, 'Alert deleted.');
                                }
                              } catch (e) {
                                if (context.mounted) showAdminError(context, e);
                              }
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
