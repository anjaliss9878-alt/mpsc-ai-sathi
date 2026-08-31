import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/bulk_flashcard_row.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/spreadsheet_parser.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/flashcard_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/content_index_resolver.dart';
import 'package:mpsc_combine_ai/services/flashcard_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

enum _Stage { pick, preview, uploading, done }

class AdminFlashcardBulkUploadScreen extends StatefulWidget {
  const AdminFlashcardBulkUploadScreen({super.key});

  @override
  State<AdminFlashcardBulkUploadScreen> createState() =>
      _AdminFlashcardBulkUploadScreenState();
}

class _AdminFlashcardBulkUploadScreenState
    extends State<AdminFlashcardBulkUploadScreen> {
  _Stage _stage = _Stage.pick;
  String? _fileName;
  List<BulkFlashcardRow> _rows = [];
  String? _pickError;
  int _uploadedCount = 0;
  String? _uploadError;

  int get _validCount => _rows.where((r) => r.willUpload).length;
  int get _duplicateCount => _rows.where((r) => r.isDuplicate).length;
  int get _invalidCount => _rows.where((r) => !r.isValid).length;

  Future<void> _pickFile() async {
    setState(() => _pickError = null);
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _pickError = 'Could not read the selected file.');
      return;
    }
    try {
      final parsed = parseSpreadsheetBytes(file.name, bytes);
      if (parsed.isEmpty) {
        setState(() => _pickError = 'No data rows found in this file.');
        return;
      }
      final index = await ContentIndexResolver.load(notesRepository);
      final rows = <BulkFlashcardRow>[];
      for (var i = 0; i < parsed.length; i++) {
        rows.add(BulkFlashcardRow.parse(i + 2, parsed[i], index: index));
      }
      final existing = await FirebaseFirestore.instance
          .collection(FlashcardRepository.collection)
          .get();
      final existingFronts = existing.docs
          .map((d) => (d.data()['front'] as String? ?? '').trim().toLowerCase())
          .where((q) => q.isNotEmpty)
          .toSet();
      final seen = <String>{};
      for (final row in rows) {
        final key = row.front.trim().toLowerCase();
        if (key.isEmpty) continue;
        if (existingFronts.contains(key) || seen.contains(key)) {
          row.isDuplicate = true;
        }
        seen.add(key);
      }
      setState(() {
        _fileName = file.name;
        _rows = rows;
        _stage = _Stage.preview;
      });
    } catch (e) {
      setState(() => _pickError = 'Could not parse this file: $e');
    }
  }

  Future<void> _upload() async {
    final toUpload = _rows.where((r) => r.willUpload).toList();
    if (toUpload.isEmpty) return;
    setState(() {
      _stage = _Stage.uploading;
      _uploadedCount = 0;
      _uploadError = null;
    });
    final firestore = FirebaseFirestore.instance;
    final writtenRefs = <DocumentReference<Map<String, dynamic>>>[];
    try {
      final batch = firestore.batch();
      for (var i = 0; i < toUpload.length; i++) {
        final row = toUpload[i];
        final ref = firestore.collection(FlashcardRepository.collection).doc();
        final item = FlashcardItem(
          id: ref.id,
          title: row.title,
          front: row.front,
          back: row.back,
          explanation: row.explanation,
          difficulty: row.difficulty,
          tags: row.tags,
          examId: row.examId,
          targetGroup: row.targetGroup.isEmpty ? 'groupB' : row.targetGroup,
          subjectId: row.subjectId,
          chapterId: row.chapterId,
          topicId: row.topicId,
          published: false,
          status: NoteWorkflowStatus.draft,
          order: DateTime.now().millisecondsSinceEpoch + i,
        );
        batch.set(ref, item.toMap());
        writtenRefs.add(ref);
      }
      await batch.commit();
      await auditLogRepository.log(
        action: 'bulk-upload',
        module: 'Flashcards',
        targetLabel: _fileName ?? 'upload',
        details: '${writtenRefs.length} flashcard(s) imported as DRAFT',
      );
      setState(() {
        _uploadedCount = writtenRefs.length;
        _stage = _Stage.done;
      });
    } catch (e) {
      for (final ref in writtenRefs) {
        try {
          await ref.delete();
        } catch (_) {}
      }
      setState(() {
        _uploadError = 'Upload failed and was rolled back: $e';
        _stage = _Stage.preview;
      });
    }
  }

  void _reset() {
    setState(() {
      _stage = _Stage.pick;
      _fileName = null;
      _rows = [];
      _pickError = null;
      _uploadError = null;
      _uploadedCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Bulk Upload — Flashcards',
      body: switch (_stage) {
        _Stage.pick => _pick(),
        _Stage.preview => _preview(),
        _Stage.uploading => const Center(child: CircularProgressIndicator()),
        _Stage.done => _done(),
      },
    );
  }

  Widget _pick() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.style_rounded, size: 56, color: AppColors.navy),
            const SizedBox(height: 16),
            const Text(
              'Import Flashcards from CSV or Excel\nImported rows stay DRAFT until you publish.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Expected columns: ${bulkFlashcardExpectedHeaders.join(', ')}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Choose file'),
            ),
            if (_pickError != null) ...[
              const SizedBox(height: 12),
              Text(_pickError!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    return Column(
      children: [
        ListTile(
          title: Text(_fileName ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          trailing: TextButton(onPressed: _reset, child: const Text('Choose different file')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '$_validCount ready · $_duplicateCount duplicate · $_invalidCount invalid',
          ),
        ),
        if (_uploadError != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_uploadError!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _rows.length,
            itemBuilder: (context, index) {
              final row = _rows[index];
              final color = !row.isValid
                  ? Colors.red
                  : row.isDuplicate
                      ? Colors.orange
                      : Colors.green;
              return ListTile(
                dense: true,
                title: Text(row.front, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  row.isValid
                      ? (row.isDuplicate ? 'Duplicate — skipped' : 'Ready')
                      : row.errors.join('; '),
                  style: TextStyle(color: color, fontSize: 11),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _validCount == 0 ? null : _upload,
                icon: const Icon(Icons.cloud_upload_rounded),
                label: Text('Import $_validCount as DRAFT'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _done() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 56, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              '$_uploadedCount flashcard(s) imported as DRAFT.',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _reset, child: const Text('Import another file')),
          ],
        ),
      ),
    );
  }
}
