import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/daily_study_plan.dart';
import 'package:mpsc_combine_ai/models/job_alert.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/job_alerts_repository.dart';

class AdminJobAlertFormScreen extends StatefulWidget {
  const AdminJobAlertFormScreen({super.key, this.existing});

  final JobAlert? existing;

  @override
  State<AdminJobAlertFormScreen> createState() =>
      _AdminJobAlertFormScreenState();
}

class _AdminJobAlertFormScreenState extends State<AdminJobAlertFormScreen> {
  late final _examController =
      TextEditingController(text: widget.existing?.examName ?? '');
  late final _orgController =
      TextEditingController(text: widget.existing?.organization ?? '');
  late final _postController =
      TextEditingController(text: widget.existing?.post ?? '');
  late final _eligibilityController =
      TextEditingController(text: widget.existing?.eligibility ?? '');
  late final _datesController =
      TextEditingController(text: widget.existing?.importantDates ?? '');
  late final _urlController =
      TextEditingController(text: widget.existing?.applicationUrl ?? '');
  late final _descriptionController =
      TextEditingController(text: widget.existing?.description ?? '');
  late bool _published = widget.existing?.published ?? false;
  DateTime? _start;
  DateTime? _last;
  bool _isSaving = false;

  static DateTime? _parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim());
  }

  @override
  void initState() {
    super.initState();
    _start = _parse(widget.existing?.applicationStartDate);
    _last = _parse(widget.existing?.lastDate);
  }

  @override
  void dispose() {
    _examController.dispose();
    _orgController.dispose();
    _postController.dispose();
    _eligibilityController.dispose();
    _datesController.dispose();
    _urlController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool start}) async {
    final current = start ? (_start ?? DateTime.now()) : (_last ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _last = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_examController.text.trim().isEmpty) {
      showAdminMessage(context, 'Exam / recruitment name is required.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final item = JobAlert(
        id: widget.existing?.id ?? '',
        examName: _examController.text.trim(),
        organization: _orgController.text.trim(),
        post: _postController.text.trim(),
        eligibility: _eligibilityController.text.trim(),
        description: _descriptionController.text.trim(),
        importantDates: _datesController.text.trim(),
        applicationStartDate:
            _start == null ? '' : DailyStudyPlan.dateKeyFor(_start),
        lastDate: _last == null ? '' : DailyStudyPlan.dateKeyFor(_last),
        applicationUrl: _urlController.text.trim(),
        published: _published,
        createdAt: widget.existing?.createdAt,
      );
      if (widget.existing == null) {
        await jobAlertsRepository.add(item);
        await auditLogRepository.log(
          action: 'create',
          module: 'Job Alerts',
          targetLabel: item.examName,
        );
      } else {
        await jobAlertsRepository.update(item);
        await auditLogRepository.log(
          action: 'update',
          module: 'Job Alerts',
          targetLabel: item.examName,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminFormScaffold(
      title: widget.existing == null ? 'Add Job Alert' : 'Edit Job Alert',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        TextField(
          controller: _examController,
          decoration: const InputDecoration(
            labelText: 'Exam / recruitment name',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _orgController,
          decoration: const InputDecoration(labelText: 'Organization'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _postController,
          decoration: const InputDecoration(labelText: 'Post'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _eligibilityController,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Eligibility'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _datesController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Important dates (optional notes)',
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            _start == null
                ? 'Application start date (optional)'
                : 'Application start: ${DailyStudyPlan.dateKeyFor(_start)}',
          ),
          trailing: const Icon(Icons.calendar_today_rounded),
          onTap: () => _pick(start: true),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            _last == null
                ? 'Last date to apply (optional)'
                : 'Last date: ${DailyStudyPlan.dateKeyFor(_last)}',
          ),
          trailing: const Icon(Icons.event_busy_rounded),
          onTap: () => _pick(start: false),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _urlController,
          decoration: const InputDecoration(
            labelText: 'Official application URL',
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _descriptionController,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Published'),
          subtitle: const Text(
            'Students only see published alerts. Unpublish to hide without deleting.',
          ),
          value: _published,
          onChanged: (v) => setState(() => _published = v),
        ),
      ],
    );
  }
}
