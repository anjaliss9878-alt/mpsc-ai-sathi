import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/bulk_pyq_row.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/spreadsheet_parser.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/content_index_resolver.dart';
import 'package:mpsc_combine_ai/services/content_knowledge_indexer.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

enum _Stage { pick, preview, uploading, done }

class AdminPyqBulkUploadScreen extends StatefulWidget {
  const AdminPyqBulkUploadScreen({super.key});

  @override
  State<AdminPyqBulkUploadScreen> createState() =>
      _AdminPyqBulkUploadScreenState();
}

class _AdminPyqBulkUploadScreenState extends State<AdminPyqBulkUploadScreen> {
  _Stage _stage = _Stage.pick;
  String? _fileName;
  List<BulkPyqRow> _rows = [];
  String? _pickError;
  double _uploadProgress = 0;
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
      final rows = <BulkPyqRow>[];
      for (var i = 0; i < parsed.length; i++) {
        rows.add(BulkPyqRow.parse(i + 2, parsed[i], index: index));
      }
      await _markDuplicates(rows);
      setState(() {
        _fileName = file.name;
        _rows = rows;
        _stage = _Stage.preview;
      });
    } catch (e) {
      setState(() => _pickError = 'Could not parse this file: $e');
    }
  }

  Future<void> _markDuplicates(List<BulkPyqRow> rows) async {
    final existing =
        await FirebaseFirestore.instance.collection(PyqRepository.collection).get();
    final existingQuestions = existing.docs
        .map((d) => (d.data()['question'] as String? ?? '').trim().toLowerCase())
        .where((q) => q.isNotEmpty)
        .toSet();
    final seenInFile = <String>{};
    for (final row in rows) {
      final key = row.question.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (existingQuestions.contains(key) || seenInFile.contains(key)) {
        row.isDuplicate = true;
      }
      seenInFile.add(key);
    }
  }

  Future<void> _upload() async {
    final toUpload = _rows.where((r) => r.willUpload).toList();
    if (toUpload.isEmpty) return;
    setState(() {
      _stage = _Stage.uploading;
      _uploadProgress = 0;
      _uploadedCount = 0;
      _uploadError = null;
    });

    final firestore = FirebaseFirestore.instance;
    final writtenRefs = <DocumentReference<Map<String, dynamic>>>[];
    final writtenItems = <PyqItem>[];
    const chunkSize = 400;
    try {
      for (var i = 0; i < toUpload.length; i += chunkSize) {
        final chunk = toUpload.skip(i).take(chunkSize).toList();
        final batch = firestore.batch();
        final refsThisChunk = <DocumentReference<Map<String, dynamic>>>[];
        for (final row in chunk) {
          final ref = firestore.collection(PyqRepository.collection).doc();
          final item = PyqItem(
            id: ref.id,
            title: row.question,
            subtitle: '',
            fileUrl: '',
            order: DateTime.now().millisecondsSinceEpoch + i,
            year: row.year,
            examName: 'MPSC Combine',
            question: row.question,
            answer: row.answer,
            explanation: row.explanation,
            subject: row.subjectTitle,
            subjectId: row.subjectId,
            chapterId: row.chapterId,
            tags: row.tags,
            published: false,
            examId: row.examId,
            targetGroup: row.targetGroup,
            topicId: row.topicId,
            options: row.options,
            correctIndex: row.correctIndex,
            difficulty: row.difficulty,
            source: row.source,
            status: NoteWorkflowStatus.draft,
          );
          batch.set(ref, item.toMap());
          refsThisChunk.add(ref);
          writtenItems.add(item);
        }
        await batch.commit();
        writtenRefs.addAll(refsThisChunk);
        setState(() {
          _uploadedCount = writtenRefs.length;
          _uploadProgress = writtenRefs.length / toUpload.length;
        });
      }
      await auditLogRepository.log(
        action: 'bulk-upload',
        module: 'PYQs',
        targetLabel: _fileName ?? 'upload',
        details:
            '${writtenRefs.length} PYQ(s) imported as DRAFT, $_duplicateCount skipped as duplicate, $_invalidCount invalid',
      );
      for (final item in writtenItems) {
        try {
          await contentKnowledgeIndexer.syncPyq(item);
        } catch (_) {}
      }
      setState(() => _stage = _Stage.done);
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
      _uploadProgress = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Bulk Upload — PYQs',
      body: switch (_stage) {
        _Stage.pick => _buildPickStage(),
        _Stage.preview => _buildPreviewStage(),
        _Stage.uploading => _buildUploadingStage(),
        _Stage.done => _buildDoneStage(),
      },
    );
  }

  Widget _buildPickStage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.upload_file_rounded, size: 56, color: AppColors.navy),
            const SizedBox(height: 16),
            const Text(
              'Import PYQs from CSV or Excel (.xlsx)',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Imported rows stay DRAFT until you publish.\n'
              'Expected columns: ${bulkPyqExpectedHeaders.join(', ')}',
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

  Widget _buildPreviewStage() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _fileName ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: _reset,
                child: const Text('Choose different file'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _StatChip(label: 'Ready (DRAFT)', value: _validCount, color: Colors.green),
              _StatChip(label: 'Duplicates', value: _duplicateCount, color: Colors.orange),
              _StatChip(label: 'Invalid', value: _invalidCount, color: Colors.red),
            ],
          ),
        ),
        if (_uploadError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(_uploadError!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _rows.length,
            itemBuilder: (context, index) {
              final row = _rows[index];
              final Color color;
              final String status;
              if (!row.isValid) {
                color = Colors.red;
                status = row.errors.join('; ');
              } else if (row.isDuplicate) {
                color = Colors.orange;
                status = 'Duplicate question — skipped';
              } else {
                color = Colors.green;
                status = 'Ready · DRAFT';
              }
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Text(
                      '${row.rowNumber}',
                      style: TextStyle(fontSize: 11, color: color),
                    ),
                  ),
                  title: Text(
                    row.question.isEmpty ? '(empty question)' : row.question,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  subtitle: Text(status, style: TextStyle(color: color, fontSize: 11)),
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

  Widget _buildUploadingStage() {
    final total = _rows.where((r) => r.willUpload).length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 220,
              child: LinearProgressIndicator(
                value: _uploadProgress == 0 ? null : _uploadProgress,
              ),
            ),
            const SizedBox(height: 16),
            Text('Uploading… $_uploadedCount / $total'),
          ],
        ),
      ),
    );
  }

  Widget _buildDoneStage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 56, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              '$_uploadedCount PYQ(s) imported as DRAFT.',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'They are hidden from students until you publish.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _reset,
              child: const Text('Import another file'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$value $label',
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
