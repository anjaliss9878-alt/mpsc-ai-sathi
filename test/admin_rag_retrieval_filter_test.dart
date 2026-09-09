import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/rag/rag_management.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/multi_rag_retrieval.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';

List<double> fakeEmbed(String text) {
  final v = List<double>.filled(kRagEmbeddingDimensions, 0);
  final tokens = ragKeywordTokens(text, limit: 80);
  if (tokens.isEmpty) {
    v[0] = 1;
    return v;
  }
  for (final token in tokens) {
    final h = token.hashCode.abs();
    v[h % kRagEmbeddingDimensions] += 1;
    v[(h ~/ 97) % kRagEmbeddingDimensions] += 0.35;
  }
  var norm = 0.0;
  for (final n in v) {
    norm += n * n;
  }
  norm = math.sqrt(norm);
  if (norm == 0) return v;
  return [for (final n in v) n / norm];
}

RagSource _politySource({required bool published}) {
  return RagSource(
    id: 'polity_unique',
    title: 'POLITY_Unique Academy',
    subject: 'Polity',
    subjectId: 'pol',
    chapter: 'Constitution',
    chapterId: 'const',
    exam: kMpscDefaultExam,
    examId: kDefaultExamId,
    fileUrl: 'https://example.test/polity.pdf',
    uploadedBy: 'admin',
    createdAt: DateTime(2026, 9, 1),
    status: RagSourceStatus.ready,
    published: published,
    sourceType: RagSourceType.pdf,
    topicId: '',
    ragDomain: ragDomainToString(RagDomain.notes),
    chunkCount: 19,
  );
}

RagChunk _chunk(int i, {required bool published}) {
  const text =
      'भारतीय राज्यघटनेची निर्मिती संविधान सभेने केली. '
      'मसुदा समितीचे अध्यक्ष डॉ. बाबासाहेब आंबेडकर होते.';
  return RagChunk(
    id: 'polity_unique_$i',
    sourceId: 'polity_unique',
    sourceTitle: 'POLITY_Unique Academy',
    subject: 'Polity',
    subjectId: 'pol',
    chapter: 'Constitution',
    chapterId: 'const',
    topicId: '',
    exam: kMpscDefaultExam,
    examId: kDefaultExamId,
    text: text,
    embedding: fakeEmbed(text),
    language: 'mr',
    sourceType: 'pdf',
    ragDomain: ragDomainToString(RagDomain.notes),
    published: published,
    chunkIndex: i,
  );
}

void main() {
  const question = 'भारतीय राज्यघटनेची निर्मिती कशी झाली?';

  test('student published filter drops Ready unpublished POLITY chunks', () {
    final chunks = [for (var i = 0; i < 19; i++) _chunk(i, published: false)];
    const student = RagSourceFilter(
      examId: kDefaultExamId,
      subjectId: 'pol',
      chapterId: 'const',
      topicId: 'making',
      domains: [RagDomain.notes],
      scope: RagSourceScope.subjectChapter,
    );
    final stages = countRagChunkFilterStages(chunks, student);
    expect(stages['candidates'], 19);
    expect(stages['afterPublished'], 0);
    expect(stages['afterAllMetadata'], 0);
    expect(
      RagSourceRepository.applyFilter(
        [_politySource(published: false)],
        student,
      ),
      isEmpty,
    );
  });

  test('admin topic filter no longer drops chapter-level POLITY chunks', () {
    final chunks = [for (var i = 0; i < 19; i++) _chunk(i, published: false)];
    const admin = RagSourceFilter(
      examId: kDefaultExamId,
      subjectId: 'pol',
      chapterId: 'const',
      topicId: 'making',
      domains: [RagDomain.notes],
      onlyPublishedReady: false,
      scope: RagSourceScope.subjectChapter,
    );
    final stages = countRagChunkFilterStages(chunks, admin);
    expect(stages, {
      'candidates': 19,
      'afterPublished': 19,
      'afterExam': 19,
      'afterSubject': 19,
      'afterChapter': 19,
      'afterTopic': 19,
      'afterDomain': 19,
      'afterAllMetadata': 19,
    });
    expect(
      RagSourceRepository.applyFilter(
        [_politySource(published: false)],
        admin,
      ).map((s) => s.id),
      ['polity_unique'],
    );
  });

  test('Admin Search/Test retrieves Ready unpublished POLITY notes', () async {
    final firestore = FakeFirebaseFirestore();
    final sources = RagSourceRepository(firestore: firestore);
    final chunks = RagChunkRepository(firestore: firestore);
    await sources.create(_politySource(published: false));
    await chunks.replaceSourceChunks(
      sourceId: 'polity_unique',
      chunks: [for (var i = 0; i < 19; i++) _chunk(i, published: false)],
    );

    Future<List<double>> embed(String q) async => fakeEmbed(q);
    final retrieval = RagRetrievalService(
      sources: sources,
      chunks: chunks,
      embedQuery: embed,
    );
    final multi = MultiRagRetrievalService(
      retrieval: retrieval,
      embedQuery: embed,
    );
    final query = buildAdminRagTestQuery(
      question: question,
      examId: kDefaultExamId,
      subjectId: 'pol',
      chapterId: 'const',
      topicId: 'making',
      domains: const [RagDomain.notes],
    );
    expect(query.onlyPublishedReady, isFalse);

    final result = await multi.retrieve(query);
    expect(result.hits, isNotEmpty);
    expect(result.hits.length, lessThanOrEqualTo(8));
    expect(
      result.hits.every((h) => h.chunk.sourceTitle == 'POLITY_Unique Academy'),
      isTrue,
    );
    expect(result.hits.first.hit.score, greaterThan(0));
    expect(result.confidence, greaterThan(0));

    final student = await retrieval.retrieve(
      query: question,
      filter: RagSourceFilter(
        examId: kDefaultExamId,
        subjectId: 'pol',
        chapterId: 'const',
        topicId: 'making',
        domains: const [RagDomain.notes],
        scope: RagSourceScope.subjectChapter,
      ),
    );
    expect(student, isEmpty);
  });

  test('Search/Test still finds indexed PDF when chapter filter does not match',
      () async {
    final firestore = FakeFirebaseFirestore();
    final sources = RagSourceRepository(firestore: firestore);
    final chunks = RagChunkRepository(firestore: firestore);
    await sources.create(_politySource(published: true));
    await chunks.replaceSourceChunks(
      sourceId: 'polity_unique',
      chunks: [for (var i = 0; i < 19; i++) _chunk(i, published: true)],
    );

    Future<List<double>> embed(String q) async => fakeEmbed(q);
    final retrieval = RagRetrievalService(
      sources: sources,
      chunks: chunks,
      embedQuery: embed,
    );
    final multi = MultiRagRetrievalService(
      retrieval: retrieval,
      embedQuery: embed,
    );
    final result = await multi.retrieve(
      buildAdminRagTestQuery(
        question: question,
        examId: kGroupBCombinedExamId,
        subjectId: 'wrong-subject',
        chapterId: 'wrong-chapter',
        domains: const [RagDomain.notes],
      ),
    );
    expect(result.hits, isNotEmpty);
    expect(
      result.hits.every((h) => h.chunk.sourceTitle == 'POLITY_Unique Academy'),
      isTrue,
    );
  });
}
