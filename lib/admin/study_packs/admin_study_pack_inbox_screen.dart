import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/notes/admin_note_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/study_content_pack.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/study_content_session_service.dart';
import 'package:mpsc_combine_ai/services/study_pack_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';
import 'package:mpsc_combine_ai/widgets/rag_study_tool_sheets.dart';

/// Admin inbox for student-submitted AI study packs. Save as notes draft only.
class AdminStudyPackInboxScreen extends StatelessWidget {
  const AdminStudyPackInboxScreen({super.key});

  Future<void> _saveDraft(BuildContext context, StudyContentPack pack) async {
    try {
      final noteId = await studyContentSessionService.savePackAsNotesDraft(pack);
      await auditLogRepository.log(
        action: 'ai-generate',
        module: 'Notes',
        targetLabel: pack.topic,
        details: 'Saved AI study pack as unpublished draft $noteId',
      );
      if (!context.mounted) return;
      showAdminMessage(context, 'Saved as Notes draft. Not published.');
      final note = await notesRepository.getNote(noteId);
      if (!context.mounted || note == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AdminNoteFormScreen(existingNote: note),
        ),
      );
    } catch (e) {
      if (context.mounted) showAdminError(context, e);
    }
  }

  Future<void> _dismiss(BuildContext context, StudyContentPack pack) async {
    final ok = await confirmDelete(context, pack.topic);
    if (!ok) return;
    try {
      await studyPackRepository.dismiss(pack.id);
      await auditLogRepository.log(
        action: 'delete',
        module: 'Study Content',
        targetLabel: pack.topic,
        details: 'Dismissed study pack',
      );
    } catch (e) {
      if (context.mounted) showAdminError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Study Content Review',
      body: StreamBuilder<List<StudyContentPack>>(
        stream: studyPackRepository.watchPendingReview(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: '${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final packs = snapshot.data!;
          if (packs.isEmpty) {
            return const EmptyState(
              message: 'No AI study packs waiting for review.',
              icon: Icons.rate_review_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: packs.length,
            itemBuilder: (context, index) {
              final pack = packs[index];
              return AdminListTile(
                title: pack.topic,
                subtitle: 'Draft review · ${pack.uid} · '
                    '${pack.citations.length} source ref(s) · never published',
                icon: Icons.auto_stories_outlined,
                onPreview: () => showRagStudySheet(
                  context: context,
                  title: pack.topic,
                  child: RagSummaryView(summary: pack.asSummary),
                ),
                onApprove: () => _saveDraft(context, pack),
                onEdit: () => _saveDraft(context, pack),
                onDelete: () => _dismiss(context, pack),
              );
            },
          );
        },
      ),
    );
  }
}
