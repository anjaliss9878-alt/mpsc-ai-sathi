import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/bulk_mcq_row.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/spreadsheet_parser.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

enum _Stage { pick, preview, uploading, done }

/// Bulk-import MCQs from a CSV or Excel (.xlsx) file: pick → parse → preview
/// with per-row validation → skip duplicates against existing questions →
/// upload with progress → error report. If any batch fails partway through,
/// every document already written by this run is deleted again so the
/// import is all-or-nothing (no partially-applied bulk upload).
class AdminBulkUploadScreen extends StatefulWidget {
  const AdminBulkUploadScreen({super.key});

  @override
  State<AdminBulkUploadScreen> createState() => _AdminBulkUploadScreenState();
}

class _AdminBulkUploadScreenState extends State<AdminBulkUploadScreen> {
  _Stage _stage = _Stage.pick;
  String? _fileName;
  List<BulkMcqRow> _rows = [];
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
      final rows = <BulkMcqRow>[];
      for (var i = 0; i < parsed.length; i++) {
        rows.add(BulkMcqRow.parse(i + 2, parsed[i])); // +2: header is row 1
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

  Future<void> _markDuplicates(List<BulkMcqRow> rows) async {
    final existing = await FirebaseFirestore.instance.collection(McqRepository.collection).get();
    final existingQuestions = existing.docs
        .map((d) => (d.data()['question'] as String? ?? '').trim().toLowerCase())
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
    const chunkSize = 400;
    try {
      for (var i = 0; i < toUpload.length; i += chunkSize) {
        final chunk = toUpload.skip(i).take(chunkSize).toList();
        final batch = firestore.batch();
        final refsThisChunk = <DocumentReference<Map<String, dynamic>>>[];
        for (final row in chunk) {
          final ref = firestore.collection(McqRepository.collection).doc();
          final item = McqItem(
            id: ref.id,
            setTitle: row.setTitle,
            subject: row.subject,
            difficulty: row.difficulty,
            question: row.question,
            options: row.options,
            correctIndex: row.correctIndex,
            explanation: row.explanation,
            order: 0,
            tags: row.tags,
          );
          batch.set(ref, item.toMap());
          refsThisChunk.add(ref);
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
        module: 'MCQs',
        targetLabel: _fileName ?? 'upload',
        details: '${writtenRefs.length} question(s) imported, $_duplicateCount skipped as duplicate, $_invalidCount invalid',
      );
      setState(() => _stage = _Stage.done);
    } catch (e) {
      // Roll back everything this run already committed so a mid-import
      // failure never leaves a half-imported set of MCQs behind.
      for (final ref in writtenRefs) {
        try {
          await ref.delete();
        } catch (_) {
          // Best-effort rollback; nothing more we can do if a delete itself
          // fails (e.g. network dropped) — surfaced via _uploadError below.
        }
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
      title: 'Bulk Upload — MCQs',
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
              'Import MCQs from CSV or Excel (.xlsx)',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Expected columns: ${bulkMcqExpectedHeaders.join(', ')}',
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
              TextButton(onPressed: _reset, child: const Text('Choose different file')),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _StatChip(label: 'Ready to upload', value: _validCount, color: Colors.green),
              _StatChip(label: 'Duplicates (skipped)', value: _duplicateCount, color: Colors.orange),
              _StatChip(label: 'Invalid (skipped)', value: _invalidCount, color: Colors.red),
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
                status = 'Ready';
              }
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Text('${row.rowNumber}', style: TextStyle(fontSize: 11, color: color)),
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
                label: Text('Upload $_validCount question(s)'),
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
              child: LinearProgressIndicator(value: _uploadProgress == 0 ? null : _uploadProgress),
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
              '$_uploadedCount question(s) imported successfully.',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '$_duplicateCount duplicate(s) and $_invalidCount invalid row(s) were skipped.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _reset, child: const Text('Import another file')),
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
      child: Text('$value $label', style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}
