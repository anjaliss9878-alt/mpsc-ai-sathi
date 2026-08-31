import 'dart:io';
import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_processing_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';

String _ruleBlock(String rules, String matchLine) {
  final start = rules.indexOf(matchLine);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $matchLine');
  final from = start + matchLine.length;
  final next = rules.indexOf('\n    match /', from);
  return rules.substring(start, next < 0 ? rules.length : next);
}

/// Mirrors firestore.rules `isStudentReadableRagSource`.
bool studentCanReadSource({
  required bool signedIn,
  required bool admin,
  required Map<String, dynamic> data,
}) {
  if (admin) return true;
  return signedIn && data['published'] == true && data['status'] == 'Ready';
}

/// Mirrors firestore.rules `isStudentReadableRagChunk`.
bool studentCanReadChunk({
  required bool signedIn,
  required bool admin,
  required Map<String, dynamic> chunk,
  required Map<String, dynamic>? source,
}) {
  if (admin) return true;
  if (!signedIn) return false;
  if (chunk['published'] != true) return false;
  final sourceId = chunk['sourceId'];
  if (sourceId is! String || sourceId.isEmpty || source == null) return false;
  return source['published'] == true && source['status'] == 'Ready';
}

/// A `where published == true` list fails closed if any matching doc is denied.
bool studentPublishedQueryAllowed(List<bool> perDocReadable) {
  if (perDocReadable.isEmpty) return true;
  return perDocReadable.every((ok) => ok);
}

RagSource _source({
  required String id,
  RagSourceStatus status = RagSourceStatus.ready,
  bool published = true,
  String contentStatus = '',
}) {
  return RagSource(
    id: id,
    title: id,
    subject: 'Polity',
    chapter: 'FR',
    exam: kMpscDefaultExam,
    fileUrl: '',
    uploadedBy: 'admin1',
    createdAt: DateTime(2026, 1, 1),
    status: status,
    published: published,
    contentStatus: contentStatus,
    examId: kDefaultExamId,
    subjectId: 'pol',
    chapterId: 'fr',
  );
}

List<double> _embed(String text) {
  final v = List<double>.filled(kRagEmbeddingDimensions, 0);
  final tokens = ragKeywordTokens(text, limit: 40);
  if (tokens.isEmpty) {
    v[0] = 1;
    return v;
  }
  for (final token in tokens) {
    v[token.hashCode.abs() % kRagEmbeddingDimensions] += 1;
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
  _FakeBackend({this.failEmbed = false}) : super(baseUrl: 'http://rag.test');

  final bool failEmbed;

  @override
  Future<List<List<double>>> embed({
    required List<String> texts,
    String task = 'document',
  }) async {
    if (failEmbed) throw StateError('embed down');
    return [for (final t in texts) _embed(t)];
  }
}

void main() {
  late String rules;

  setUpAll(() {
    rules = File('firestore.rules').readAsStringSync();
  });

  test('rules file no longer allows any signed-in student to read all RAG', () {
    final sources = _ruleBlock(rules, 'match /ragSources/{sourceId}');
    final chunks = _ruleBlock(rules, 'match /ragChunks/{chunkId}');
    expect(sources, contains('allow read: if isAdmin() || isStudentReadableRagSource();'));
    expect(sources, contains('allow write: if isAdmin();'));
    expect(sources, isNot(contains('allow read: if isSignedIn();')));
    expect(chunks, contains('allow read: if isAdmin() || isStudentReadableRagChunk();'));
    expect(chunks, contains('allow write: if isAdmin();'));
    expect(chunks, isNot(contains('allow read: if isSignedIn();')));
    expect(rules, contains('function isStudentReadableRagSource()'));
    expect(rules, contains('function isStudentReadableRagChunk()'));
    expect(rules, contains("resource.data.status == 'Ready'"));
    expect(rules, contains('resource.data.published == true'));
    expect(rules, contains('get(ragSourcePath(resource.data.sourceId)).data.status == \'Ready\''));
  });

  test('Draft → student cannot read source or chunk', () {
    final source = {
      'published': false,
      'status': 'Uploading',
      'contentStatus': 'draft',
    };
    expect(
      studentCanReadSource(signedIn: true, admin: false, data: source),
      isFalse,
    );
    expect(
      studentCanReadChunk(
        signedIn: true,
        admin: false,
        chunk: {'published': false, 'sourceId': 's1'},
        source: source,
      ),
      isFalse,
    );
    expect(
      studentCanReadSource(signedIn: true, admin: true, data: source),
      isTrue,
    );
  });

  test('Under Review → student cannot read source or chunk', () {
    final source = {
      'published': false,
      'status': 'Ready',
      'contentStatus': 'underReview',
    };
    expect(
      studentCanReadSource(signedIn: true, admin: false, data: source),
      isFalse,
    );
    expect(
      studentCanReadChunk(
        signedIn: true,
        admin: false,
        chunk: {'published': false, 'sourceId': 's1'},
        source: source,
      ),
      isFalse,
    );
  });

  test('Processing → student cannot read source or chunk', () {
    final source = {'published': true, 'status': 'Processing'};
    expect(
      studentCanReadSource(signedIn: true, admin: false, data: source),
      isFalse,
    );
    expect(
      studentCanReadChunk(
        signedIn: true,
        admin: false,
        chunk: {'published': true, 'sourceId': 's1'},
        source: source,
      ),
      isFalse,
    );
    expect(
      studentPublishedQueryAllowed([
        studentCanReadChunk(
          signedIn: true,
          admin: false,
          chunk: {'published': true, 'sourceId': 's1'},
          source: source,
        ),
      ]),
      isFalse,
    );
  });

  test('Failed → student cannot read source or chunk', () {
    final source = {'published': true, 'status': 'Failed'};
    expect(
      studentCanReadSource(signedIn: true, admin: false, data: source),
      isFalse,
    );
    expect(
      studentCanReadChunk(
        signedIn: true,
        admin: false,
        chunk: {'published': true, 'sourceId': 's1'},
        source: source,
      ),
      isFalse,
    );
  });

  test('Unpublished → student cannot read source or chunk', () {
    final source = {'published': false, 'status': 'Ready'};
    expect(
      studentCanReadSource(signedIn: true, admin: false, data: source),
      isFalse,
    );
    expect(
      studentCanReadChunk(
        signedIn: true,
        admin: false,
        chunk: {'published': false, 'sourceId': 's1'},
        source: source,
      ),
      isFalse,
    );
  });

  test('Published + Ready → student can read source and its chunks', () {
    final source = {
      'published': true,
      'status': 'Ready',
      'contentStatus': 'published',
    };
    expect(
      studentCanReadSource(signedIn: true, admin: false, data: source),
      isTrue,
    );
    expect(
      studentCanReadChunk(
        signedIn: true,
        admin: false,
        chunk: {'published': true, 'sourceId': 's1'},
        source: source,
      ),
      isTrue,
    );
    expect(
      studentCanReadSource(signedIn: false, admin: false, data: source),
      isFalse,
    );
  });

  test('student cannot write RAG; admin can read every status and write', () {
    final sources = _ruleBlock(rules, 'match /ragSources/{sourceId}');
    final chunks = _ruleBlock(rules, 'match /ragChunks/{chunkId}');
    expect(sources, contains('allow write: if isAdmin();'));
    expect(chunks, contains('allow write: if isAdmin();'));
    expect(sources, isNot(contains('allow write: if isSignedIn()')));
    expect(chunks, isNot(contains('allow write: if isSignedIn()')));
    for (final status in ['Uploading', 'Processing', 'Failed', 'Ready']) {
      expect(
        studentCanReadSource(
          signedIn: true,
          admin: true,
          data: {'published': false, 'status': status},
        ),
        isTrue,
        reason: 'admin must manage $status',
      );
    }
  });

  test('student cannot read another student private performance data', () {
    expect(rules, contains('match /students/{uid}'));
    expect(rules, contains('function isOwner(uid)'));
    final attempts = _ruleBlock(rules, 'match /testAttempts/{attemptId}');
    expect(attempts, contains('allow read: if isOwner(uid) || isAdmin();'));
    expect(attempts, contains('allow write: if isOwner(uid);'));
    final plans = _ruleBlock(rules, 'match /studyPlans/{planId}');
    expect(plans, contains('allow read: if isOwner(uid) || isAdmin();'));
    expect(plans, contains('allow write: if isOwner(uid);'));
    final syllabus = _ruleBlock(rules, 'match /syllabusProgress/{topicId}');
    expect(syllabus, contains('allow read: if isOwner(uid) || isAdmin();'));
    expect(rules, isNot(contains('match /{path=**}/testAttempts')));
    expect(rules, isNot(contains('match /{path=**}/studyPlans')));
    expect(rules, isNot(contains('match /{path=**}/syllabusProgress')));
  });

  test('student query of published Ready sources excludes every other status',
      () async {
    final firestore = FakeFirebaseFirestore();
    final sources = RagSourceRepository(firestore: firestore);
    await sources.create(
      _source(
        id: 'draft',
        status: RagSourceStatus.uploading,
        published: false,
        contentStatus: 'draft',
      ),
    );
    await sources.create(
      _source(
        id: 'review',
        status: RagSourceStatus.ready,
        published: false,
        contentStatus: 'underReview',
      ),
    );
    await sources.create(
      _source(
        id: 'processing',
        status: RagSourceStatus.processing,
        published: true,
      ),
    );
    await sources.create(
      _source(
        id: 'failed',
        status: RagSourceStatus.failed,
        published: true,
      ),
    );
    await sources.create(
      _source(
        id: 'unpublished',
        status: RagSourceStatus.ready,
        published: false,
        contentStatus: 'unpublished',
      ),
    );
    await sources.create(
      _source(
        id: 'live',
        status: RagSourceStatus.ready,
        published: true,
        contentStatus: 'published',
      ),
    );

    final studentVisible = await sources.getPublishedReadyOnce();
    expect(studentVisible.map((s) => s.id), ['live']);
    expect(studentVisible.single.isUsableForRetrieval, isTrue);

    final adminAll = await sources.watchAll().first;
    expect(adminAll, hasLength(6));
  });

  test('setPublished on Failed/Processing does not expose chunks', () async {
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
      _source(id: 'fail1', status: RagSourceStatus.failed, published: false),
    );
    await chunks.replaceSourceChunks(
      sourceId: 'fail1',
      chunks: [
        RagChunk(
          id: 'fail1_0',
          sourceId: 'fail1',
          sourceTitle: 'fail1',
          subject: 'Polity',
          chapter: 'FR',
          text: 'secret draft chunk',
          embedding: _embed('secret draft chunk'),
          language: 'en',
          sourceType: 'text',
          published: false,
        ),
      ],
    );
    await processing.setPublished((await sources.get('fail1'))!, true);
    final failed = await sources.get('fail1');
    expect(failed!.published, isTrue);
    expect(failed.status, RagSourceStatus.failed);
    expect(failed.isUsableForRetrieval, isFalse);
    expect(
      (await chunks.getForSource('fail1')).every((c) => !c.published),
      isTrue,
    );
    expect(await sources.getPublishedReadyOnce(), isEmpty);
    expect(await chunks.getPublished(), isEmpty);
  });

  test('successful index then unpublish hides chunks from student retrieval',
      () async {
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
    await sources.create(_source(id: 'pub1', published: true));
    await processing.processSource(
      'pub1',
      inlineText: 'Article 14 equality before law.',
    );
    expect((await sources.getPublishedReadyOnce()).map((s) => s.id), ['pub1']);
    expect(await chunks.getPublished(), isNotEmpty);

    await processing.setPublished((await sources.get('pub1'))!, false);
    expect(await sources.getPublishedReadyOnce(), isEmpty);
    expect(await chunks.getPublished(), isEmpty);
    expect((await sources.watchAll().first).single.published, isFalse);
  });

  test('failed embedding leaves chunks unpublished', () async {
    final firestore = FakeFirebaseFirestore();
    final sources = RagSourceRepository(firestore: firestore);
    final chunks = RagChunkRepository(firestore: firestore);
    final ok = RagProcessingService(
      sources: sources,
      chunks: chunks,
      backend: _FakeBackend(),
      firestore: firestore,
      notes: NotesRepository(firestore: firestore),
      pyqs: PyqRepository(firestore: firestore),
      currentAffairs: CurrentAffairsRepository(firestore: firestore),
    );
    await sources.create(_source(id: 's1', published: true));
    await ok.processSource('s1', inlineText: 'Article 14 equality before law.');
    expect((await chunks.getForSource('s1')).every((c) => c.published), isTrue);

    final failing = RagProcessingService(
      sources: sources,
      chunks: chunks,
      backend: _FakeBackend(failEmbed: true),
      firestore: firestore,
      notes: NotesRepository(firestore: firestore),
      pyqs: PyqRepository(firestore: firestore),
      currentAffairs: CurrentAffairsRepository(firestore: firestore),
    );
    await expectLater(
      failing.processSource(
        's1',
        inlineText: 'Article 14 equality before law rewritten.',
        force: true,
      ),
      throwsA(isA<Object>()),
    );
    expect((await sources.get('s1'))!.status, RagSourceStatus.failed);
    expect(
      (await chunks.getForSource('s1')).every((c) => !c.published),
      isTrue,
    );
    expect(await sources.getPublishedReadyOnce(), isEmpty);
    expect(await chunks.getPublished(), isEmpty);
  });
}
