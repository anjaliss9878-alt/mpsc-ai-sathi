import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/line_list_field.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

/// Edits the single note document belonging to [chapter] — creates one if
/// none exists yet.
class AdminNoteFormScreen extends StatefulWidget {
  const AdminNoteFormScreen({super.key, required this.subjectId, required this.chapter});

  final String subjectId;
  final ChapterItem chapter;

  @override
  State<AdminNoteFormScreen> createState() => _AdminNoteFormScreenState();
}

class _AdminNoteFormScreenState extends State<AdminNoteFormScreen> {
  bool _isSaving = false;
  bool _loaded = false;
  String? _noteId;
  final _pointsKey = GlobalKey<LineListFieldState>();
  final _summaryKey = GlobalKey<LineListFieldState>();
  NoteItem? _initial;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final note = await notesRepository.getNoteForChapter(widget.chapter.id);
      if (!mounted) return;
      setState(() {
        _initial = note;
        _noteId = note?.id;
        _loaded = true;
      });
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await notesRepository.saveNote(
        noteId: _noteId,
        subjectId: widget.subjectId,
        chapterId: widget.chapter.id,
        importantPoints: _pointsKey.currentState?.lines ?? const [],
        revisionSummary: _summaryKey.currentState?.lines ?? const [],
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text('Notes — ${widget.chapter.title}')),
        body: const LoadingState(),
      );
    }
    return AdminFormScaffold(
      title: 'Notes — ${widget.chapter.title}',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        const Text(
          'One bullet point per line. Blank lines are ignored.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const AdminSectionLabel(label: 'Important Points'),
        LineListField(
          key: _pointsKey,
          label: 'Important Points',
          initialLines: _initial?.importantPoints ?? const [],
          hintText: 'e.g. रेग्युलेटिंग ॲक्ट, 1773 हा ...',
          minLines: 5,
        ),
        const AdminSectionLabel(label: 'Revision Summary'),
        LineListField(
          key: _summaryKey,
          label: 'Revision Summary',
          initialLines: _initial?.revisionSummary ?? const [],
          hintText: 'e.g. 1773 — कंपनीच्या कारभारावर संसदीय नियंत्रणाची सुरुवात',
          minLines: 5,
        ),
      ],
    );
  }
}
