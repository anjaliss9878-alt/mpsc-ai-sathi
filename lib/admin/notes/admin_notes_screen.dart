import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_note_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_content_filter_bar.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_preview.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/note_rag_indexer.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Admin Content → Notes list (same `notes` collection students read).
class AdminNotesScreen extends StatefulWidget {
  const AdminNotesScreen({super.key});

  @override
  State<AdminNotesScreen> createState() => _AdminNotesScreenState();
}

class _AdminNotesScreenState extends State<AdminNotesScreen> {
  String _query = '';
  NoteWorkflowStatus? _status;
  String? _difficulty;
  String? _language;
  String? _subjectId;
  String? _chapterId;
  String? _topicId;
  DateTime? _date;

  Future<void> _setStatus(NoteItem note, NoteWorkflowStatus status) async {
    try {
      await notesRepository.patchNote(note.id, {
        'status': noteWorkflowStatusToString(status),
        'published': noteWorkflowPublishedFlag(status),
      });
      try {
        final updated = await notesRepository.getNote(note.id);
        if (updated != null) await noteRagIndexer.syncPublished(updated);
      } catch (_) {}
      await auditLogRepository.log(
        action: status == NoteWorkflowStatus.published
            ? 'publish'
            : status == NoteWorkflowStatus.approved
                ? 'approve'
                : 'unpublish',
        module: 'Notes',
        targetLabel: note.title,
      );
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  List<NoteItem> _filter(List<NoteItem> notes) {
    return notes.where((n) {
      return matchesAdminContentFilters(
        query: _query,
        fields: [n.title, n.description, n.topicId, ...n.tags],
        status: _status,
        itemStatus: n.status,
        difficulty: _difficulty,
        itemDifficulty: n.difficulty,
        language: _language,
        itemLanguage: n.language,
        subjectId: _subjectId,
        itemSubjectId: n.subjectId,
        chapterId: _chapterId,
        itemChapterId: n.chapterId,
        topicId: _topicId,
        itemTopicId: n.resolvedTopicId,
        date: _date,
        itemDate: n.updatedAt,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Notes',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AdminNoteFormScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<NoteItem>>(
        stream: notesRepository.watchAllNotes(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load notes: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final all = snapshot.data!;
          final notes = _filter(all);
          if (all.isEmpty) {
            return const EmptyState(
              message: 'No notes yet. Tap + to add a PDF note under '
                  'Exam → Subject → Chapter → Topic.',
              icon: Icons.picture_as_pdf_outlined,
            );
          }
          return Column(
            children: [
              AdminContentFilterBar(
                queryHint: 'Search title, topic, tags…',
                onQueryChanged: (v) => setState(() => _query = v),
                status: _status,
                onStatusChanged: (v) => setState(() => _status = v),
                difficulty: _difficulty,
                onDifficultyChanged: (v) => setState(() => _difficulty = v),
                language: _language,
                onLanguageChanged: (v) => setState(() => _language = v),
                subjectId: _subjectId,
                onSubjectIdChanged: (v) => setState(() => _subjectId = v),
                chapterId: _chapterId,
                onChapterIdChanged: (v) => setState(() => _chapterId = v),
                topicId: _topicId,
                onTopicIdChanged: (v) => setState(() => _topicId = v),
                date: _date,
                onDateChanged: (v) => setState(() => _date = v),
                showIndexFilters: true,
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Draft / unpublished notes stay hidden from students.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ),
              Expanded(
                child: notes.isEmpty
                    ? const EmptyState(
                        message: 'No notes match your search.',
                        icon: Icons.search_off_rounded,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: notes.length,
                        itemBuilder: (context, index) {
                          final note = notes[index];
                          return AdminListTile(
                            title: note.title.isNotEmpty ? note.title : 'Untitled note',
                            subtitle:
                                '${noteWorkflowStatusLabel(note.status)} · '
                                'RAG ${noteRagStatusLabel(note.ragStatus)}'
                                '${note.pdfFileName.isNotEmpty ? ' · ${note.pdfFileName}' : ''}',
                            icon: Icons.picture_as_pdf_rounded,
                            isActive: note.status == NoteWorkflowStatus.published,
                            onPreview: () => showNotePreview(context, note),
                            onApprove: () => _setStatus(
                              note,
                              NoteWorkflowStatus.approved,
                            ),
                            onToggleActive: () => _setStatus(
                              note,
                              note.status == NoteWorkflowStatus.published
                                  ? NoteWorkflowStatus.unpublished
                                  : NoteWorkflowStatus.published,
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AdminNoteFormScreen(
                                  existingNote: note,
                                  subjectId: note.subjectId,
                                  examId: note.examId,
                                ),
                              ),
                            ),
                            onEdit: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AdminNoteFormScreen(
                                  existingNote: note,
                                  subjectId: note.subjectId,
                                  examId: note.examId,
                                ),
                              ),
                            ),
                            onDelete: () async {
                              final label =
                                  note.title.isNotEmpty ? note.title : note.id;
                              final confirmed =
                                  await confirmDelete(context, label);
                              if (!confirmed) return;
                              try {
                                await notesRepository.deleteNote(note.id);
                                await auditLogRepository.log(
                                  action: 'delete',
                                  module: 'Notes',
                                  targetLabel: label,
                                );
                                if (context.mounted) {
                                  showAdminMessage(context, 'Note deleted.');
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
