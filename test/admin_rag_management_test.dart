import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/multi_rag_result.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_management.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_processing_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';

List<double> _fakeEmbed(String text) {
  final v = List<double>.filled(kRagEmbeddingDimensions, 0);
  final tokens = ragKeywordTokens(text, limit: 80);
  if (tokens.isEmpty) {
    v[0] = 1;
    return v;
  }
  for (final token in tokens) {
    final h = token.hashCode.abs();
    v[h % kRagEmbeddingDimensions] += 1;
  }
  var norm = 0.0;
  for (final n in v) {
    norm += n * n;
  }
  norm = math.sqrt(norm);
  if (norm == 0) return v;
  return [for (final n in v) n / norm];
}

class _FakeBackend extends RagBackendClient {
  _FakeBackend() : super(baseUrl: 'http://rag.test');

  @override
  Future<List<List<double>>> embed({
    required List<String> texts,
    String task = 'document',
  }) async {
    return [for (final t in texts) _fakeEmbed(t)];
  }
}

RagSource _source({
  required String id,
  RagSourceStatus status = RagSourceStatus.ready,
  bool needsReindex = false,
  String examId = kDefaultExamId,
  String subjectId = 'pol',
  String chapterId = 'fr',
  String topicId = 'a14',
  String contentType = kNotesPdfContentType,
  String ragDomain = '',
  String title = 'Fundamental Rights',
  String fileUrl = '',
  RagSourceType sourceType = RagSourceType.notes,
  String linkedId = 'note-1',
  int chunkCount = 3,
  String exam = kMpscDefaultExam,
}) {
  return RagSource(
    id: id,
    title: title,
    subject: 'Polity',
    chapter: 'Fundamental Rights',
    exam: exam,
    fileUrl: fileUrl,
    uploadedBy: 'admin',
    createdAt: DateTime(2026, 8, 1),
    updatedAt: DateTime(2026, 8, 20, 10, 15),
    status: status,
    published: status == RagSourceStatus.ready,
    sourceType: sourceType,
    examId: examId,
    subjectId: subjectId,
    chapterId: chapterId,
    topicId: topicId,
    contentType: contentType,
    ragDomain: ragDomain,
    needsReindex: needsReindex,
    linkedId: linkedId,
    chunkCount: chunkCount,
  );
}

void main() {
  test('admin statuses map Draft / Processing / Ready / Failed / Needs Re-index', () {
    expect(
      ragManagementStatus(_source(id: 'd', status: RagSourceStatus.uploading)),
      RagManagementStatus.draft,
    );
    expect(
      ragManagementStatus(_source(id: 'p', status: RagSourceStatus.processing)),
      RagManagementStatus.processing,
    );
    expect(
      ragManagementStatus(_source(id: 'r')),
      RagManagementStatus.ready,
    );
    expect(
      ragManagementStatus(_source(id: 'f', status: RagSourceStatus.failed)),
      RagManagementStatus.failed,
    );
    expect(
      ragManagementStatus(_source(id: 'n', needsReindex: true)),
      RagManagementStatus.needsReindex,
    );
    expect(
      ragManagementStatusToString(RagManagementStatus.needsReindex),
      'Needs Re-index',
    );
  });

  test('embedding status follows management lifecycle', () {
    expect(
      ragEmbeddingStatus(_source(id: 'd', status: RagSourceStatus.uploading)),
      RagEmbeddingStatus.pending,
    );
    expect(
      ragEmbeddingStatus(_source(id: 'p', status: RagSourceStatus.processing)),
      RagEmbeddingStatus.processing,
    );
    expect(ragEmbeddingStatus(_source(id: 'r')), RagEmbeddingStatus.embedded);
    expect(
      ragEmbeddingStatus(_source(id: 'stale', chunkCount: 0)),
      RagEmbeddingStatus.stale,
    );
    expect(
      ragEmbeddingStatus(_source(id: 'n', needsReindex: true)),
      RagEmbeddingStatus.stale,
    );
    expect(
      ragEmbeddingStatus(_source(id: 'f', status: RagSourceStatus.failed)),
      RagEmbeddingStatus.failed,
    );
  });

  test('index is blocked until Content Index metadata is valid', () {
    final missingTitle = _source(id: 'x', title: '');
    expect(ragMetadataIsIndexable(missingTitle), isFalse);
    expect(ragIndexMetadataIssues(missingTitle).first.field, 'title');

    final missingExam = _source(id: 'e', examId: '', exam: '');
    expect(
      ragIndexMetadataIssues(missingExam).any((i) => i.field == 'examId'),
      isTrue,
    );

    final pdf = _source(
      id: 'pdf',
      sourceType: RagSourceType.pdf,
      fileUrl: '',
      linkedId: '',
    );
    expect(
      ragIndexMetadataIssues(pdf).any((i) => i.field == 'fileUrl'),
      isTrue,
    );

    final notes = _source(id: 'ok');
    expect(ragMetadataIsIndexable(notes), isTrue);
  });

  test('admin filters by exam, domain, draft, and needs-reindex', () {
    final notes = _source(id: 'n1', ragDomain: ragDomainToString(RagDomain.notes));
    final pyq = _source(
      id: 'p1',
      contentType: kPyqContentType,
      ragDomain: ragDomainToString(RagDomain.pyq),
      sourceType: RagSourceType.pyq,
    );
    final stale = _source(id: 'n2', needsReindex: true);
    final draft = _source(id: 'd1', status: RagSourceStatus.uploading);

    expect(matchesRagAdminFilters(notes, domain: RagDomain.notes), isTrue);
    expect(matchesRagAdminFilters(notes, domain: RagDomain.pyq), isFalse);
    expect(matchesRagAdminFilters(pyq, domain: RagDomain.pyq), isTrue);
    expect(matchesRagAdminFilters(notes, examId: kDefaultExamId), isTrue);
    expect(matchesRagAdminFilters(notes, examId: 'other'), isFalse);
    expect(
      matchesRagAdminFilters(stale, status: RagAdminStatusFilter.indexed),
      isFalse,
    );
    expect(
      matchesRagAdminFilters(stale, status: RagAdminStatusFilter.needsReindex),
      isTrue,
    );
    expect(
      matchesRagAdminFilters(draft, status: RagAdminStatusFilter.draft),
      isTrue,
    );
  });

  test('needsReindex round-trips on ragSources maps', () {
    final source = _source(id: 'n', needsReindex: true);
    final copy = RagSource.fromMap(source.toMap(), source.id);
    expect(copy.needsReindex, isTrue);
    expect(ragManagementStatus(copy), RagManagementStatus.needsReindex);
  });

  test('existing Indexed/Processing/Failed stats still count pipeline status', () {
    final sources = [
      _source(id: 'ready-1'),
      _source(id: 'ready-2'),
      _source(id: 'proc', status: RagSourceStatus.processing),
      _source(id: 'up', status: RagSourceStatus.uploading),
      _source(id: 'fail', status: RagSourceStatus.failed),
    ];
    final stats = ragAdminMonitorStats(sources);
    expect(stats.total, 5);
    expect(stats.indexed, 2);
    expect(stats.processing, 2);
    expect(stats.failed, 1);
  });

  test('admin RAG test query omits student performance without a student uid', () {
    final stripped = buildAdminRagTestQuery(
      question: 'My weak topics in Polity',
      examId: kDefaultExamId,
      subjectId: 'pol',
      domains: [RagDomain.studentPerformance, RagDomain.notes],
      studentUid: '',
      performance: const [
        StudentPerformanceRecord(label: 'secret weak topic', scorePercent: 20),
      ],
    );
    expect(stripped.domains, [RagDomain.notes]);
    expect(stripped.performance, isEmpty);
    expect(
      adminRagTestAllowsStudentPerformance(
        domains: [RagDomain.studentPerformance],
        studentUid: '',
      ),
      isFalse,
    );
  });

  test('admin RAG test query includes student performance only with explicit student', () {
    const rows = [
      StudentPerformanceRecord(label: 'Article 14', scorePercent: 18),
    ];
    final query = buildAdminRagTestQuery(
      question: 'My weak topics',
      domains: [RagDomain.studentPerformance, RagDomain.notes],
      studentUid: 'student-1',
      performance: rows,
    );
    expect(query.domains, [RagDomain.studentPerformance, RagDomain.notes]);
    expect(query.performance, rows);
    expect(
      adminRagTestAllowsStudentPerformance(
        domains: [RagDomain.studentPerformance],
        studentUid: 'student-1',
      ),
      isTrue,
    );
  });

  test('supported admin domains cover Notes PYQ Syllabus CA AI Teacher Performance', () {
    expect(
      RagDomain.values.map(ragDomainLabel).toList(),
      [
        'Notes',
        'PYQs',
        'Syllabus',
        'Current Affairs',
        'AI Teacher',
        'Student Performance',
      ],
    );
  });

  test('Remove from RAG keeps the source as Draft and deletes chunks', () async {
    final firestore = FakeFirebaseFirestore();
    final sources = RagSourceRepository(firestore: firestore);
    final chunks = RagChunkRepository(firestore: firestore);
    final processing = RagProcessingService(
      sources: sources,
      chunks: chunks,
      backend: _FakeBackend(),
      firestore: firestore,
      notes: NotesRepository(firestore: firestore),
      pyqs: PyqRepository(firestore: firestore),
      currentAffairs: CurrentAffairsRepository(firestore: firestore),
    );
    await sources.create(
      _source(
        id: 's-remove',
        status: RagSourceStatus.processing,
        sourceType: RagSourceType.text,
        linkedId: 's-remove',
        contentType: 'notes',
      ),
    );
    final ready = await processing.processSource(
      's-remove',
      inlineText: 'संसद ही भारतीय संविधानातील केंद्रीय विधिमंडळ आहे. ' * 8,
    );
    expect(ready.status, RagSourceStatus.ready);
    expect(await chunks.getForSource('s-remove'), isNotEmpty);

    await processing.removeFromRag(ready);
    final leftover = await sources.get('s-remove');
    expect(leftover, isNotNull);
    expect(leftover!.status, RagSourceStatus.uploading);
    expect(ragManagementStatus(leftover), RagManagementStatus.draft);
    expect(leftover.published, isFalse);
    expect(leftover.chunkCount, 0);
    expect(await chunks.getForSource('s-remove'), isEmpty);
  });

  test('successful index clears needsReindex', () async {
    final firestore = FakeFirebaseFirestore();
    final sources = RagSourceRepository(firestore: firestore);
    final chunks = RagChunkRepository(firestore: firestore);
    final processing = RagProcessingService(
      sources: sources,
      chunks: chunks,
      backend: _FakeBackend(),
      firestore: firestore,
      notes: NotesRepository(firestore: firestore),
      pyqs: PyqRepository(firestore: firestore),
      currentAffairs: CurrentAffairsRepository(firestore: firestore),
    );
    await sources.create(
      _source(
        id: 's-reindex',
        status: RagSourceStatus.processing,
        needsReindex: true,
        sourceType: RagSourceType.text,
        linkedId: 's-reindex',
        contentType: 'notes',
      ),
    );
    final ready = await processing.processSource(
      's-reindex',
      inlineText: 'Fundamental Rights under Articles 12 to 35 of the Constitution. ' * 6,
    );
    expect(ready.needsReindex, isFalse);
    expect(ragManagementStatus(ready), RagManagementStatus.ready);
  });
}
