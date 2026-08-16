import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_chapters_screen.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_subject_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/storage_service.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Admin Subjects list — add / edit / delete / publish, then open Topics.
class AdminSubjectsScreen extends StatefulWidget {
  const AdminSubjectsScreen({super.key});

  @override
  State<AdminSubjectsScreen> createState() => _AdminSubjectsScreenState();
}

class _AdminSubjectsScreenState extends State<AdminSubjectsScreen> {
  String _query = '';

  List<SubjectItem> _filter(List<SubjectItem> subjects) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return subjects;
    return subjects.where((s) {
      return s.title.toLowerCase().contains(q) ||
          s.subtitle.toLowerCase().contains(q) ||
          s.nameEn.toLowerCase().contains(q) ||
          s.slug.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Subjects',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AdminSubjectFormScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<SubjectItem>>(
        stream: notesRepository.watchSubjects(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load subjects: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final all = snapshot.data!;
          final subjects = _filter(all);
          if (all.isEmpty) {
            return const EmptyState(
              message: 'No subjects yet. Tap + to add the first subject '
                  '(e.g. राज्यशास्त्र / Polity).',
              icon: Icons.library_books_outlined,
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search subjects…',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tap a subject to manage Topics. Drag ☰ to reorder.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ),
              Expanded(
                child: subjects.isEmpty
                    ? const EmptyState(
                        message: 'No subjects match your search.',
                        icon: Icons.search_off_rounded,
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: subjects.length,
                        onReorder: (oldIndex, newIndex) async {
                          // Reorder against the full unfiltered list so search
                          // mode cannot scramble global order unexpectedly.
                          if (_query.trim().isNotEmpty) {
                            showAdminMessage(
                              context,
                              'Clear search before reordering subjects.',
                            );
                            return;
                          }
                          final reordered = List.of(subjects);
                          if (newIndex > oldIndex) newIndex -= 1;
                          final moved = reordered.removeAt(oldIndex);
                          reordered.insert(newIndex, moved);
                          try {
                            for (var i = 0; i < reordered.length; i++) {
                              if (reordered[i].order != i) {
                                await notesRepository
                                    .updateSubject(reordered[i].copyWith(order: i));
                              }
                            }
                          } catch (e) {
                            if (context.mounted) showAdminError(context, e);
                          }
                        },
                        itemBuilder: (context, index) {
                          final subject = subjects[index];
                          return AdminListTile(
                            key: ValueKey(subject.id),
                            title: subject.title,
                            subtitle:
                                '${subject.published ? 'Published' : 'Draft'} · '
                                'id=${subject.id}'
                                '${subject.slug.isNotEmpty ? ' · ${subject.slug}' : ''}'
                                '${subject.subtitle.isNotEmpty ? ' · ${subject.subtitle}' : ''}',
                            icon: subject.icon,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AdminChaptersScreen(subject: subject),
                              ),
                            ),
                            onEdit: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AdminSubjectFormScreen(existing: subject),
                              ),
                            ),
                            onDelete: () async {
                              final confirmed = await confirmDelete(context, subject.title);
                              if (!confirmed) return;
                              try {
                                await notesRepository.deleteSubject(subject.id);
                                if (subject.imageUrl.isNotEmpty) {
                                  await storageService.deleteByUrl(subject.imageUrl);
                                }
                                await auditLogRepository.log(
                                  action: 'delete',
                                  module: 'Subjects',
                                  targetLabel: subject.title,
                                );
                                if (context.mounted) {
                                  showAdminMessage(context, 'Subject deleted.');
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
