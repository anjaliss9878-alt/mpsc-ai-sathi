import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/faculty_item.dart';
import 'package:mpsc_combine_ai/models/live_class_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/faculty_repository.dart';
import 'package:mpsc_combine_ai/services/live_class_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Create/Schedule/Edit a Live Class — one form covers both "Create Live
/// Class" and "Schedule Class" since scheduling fields ([scheduledAt],
/// [durationMinutes]) are just part of a class's normal data.
///
/// [roomId] is reserved for a future 100ms integration (see
/// `live_class_video_service.dart`) and is not used by any join flow today.
class AdminLiveClassFormScreen extends StatefulWidget {
  const AdminLiveClassFormScreen({super.key, this.existing});

  final LiveClassItem? existing;

  @override
  State<AdminLiveClassFormScreen> createState() => _AdminLiveClassFormScreenState();
}

class _AdminLiveClassFormScreenState extends State<AdminLiveClassFormScreen> {
  late final _titleController = TextEditingController(text: widget.existing?.title ?? '');
  late final _descriptionController =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _subjectController =
      TextEditingController(text: widget.existing?.subject ?? '');
  late final _bannerController =
      TextEditingController(text: widget.existing?.bannerImageUrl ?? '');
  late final _urlController =
      TextEditingController(text: widget.existing?.meetingUrl ?? '');
  late final _roomIdController = TextEditingController(text: widget.existing?.roomId ?? '');
  late final _recordingController =
      TextEditingController(text: widget.existing?.recordingUrl ?? '');
  late final _scheduleTextController =
      TextEditingController(text: widget.existing?.scheduleText ?? '');
  late final _durationController = TextEditingController(
    text: (widget.existing?.durationMinutes ?? 60).toString(),
  );
  late String _platform = widget.existing?.platform ?? liveClassPlatforms.first;
  late String _status = widget.existing?.status ?? 'upcoming';
  late String _facultyId = widget.existing?.facultyId ?? '';
  late String _facultyName = widget.existing?.facultyName ?? '';
  late DateTime _scheduledAt = (widget.existing?.hasSchedule ?? false)
      ? widget.existing!.scheduledAt
      : DateTime.now().add(const Duration(hours: 1));
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _subjectController.dispose();
    _bannerController.dispose();
    _urlController.dispose();
    _roomIdController.dispose();
    _recordingController.dispose();
    _scheduleTextController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null) return;
    setState(() {
      _scheduledAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _scheduledAt.hour,
        _scheduledAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (picked == null) return;
    setState(() {
      _scheduledAt = DateTime(
        _scheduledAt.year,
        _scheduledAt.month,
        _scheduledAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      showAdminMessage(context, 'Title is required.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final item = LiveClassItem(
        id: widget.existing?.id ?? '',
        title: _titleController.text.trim(),
        subject: _subjectController.text.trim(),
        meetingUrl: _urlController.text.trim(),
        platform: _platform,
        scheduleText: _scheduleTextController.text.trim(),
        status: _status,
        description: _descriptionController.text.trim(),
        facultyId: _facultyId,
        facultyName: _facultyName,
        bannerImageUrl: _bannerController.text.trim(),
        roomId: _roomIdController.text.trim(),
        recordingUrl: _recordingController.text.trim(),
        durationMinutes: int.tryParse(_durationController.text.trim()) ?? 60,
        attendanceCount: widget.existing?.attendanceCount ?? 0,
        scheduledAt: _scheduledAt,
      );
      if (widget.existing == null) {
        await liveClassRepository.add(item);
        await auditLogRepository.log(action: 'create', module: 'Live Classes', targetLabel: item.title);
      } else {
        await liveClassRepository.update(item);
        await auditLogRepository.log(action: 'update', module: 'Live Classes', targetLabel: item.title);
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
      title: widget.existing == null ? 'Add Live Class' : 'Edit Live Class',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _descriptionController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Description (optional)'),
        ),

        const AdminSectionLabel(label: 'Subject'),
        TextField(
          controller: _subjectController,
          decoration: const InputDecoration(labelText: 'Subject (e.g. Polity)'),
        ),
        const SizedBox(height: 8),
        _SubjectSuggestions(
          onSelected: (title) => setState(() => _subjectController.text = title),
        ),

        const AdminSectionLabel(label: 'Faculty'),
        _FacultyPicker(
          selectedFacultyId: _facultyId,
          onSelected: (id, name) => setState(() {
            _facultyId = id;
            _facultyName = name;
          }),
        ),

        const AdminSectionLabel(label: 'Banner'),
        TextField(
          controller: _bannerController,
          decoration: const InputDecoration(
            labelText: 'Banner Image URL (optional)',
            hintText: 'https://...',
          ),
        ),

        const AdminSectionLabel(label: 'Schedule'),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: Text(
                  '${_scheduledAt.day}/${_scheduledAt.month}/${_scheduledAt.year}',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.access_time_rounded, size: 16),
                label: Text(TimeOfDay.fromDateTime(_scheduledAt).format(context)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _durationController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Duration (minutes)'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _scheduleTextController,
          decoration: const InputDecoration(
            labelText: 'Schedule note shown to students (optional)',
            hintText: 'e.g. Recurring every Monday & Wednesday',
          ),
        ),

        const AdminSectionLabel(label: 'Meeting / Room'),
        DropdownButtonFormField<String>(
          initialValue: _platform,
          decoration: const InputDecoration(labelText: 'Platform'),
          items: liveClassPlatforms
              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
              .toList(),
          onChanged: (value) => setState(() => _platform = value ?? _platform),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _urlController,
          decoration: const InputDecoration(
            labelText: 'Meeting / stream link',
            hintText: 'https://meet.google.com/...',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _roomIdController,
          decoration: const InputDecoration(
            labelText: 'Room ID (reserved for 100ms — optional, unused today)',
          ),
        ),

        const AdminSectionLabel(label: 'Recording'),
        TextField(
          controller: _recordingController,
          decoration: const InputDecoration(
            labelText: 'Recording URL (once the class is completed)',
            hintText: 'https://...',
          ),
        ),

        const AdminSectionLabel(label: 'Status'),
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Status'),
          items: liveClassStatuses
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: (value) => setState(() => _status = value ?? _status),
        ),
      ],
    );
  }
}

class _SubjectSuggestions extends StatelessWidget {
  const _SubjectSuggestions({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SubjectItem>>(
      stream: notesRepository.watchSubjects(),
      builder: (context, snapshot) {
        final subjects = snapshot.data ?? const <SubjectItem>[];
        if (subjects.isEmpty) return const SizedBox.shrink();
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: subjects
              .map(
                (s) => ActionChip(
                  label: Text(s.title),
                  onPressed: () => onSelected(s.title),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _FacultyPicker extends StatelessWidget {
  const _FacultyPicker({required this.selectedFacultyId, required this.onSelected});

  final String selectedFacultyId;
  final void Function(String id, String name) onSelected;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FacultyItem>>(
      stream: facultyRepository.watchAll(),
      builder: (context, snapshot) {
        final faculty = snapshot.data ?? const <FacultyItem>[];
        if (faculty.isEmpty) {
          return const Text(
            'No faculty added yet. Add one from Admin Dashboard → Faculty, '
            'then come back to assign them here.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          );
        }
        final validValue = faculty.any((f) => f.id == selectedFacultyId)
            ? selectedFacultyId
            : null;
        return DropdownButtonFormField<String>(
          initialValue: validValue,
          decoration: const InputDecoration(labelText: 'Assign faculty (optional)'),
          items: faculty
              .map((f) => DropdownMenuItem(value: f.id, child: Text(f.name)))
              .toList(),
          onChanged: (value) {
            final match = faculty.firstWhere(
              (f) => f.id == value,
              orElse: () => const FacultyItem(
                id: '',
                name: '',
                designation: '',
                subject: '',
                photoUrl: '',
                bio: '',
              ),
            );
            onSelected(match.id, match.name);
          },
        );
      },
    );
  }
}
