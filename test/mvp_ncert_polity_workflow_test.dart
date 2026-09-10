import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_grounded_learning_service.dart';
import 'package:mpsc_combine_ai/services/rag_processing_service.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';
import 'package:mpsc_combine_ai/services/study_pack_repository.dart';
import 'package:mpsc_combine_ai/services/study_content_session_service.dart';

List<double> _embed(String text) {
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
  var n = 0.0;
  for (final x in v) {
    n += x * x;
  }
  n = math.sqrt(n);
  return [for (final x in v) x / n];
}

class _NcertBackend extends RagBackendClient {
  _NcertBackend() : super(baseUrl: 'http://rag.test');

  int extractCalls = 0;
  int embedCalls = 0;
  int learnCalls = 0;
  final modes = <String>[];

  static const ncertText =
      'The Constitution of India was framed by the Constituent Assembly. '
      'Dr. B.R. Ambedkar was the Chairman of the Drafting Committee. '
      'The Constitution was adopted on 26 November 1949.';

  @override
  Future<List<RagExtractedPage>> extractPdf({
    required String fileUrl,
    String title = '',
  }) async {
    extractCalls++;
    return [const RagExtractedPage(pageNumber: 1, text: ncertText)];
  }

  @override
  Future<List<List<double>>> embed({
    required List<String> texts,
    String task = 'document',
  }) async {
    embedCalls++;
    return [for (final t in texts) _embed(t)];
  }

  @override
  Future<List<double>> embedQuery(String query) async => _embed(query);

  @override
  Future<Map<String, dynamic>> learn(Map<String, dynamic> body) async {
    learnCalls++;
    modes.add('${body['mode']}');
    final chunks = (body['chunks'] as List?) ?? const [];
    if (chunks.isEmpty) return {'insufficient': true};
    switch ('${body['mode']}') {
      case 'summary':
        return {
          'detailed': 'Exam notes: Constituent Assembly framed the Constitution.',
          'shortNotes': 'Ambedkar chaired the Drafting Committee.',
          'fiveMinuteRevision': 'Adopted 26 November 1949.',
        };
      case 'mcq':
        return {
          'questions': [
            {
              'question': 'Who chaired the Drafting Committee?',
              'options': ['Ambedkar', 'Nehru', 'Patel', 'Prasad'],
              'correctIndex': 0,
              'explanation': 'NCERT Political Science',
            },
          ],
        };
      case 'answer':
        return {
          'answer': 'The Constituent Assembly framed the Constitution.',
          'insufficient': false,
        };
      case 'revision':
        return {
          'points': ['Constituent Assembly', 'Drafting Committee', '26 Nov 1949'],
        };
      default:
        return {'ok': true};
    }
  }
}

RagSource _ncert({required bool published}) {
  return RagSource(
    id: 'ncert_polity',
    title: 'NCERT Political Science',
    subject: 'Political Science',
    subjectId: 'pol',
    chapter: 'Constitution',
    chapterId: 'const',
    topicId: '',
    exam: kMpscDefaultExam,
    examId: kDefaultExamId,
    fileUrl: 'https://example.test/ncert-polity.pdf',
    uploadedBy: 'admin',
    createdAt: DateTime(2026, 9, 1),
    status: RagSourceStatus.uploading,
    published: published,
    sourceType: RagSourceType.pdf,
    ragDomain: 'notes_rag',
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late RagSourceRepository sources;
  late RagChunkRepository chunks;
  late PyqRepository pyqs;
  late NotesRepository notes;
  late _NcertBackend backend;
  late RagProcessingService processing;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    sources = RagSourceRepository(firestore: firestore);
    chunks = RagChunkRepository(firestore: firestore);
    pyqs = PyqRepository(firestore: firestore);
    notes = NotesRepository(firestore: firestore);
    backend = _NcertBackend();
    processing = RagProcessingService(
      sources: sources,
      chunks: chunks,
      backend: backend,
      firestore: firestore,
      notes: notes,
      pyqs: pyqs,
      currentAffairs: CurrentAffairsRepository(firestore: firestore),
    );
  });

  test('MVP 1-8 NCERT Political Science: upload extract chunk embed retrieve grounded notes MCQ',
      () async {
    await sources.create(_ncert(published: false));

    // 1 + 2 + 3 + 4
    final ready = await processing.processSource('ncert_polity');
    expect(ready.status, RagSourceStatus.ready);
    expect(backend.extractCalls, greaterThan(0));
    final indexed = await chunks.getForSource('ncert_polity');
    expect(indexed, isNotEmpty);
    expect(indexed.every((c) => c.embedding.length == kRagEmbeddingDimensions), isTrue);
    expect(backend.embedCalls, greaterThan(0));

    // Student cannot retrieve unpublished Ready source.
    final retrieval = RagRetrievalService(
      sources: sources,
      chunks: chunks,
      backend: backend,
      embedQuery: (q) async => _embed(q),
    );
    var studentHits = await retrieval.retrieve(
      query: 'How was the Constitution made?',
      filter: const RagSourceFilter(
        onlyPublishedReady: true,
        subjectId: 'pol',
        chapterId: 'const',
        topicId: 'making',
        scope: RagSourceScope.subjectChapter,
        hybrid: false,
        similarityThreshold: 0.01,
      ),
    );
    expect(studentHits, isEmpty);

    await processing.setPublished(ready, true);

    // 5
    studentHits = await retrieval.retrieve(
      query: 'How was the Constitution made?',
      filter: const RagSourceFilter(
        onlyPublishedReady: true,
        subjectId: 'pol',
        chapterId: 'const',
        topicId: 'making',
        scope: RagSourceScope.subjectChapter,
        hybrid: false,
        similarityThreshold: 0.01,
      ),
    );
    expect(studentHits, isNotEmpty);
    expect(studentHits.first.chunk.sourceTitle, 'NCERT Political Science');

    final grounded = RagGroundedLearningService(
      retrieval: retrieval,
      backend: backend,
    );
    // 6
    final answer = await grounded.answer(
      question: 'How was the Indian Constitution made?',
      prefetchedHits: studentHits,
    );
    expect(answer.markdown.toLowerCase(), contains('constituent'));
    expect(backend.modes.contains('answer'), isTrue);

    final sessionService = StudyContentSessionService(
      retrieval: retrieval,
      grounded: grounded,
      notes: notes,
      packs: StudyPackRepository(firestore: firestore),
    );
    // 7 + 12 after publish
    final session = await sessionService.open(
      topic: 'Indian Constitution making',
      subjectTitle: 'Political Science',
      subjectId: 'pol',
      chapterId: 'const',
      topicId: 'making',
    );
    expect(session.insufficient, isFalse);
    expect(session.notes.detailed, isNot(kStudyContentInsufficient));

    // 8
    final mcqs = await sessionService.loadMcqs(session);
    expect(mcqs, isNotEmpty);
    expect(mcqs.first.question, contains('Drafting'));
  });

  test('MVP 9-12 PYQ extract mapping admin approval student visibility', () async {
    const officialQ = 'Who was the Chairman of the Drafting Committee?';
    const officialA = 'Dr. B.R. Ambedkar';
    final id = await pyqs.add(
      PyqItem(
        id: '',
        title: 'NCERT-linked PYQ',
        subtitle: '2019',
        fileUrl: '',
        order: 1,
        question: officialQ,
        answer: officialA,
        options: const ['Ambedkar', 'Nehru', 'Patel', 'Prasad'],
        correctIndex: 0,
        subjectId: 'pol',
        chapterId: 'const',
        topicId: 'making',
        subject: 'Political Science',
        status: NoteWorkflowStatus.draft,
        published: false,
        year: 2019,
      ),
    );
    final draft = (await firestore.collection('pyqs').doc(id).get()).data()!;
    final item = PyqItem.fromMap(draft, id);

    // 9 extraction text for RAG/indexing (does not rewrite official fields)
    expect(item.searchableText, contains(officialQ));
    expect(item.searchableText, contains(officialA));

    // 10 mapping
    expect(item.subjectId, 'pol');
    expect(item.chapterId, 'const');
    expect(item.topicId, 'making');

    // 11 admin approval without changing official text
    await pyqs.updateWorkflow(id, NoteWorkflowStatus.approved);
    await pyqs.updateWorkflow(id, NoteWorkflowStatus.published);
    final published = PyqItem.fromMap(
      (await firestore.collection('pyqs').doc(id).get()).data()!,
      id,
    );
    expect(published.question, officialQ);
    expect(published.answer, officialA);
    expect(published.status, NoteWorkflowStatus.published);
    expect(published.isStudentVisible, isTrue);

    // 12 students never see draft/under review
    final hiddenId = await pyqs.add(
      const PyqItem(
        id: '',
        title: 'Hidden',
        subtitle: '',
        fileUrl: '',
        order: 2,
        question: officialQ,
        answer: officialA,
        status: NoteWorkflowStatus.underReview,
        published: false,
      ),
    );
    final visible = await pyqs.watchPublished().first;
    expect(visible.map((p) => p.id), [id]);
    expect(visible.any((p) => p.id == hiddenId), isFalse);

    final draftNote = NoteItem(
      id: 'n1',
      subjectId: 'pol',
      chapterId: 'const',
      title: 'Draft notes',
      importantPoints: const ['secret'],
      revisionSummary: const ['secret'],
      status: NoteWorkflowStatus.aiGenerated,
      published: false,
    );
    expect(draftNote.isStudentVisible, isFalse);
    expect(
      NoteItem(
        id: 'n2',
        subjectId: 'pol',
        chapterId: 'const',
        title: 'Live',
        importantPoints: const ['ok'],
        revisionSummary: const ['ok'],
        status: NoteWorkflowStatus.published,
        published: true,
      ).isStudentVisible,
      isTrue,
    );
  });

  test('empty published RAG shows the exact student insufficient line', () async {
    final retrieval = RagRetrievalService(
      sources: sources,
      chunks: chunks,
      backend: backend,
      embedQuery: (q) async => _embed(q),
    );
    final session = await StudyContentSessionService(
      retrieval: retrieval,
      grounded: RagGroundedLearningService(
        retrieval: retrieval,
        backend: backend,
      ),
      notes: notes,
      packs: StudyPackRepository(firestore: firestore),
    ).open(topic: 'Quantum gravity');
    expect(session.insufficient, isTrue);
    expect(
      session.notes.detailed,
      kStudyContentInsufficient,
    );
    expect(backend.learnCalls, 0);
  });
}
