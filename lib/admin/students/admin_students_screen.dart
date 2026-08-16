import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

enum StudentFilter { all, active, blocked }

/// Student Management: search + filter + paginate students (client-side, on
/// top of one live Firestore stream — see [ProfileRepository.watchAllStudents]
/// for why), plus Block/Unblock, Assign Courses and a small Progress summary
/// per student.
class AdminStudentsScreen extends StatefulWidget {
  const AdminStudentsScreen({super.key});

  @override
  State<AdminStudentsScreen> createState() => _AdminStudentsScreenState();
}

class _AdminStudentsScreenState extends State<AdminStudentsScreen> {
  final _searchController = TextEditingController();
  StudentFilter _filter = StudentFilter.all;
  int _visibleCount = 20;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffoldForStudents(
      searchController: _searchController,
      onSearchChanged: () => setState(() => _visibleCount = 20),
      filter: _filter,
      onFilterChanged: (f) => setState(() {
        _filter = f;
        _visibleCount = 20;
      }),
      body: StreamBuilder<List<StudentProfile>>(
        stream: profileRepository.watchAllStudents(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load students: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final query = _searchController.text.trim().toLowerCase();
          var students = snapshot.data!;
          if (_filter == StudentFilter.active) {
            students = students.where((s) => !s.isBlocked).toList();
          } else if (_filter == StudentFilter.blocked) {
            students = students.where((s) => s.isBlocked).toList();
          }
          if (query.isNotEmpty) {
            students = students
                .where((s) =>
                    s.name.toLowerCase().contains(query) ||
                    s.email.toLowerCase().contains(query) ||
                    s.mobile.contains(query))
                .toList();
          }
          if (students.isEmpty) {
            return const EmptyState(
              message: 'No students match this search/filter.',
              icon: Icons.people_outline_rounded,
            );
          }
          final visible = students.take(_visibleCount).toList();
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: visible.length + (visible.length < students.length ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == visible.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _visibleCount += 20),
                      child: Text('Load more (${students.length - visible.length} remaining)'),
                    ),
                  ),
                );
              }
              final student = visible[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: student.isBlocked
                        ? Colors.red.withValues(alpha: 0.12)
                        : AppColors.navy.withValues(alpha: 0.08),
                    child: Icon(
                      student.isBlocked ? Icons.block_rounded : Icons.person_rounded,
                      color: student.isBlocked ? Colors.red : AppColors.navy,
                    ),
                  ),
                  title: Text(
                    student.name.isEmpty ? '(No name)' : student.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    [student.email, student.targetExam].where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => _StudentDetailDialog(student: student),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Thin wrapper matching the shared AdminScaffold look, with a search bar +
/// filter chips row bolted onto the AppBar area (kept local to this screen
/// since no other module needs search+filter chrome yet).
class AdminScaffoldForStudents extends StatelessWidget {
  const AdminScaffoldForStudents({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.filter,
    required this.onFilterChanged,
    required this.body,
  });

  final TextEditingController searchController;
  final VoidCallback onSearchChanged;
  final StudentFilter filter;
  final ValueChanged<StudentFilter> onFilterChanged;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Student Management', style: TextStyle(fontWeight: FontWeight.w600))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: searchController,
                    onChanged: (_) => onSearchChanged(),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search by name, email or mobile',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: filter == StudentFilter.all,
                        onSelected: (_) => onFilterChanged(StudentFilter.all),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Active'),
                        selected: filter == StudentFilter.active,
                        onSelected: (_) => onFilterChanged(StudentFilter.active),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Blocked'),
                        selected: filter == StudentFilter.blocked,
                        onSelected: (_) => onFilterChanged(StudentFilter.blocked),
                      ),
                    ],
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StudentDetailDialog extends StatefulWidget {
  const _StudentDetailDialog({required this.student});

  final StudentProfile student;

  @override
  State<_StudentDetailDialog> createState() => _StudentDetailDialogState();
}

class _StudentDetailDialogState extends State<_StudentDetailDialog> {
  late bool _isBlocked = widget.student.isBlocked;
  final Set<String> _assigned = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _assigned.addAll(widget.student.assignedSubjectIds);
  }

  Future<Map<String, int>> _loadProgress() async {
    final firestore = FirebaseFirestore.instance;
    final lessons = await firestore
        .collection('students')
        .doc(widget.student.uid)
        .collection('aiLessons')
        .count()
        .get();
    final attendance = await firestore
        .collection('liveClassAttendance')
        .where('uid', isEqualTo: widget.student.uid)
        .count()
        .get();
    return {
      'lessons': lessons.count ?? 0,
      'attendance': attendance.count ?? 0,
    };
  }

  Future<void> _toggleBlocked(bool value) async {
    setState(() {
      _isBlocked = value;
      _isSaving = true;
    });
    try {
      await profileRepository.setBlocked(widget.student.uid, value);
      await auditLogRepository.log(
        action: value ? 'block' : 'unblock',
        module: 'Students',
        targetLabel: widget.student.name.isEmpty ? widget.student.email : widget.student.name,
      );
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleSubject(String subjectId, bool selected) async {
    setState(() {
      if (selected) {
        _assigned.add(subjectId);
      } else {
        _assigned.remove(subjectId);
      }
    });
    try {
      await profileRepository.setAssignedSubjects(widget.student.uid, _assigned.toList());
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    return AlertDialog(
      title: Text(student.name.isEmpty ? student.email : student.name),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(student.email, style: const TextStyle(color: AppColors.textSecondary)),
              if (student.mobile.isNotEmpty)
                Text(student.mobile, style: const TextStyle(color: AppColors.textSecondary)),
              if (student.targetExam.isNotEmpty)
                Text('Target: ${student.targetExam}', style: const TextStyle(color: AppColors.textSecondary)),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Block this student'),
                subtitle: const Text('Blocked students are signed out immediately.'),
                value: _isBlocked,
                onChanged: _isSaving ? null : _toggleBlocked,
              ),
              const Divider(height: 24),
              const Text('Assigned courses (leave empty = all courses)',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              StreamBuilder<List<SubjectItem>>(
                stream: notesRepository.watchSubjects(),
                builder: (context, snapshot) {
                  final subjects = snapshot.data ?? const <SubjectItem>[];
                  if (subjects.isEmpty) {
                    return const Text('No subjects created yet.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12));
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: subjects.map((s) {
                      final selected = _assigned.contains(s.id);
                      return FilterChip(
                        label: Text(s.title),
                        selected: selected,
                        onSelected: (v) => _toggleSubject(s.id, v),
                      );
                    }).toList(),
                  );
                },
              ),
              const Divider(height: 24),
              const Text('Progress', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              FutureBuilder<Map<String, int>>(
                future: _loadProgress(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    );
                  }
                  final data = snapshot.data!;
                  return Row(
                    children: [
                      _ProgressStat(label: 'AI Lessons', value: data['lessons'] ?? 0),
                      const SizedBox(width: 20),
                      _ProgressStat(label: 'Live Classes Attended', value: data['attendance'] ?? 0),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ProgressStat extends StatelessWidget {
  const _ProgressStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.navy)),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }
}
