import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/admin/widgets/content_index_picker.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/multi_rag_result.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';
import 'package:mpsc_combine_ai/rag/rag_management.dart';
import 'package:mpsc_combine_ai/services/ai_weakness_tracker.dart';
import 'package:mpsc_combine_ai/services/multi_rag_answer_service.dart';
import 'package:mpsc_combine_ai/services/multi_rag_retrieval.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Admin Search/Test console over the existing Multi-RAG engine.
///
/// Student-performance rows are never loaded unless the admin selects that
/// domain **and** an explicit student.
class AdminRagTestConsole extends StatefulWidget {
  const AdminRagTestConsole({
    super.key,
    this.initialQuestion = '',
    this.initialExamId = kDefaultExamId,
    this.initialSubjectId = '',
    this.initialChapterId = '',
    this.initialTopicId = '',
  });

  final String initialQuestion;
  final String initialExamId;
  final String initialSubjectId;
  final String initialChapterId;
  final String initialTopicId;

  @override
  State<AdminRagTestConsole> createState() => _AdminRagTestConsoleState();
}

class _AdminRagTestConsoleState extends State<AdminRagTestConsole> {
  late final _question = TextEditingController(text: widget.initialQuestion);
  late ContentIndexSelection _index = ContentIndexSelection(
    examId: widget.initialExamId.isNotEmpty
        ? widget.initialExamId
        : kDefaultExamId,
    subjectId: widget.initialSubjectId,
    chapterId: widget.initialChapterId,
    topicId: widget.initialTopicId,
  );
  final Set<RagDomain> _domains = {};
  String _studentUid = '';
  bool _busy = false;
  String? _error;
  MultiRagResult? _result;
  MultiRagAnswer? _answer;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _retrieve() async {
    final q = _question.text.trim();
    if (q.isEmpty) {
      showAdminMessage(context, 'Enter a question first.');
      return;
    }
    if (_domains.contains(RagDomain.studentPerformance) &&
        _studentUid.trim().isEmpty) {
      showAdminMessage(
        context,
        'Student Performance is skipped until you select a student.',
      );
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var performance = const <StudentPerformanceRecord>[];
      if (adminRagTestAllowsStudentPerformance(
        domains: _domains.toList(),
        studentUid: _studentUid,
      )) {
        final snap = await aiWeaknessTracker.load(_studentUid);
        performance = [
          for (final signal in snap.signals)
            StudentPerformanceRecord(
              label: signal.label,
              subjectId: signal.subjectId,
              chapterId: signal.chapterId,
              scorePercent: signal.scorePercent,
              source: signal.source,
              status: signal.isWeak
                  ? 'weak'
                  : (signal.isStrong ? 'strong' : ''),
            ),
        ];
      }
      final query = buildAdminRagTestQuery(
        question: q,
        examId: _index.examId,
        subjectId: _index.subjectId,
        chapterId: _index.chapterId,
        topicId: _index.topicId,
        domains: _domains.toList(),
        studentUid: _studentUid,
        performance: performance,
      );
      final retrieved = await multiRagRetrievalService.retrieve(query);
      final answer = await multiRagAnswerService.answer(
        query,
        subjectHint: _index.subjectTitle,
      );
      if (!mounted) return;
      setState(() {
        _result = retrieved;
        _answer = answer;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = null;
        _answer = null;
        _error = RagException.fromError(e).message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final includePerformance = _domains.contains(RagDomain.studentPerformance);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminSectionLabel(label: 'RAG Test Console'),
        const Text(
          'Uses the existing Multi-RAG engine. Student Performance is never '
          'loaded unless you select that domain and a student.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _question,
          decoration: const InputDecoration(
            hintText: 'Question…',
          ),
          minLines: 2,
          maxLines: 4,
        ),
        const SizedBox(height: 12),
        ContentIndexPicker(
          initial: _index,
          onChanged: (next) => setState(() => _index = next),
        ),
        const SizedBox(height: 8),
        const Text(
          'RAG domains',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final domain in RagDomain.values)
              FilterChip(
                label: Text(ragDomainLabel(domain)),
                selected: _domains.contains(domain),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _domains.add(domain);
                    } else {
                      _domains.remove(domain);
                      if (domain == RagDomain.studentPerformance) {
                        _studentUid = '';
                      }
                    }
                  });
                },
              ),
          ],
        ),
        if (includePerformance) ...[
          const SizedBox(height: 12),
          StreamBuilder<List<StudentProfile>>(
            stream: profileRepository.watchAllStudents(),
            builder: (context, snapshot) {
              final students = snapshot.data ?? const <StudentProfile>[];
              return DropdownButtonFormField<String>(
                key: ValueKey('$_studentUid-${students.length}'),
                initialValue: students.any((s) => s.uid == _studentUid)
                    ? _studentUid
                    : '',
                decoration: const InputDecoration(
                  labelText: 'Student (required for Student Performance)',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('No student — skip private data'),
                  ),
                  for (final student in students)
                    DropdownMenuItem(
                      value: student.uid,
                      child: Text(
                        student.name.trim().isNotEmpty
                            ? student.name
                            : student.uid,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _studentUid = v ?? ''),
              );
            },
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _retrieve,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search_rounded),
          label: Text(_busy ? 'Retrieving…' : 'Retrieve'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: Colors.red.shade700)),
        ],
        if (_result != null) ...[
          const SizedBox(height: 16),
          Text(
            'Overall confidence ${(_result!.confidence * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (_result!.hits.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'No chunks retrieved for this question and filters.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          for (final hit in _result!.hits)
            Card(
              margin: const EdgeInsets.only(top: 10),
              child: ListTile(
                title: Text(
                  hit.chunk.sourceTitle.isNotEmpty
                      ? hit.chunk.sourceTitle
                      : hit.sourceRef.documentRef,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    ragDomainLabel(hit.domain),
                    'confidence ${(hit.confidence * 100).toStringAsFixed(0)}%',
                    if (hit.sourceRef.documentRef.isNotEmpty)
                      hit.sourceRef.documentRef,
                    hit.chunk.text,
                  ].join(' · '),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
        if (_answer != null) ...[
          const SizedBox(height: 16),
          const Text(
            'Generated answer',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          SelectableText(
            _answer!.insufficient
                ? (_answer!.markdown.isNotEmpty
                    ? _answer!.markdown
                    : 'Insufficient evidence in the selected sources.')
                : _answer!.markdown,
          ),
        ],
      ],
    );
  }
}
