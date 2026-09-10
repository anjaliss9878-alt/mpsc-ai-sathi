import 'dart:io';
import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/models/study_content_pack.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_grounded_learning_service.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';
import 'package:mpsc_combine_ai/services/study_content_session_service.dart';
import 'package:mpsc_combine_ai/services/study_pack_repository.dart';

List<double> _embed(String text) {
  final v = List<double>.filled(kRagEmbeddingDimensions, 0);
  v[0] = 1;
  final h = text.hashCode.abs();
  v[h % kRagEmbeddingDimensions] = 1;
  var n = 0.0;
  for (final x in v) {
    n += x * x;
  }
  n = math.sqrt(n);
  return [for (final x in v) x / n];
}

class _StubRetrieve extends RagRetrievalService {
  _StubRetrieve(
    this.hits, {
    required FakeFirebaseFirestore firestore,
    RagBackendClient? backend,
  }) : super(
          sources: RagSourceRepository(firestore: firestore),
          chunks: RagChunkRepository(firestore: firestore),
          backend: backend ?? RagBackendClient(baseUrl: 'http://rag.test'),
          firestore: firestore,
          serverFirst: false,
          embedQuery: (q) async => _embed(q),
        );

  List<RagHit> hits;
  int retrieveCalls = 0;

  @override
  Future<List<RagHit>> retrieve({
    required String query,
    RagSourceFilter filter = RagSourceFilter.allPublished,
    List<double>? queryEmbedding,
  }) async {
    retrieveCalls++;
    expect(filter.onlyPublishedReady, isTrue);
    return hits;
  }
}

class _RetryRetrieve extends RagRetrievalService {
  _RetryRetrieve({
    required this.scoped,
    required this.fallback,
    required FakeFirebaseFirestore firestore,
    RagBackendClient? backend,
  }) : super(
          sources: RagSourceRepository(firestore: firestore),
          chunks: RagChunkRepository(firestore: firestore),
          backend: backend ?? RagBackendClient(baseUrl: 'http://rag.test'),
          firestore: firestore,
          serverFirst: false,
          embedQuery: (q) async => _embed(q),
        );

  final List<RagHit> scoped;
  final List<RagHit> fallback;
  int retrieveCalls = 0;

  @override
  Future<List<RagHit>> retrieve({
    required String query,
    RagSourceFilter filter = RagSourceFilter.allPublished,
    List<double>? queryEmbedding,
  }) async {
    retrieveCalls++;
    expect(filter.onlyPublishedReady, isTrue);
    if (filter.chapterId.isNotEmpty || filter.subjectId.isNotEmpty) {
      return scoped;
    }
    return fallback;
  }
}

class _LearnBackend extends RagBackendClient {
  _LearnBackend() : super(baseUrl: 'http://rag.test');

  int learnCalls = 0;
  final modes = <String>[];

  @override
  Future<Map<String, dynamic>> learn(Map<String, dynamic> body) async {
    learnCalls++;
    modes.add('${body['mode']}');
    final chunks = (body['chunks'] as List?) ?? const [];
    if (chunks.isEmpty) return {'insufficient': true};
    switch ('${body['mode']}') {
      case 'summary':
        return {
          'insufficient': false,
          'detailed': 'Article 14 exam notes from approved PDF.',
          'shortNotes': 'Equality before law.',
          'fiveMinuteRevision': 'Revise Art 14.',
          'importantFacts': ['Article 14'],
          'examPoints': ['MPSC favourite'],
          'commonMistakes': ['Confusing 14 and 15'],
          'chunkIndexes': [0],
        };
      case 'mcq':
        return {
          'insufficient': false,
          'questions': [
            {
              'question': 'Article 14 is about?',
              'options': ['Equality', 'Property', 'Vote', 'Tax'],
              'correctIndex': 0,
              'explanation': 'From the approved chunk.',
              'difficulty': 'Easy',
              'topic': 'FR',
              'chunkIndexes': [0],
            },
          ],
        };
      case 'revision':
        return {
          'insufficient': false,
          'keyFacts': ['Article 14'],
          'terms': ['Equality'],
          'dates': <String>[],
          'articles': ['14'],
          'committees': <String>[],
          'personalities': <String>[],
          'examTraps': ['14 vs 15'],
          'chunkIndexes': [0],
        };
      default:
        return {
          'insufficient': false,
          'answer': 'Explanation from approved chunk only.',
          'chunkIndexes': [0],
        };
    }
  }
}

RagHit _hit() {
  return RagHit(
    chunk: RagChunk(
      id: 'c1',
      sourceId: 's1',
      sourceTitle: 'Laxmikanth',
      subject: 'Polity',
      chapter: 'FR',
      text: 'Article 14 equality before law.',
      embedding: _embed('article 14'),
      language: 'en',
      sourceType: 'pdf',
      published: true,
      pageNumber: 12,
    ),
    score: 0.9,
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late NotesRepository notes;
  late StudyPackRepository packs;
  late _LearnBackend backend;
  late RagGroundedLearningService grounded;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    notes = NotesRepository(firestore: firestore);
    packs = StudyPackRepository(firestore: firestore);
    backend = _LearnBackend();
    grounded = RagGroundedLearningService(
      retrieval: _StubRetrieve(const [], firestore: firestore, backend: backend),
      backend: backend,
      loadPublishedPyqs: () async => [
        PyqItem(
          id: 'p1',
          title: 'Equality PYQ',
          subtitle: '2019',
          fileUrl: '',
          order: 1,
          question: 'Which article guarantees equality before law?',
          options: const ['14', '15', '16', '19'],
          correctIndex: 0,
          answer: '14',
          explanation: 'Official paper',
          year: 2019,
          examName: 'MPSC PSI',
          published: true,
          status: NoteWorkflowStatus.published,
          subject: 'Polity',
        ),
      ],
    );
  });

  test('no published hits → insufficient and no Gemini learn call', () async {
    final service = StudyContentSessionService(
      retrieval: _StubRetrieve(const [], firestore: firestore, backend: backend),
      grounded: grounded,
      packs: packs,
      notes: notes,
    );
    final session = await service.open(topic: 'Quantum gravity');
    expect(session.insufficient, isTrue);
    expect(session.notes.detailed, kStudyContentInsufficient);
    expect(backend.learnCalls, 0);
  });

  test('empty chapter-scoped retrieve retries all published+Ready sources', () async {
    final retrieval = _RetryRetrieve(
      scoped: const [],
      fallback: [_hit()],
      firestore: firestore,
      backend: backend,
    );
    final service = StudyContentSessionService(
      retrieval: retrieval,
      grounded: grounded,
      packs: packs,
      notes: notes,
    );
    final session = await service.open(
      topic: 'Fundamental Rights',
      subjectId: 'mpsc_group_b_prelims_general_ability_test',
      chapterId: 'new-group-b-chapter',
    );
    expect(session.insufficient, isFalse);
    expect(retrieval.retrieveCalls, 2);
    expect(backend.learnCalls, 1);
  });

  test('published hits generate notes then reuse hits for MCQ / PYQ / revision',
      () async {
    final retrieval = _StubRetrieve(
      [_hit()],
      firestore: firestore,
      backend: backend,
    );
    final service = StudyContentSessionService(
      retrieval: retrieval,
      grounded: grounded,
      packs: packs,
      notes: notes,
    );
    final session = await service.open(topic: 'Article 14');
    expect(session.insufficient, isFalse);
    expect(session.notes.detailed, contains('approved PDF'));
    expect(backend.learnCalls, 1);

    final mcqs = await service.loadMcqs(session);
    expect(mcqs, hasLength(1));
    await service.loadMcqs(session);
    expect(backend.modes.where((m) => m == 'mcq'), hasLength(1));

    final pyqs = await service.loadPyqs(session);
    expect(pyqs, isNotEmpty);
    expect(pyqs.first.question, contains('equality'));
    expect(backend.modes.contains('pyq'), isFalse);

    final revision = await service.loadRevision(session);
    expect(revision.keyFacts, contains('Article 14'));
    expect(retrieval.retrieveCalls, 1);
  });

  test('admin save pack writes unpublished notes draft only', () async {
    final service = StudyContentSessionService(
      retrieval: _StubRetrieve(
        [_hit()],
        firestore: firestore,
        backend: backend,
      ),
      grounded: grounded,
      packs: packs,
      notes: notes,
    );
    final packId = await packs.submit(
      StudyContentPack(
        id: '',
        uid: 'student1',
        topic: 'Article 14',
        detailedNotes: 'Draft notes from RAG.',
        importantFacts: const ['Art 14'],
        examPoints: const ['MPSC'],
        citations: const [
          RagCitation(
            sourceId: 's1',
            subject: 'Polity',
            chapter: 'FR',
            topic: 'Equality',
            pageNumber: 12,
          ),
        ],
        status: StudyPackReviewStatus.pendingReview,
        published: true,
        createdAt: DateTime(2026, 9, 2),
      ),
    );
    final stored = StudyContentPack.fromMap(
      (await firestore.collection('studyPacks').doc(packId).get()).data()!,
      packId,
    );
    expect(stored.published, isFalse);

    final noteId = await service.savePackAsNotesDraft(stored);
    final note = await notes.getNote(noteId);
    expect(note, isNotNull);
    expect(note!.published, isFalse);
    expect(note.status, NoteWorkflowStatus.aiGenerated);
    expect(note.isStudentVisible, isFalse);
    expect(note.tags, contains('ai-generated'));
    expect(note.contentMarkdown, contains('Draft notes from RAG.'));
  });

  test('firestore.rules gate studyPacks like ai_lessons and keep published false',
      () {
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules, contains('match /studyPacks/{packId}'));
    expect(rules, contains('request.resource.data.published != true'));
  });
}
