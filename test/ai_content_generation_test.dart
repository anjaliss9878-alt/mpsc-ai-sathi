import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/ai_generated_content.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/rag_chunk.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/services/ai_content_generation_service.dart';
import 'package:mpsc_combine_ai/services/ai_generated_content_repository.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/gemini_rest_client.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';

class _FakeGemini extends GeminiRestClient {
  _FakeGemini(this.payload) : super(apiKey: 'test', model: 'fake');

  final Map<String, dynamic> payload;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> generateJson({
    required String systemPrompt,
    required String userText,
    double temperature = 0.35,
    int maxOutputTokens = 8192,
  }) async {
    calls++;
    expect(systemPrompt, contains('ONLY the supplied'));
    expect(userText, contains('SOURCE EXCERPTS'));
    return payload;
  }
}

class _FakeRetrieval extends RagRetrievalService {
  _FakeRetrieval(
    this.hits, {
    required RagSourceRepository sources,
    required RagChunkRepository chunks,
  }) : super(
          serverFirst: false,
          sources: sources,
          chunks: chunks,
        );

  final List<RagHit> hits;

  @override
  Future<List<RagHit>> retrieve({
    required String query,
    RagSourceFilter filter = RagSourceFilter.allPublished,
    List<double>? queryEmbedding,
  }) async =>
      hits;
}

void main() {
  const request = AiContentGenerationRequest(
    examId: kGroupBCombinedExamId,
    subjectId: 'sub1',
    chapterId: 'ch1',
    topicId: 'tp1',
    sourceId: 'src1',
    types: {AiGeneratedContentType.mcq},
    mcqCount: 2,
    difficulty: 'Medium',
    subjectTitle: 'Polity',
    chapterTitle: 'Rights',
  );

  test('MCQ validation accepts A/B/C/D with four options', () {
    final ok = AiGeneratedMcqValidation.check({
      'question': 'Q?',
      'optionA': 'a',
      'optionB': 'b',
      'optionC': 'c',
      'optionD': 'd',
      'correctAnswer': 'B',
      'explanation': 'Because source says so',
      'difficulty': 'Medium',
    });
    expect(ok.ok, isTrue);
  });

  test('MCQ validation rejects malformed rows', () {
    expect(
      AiGeneratedMcqValidation.check({
        'question': '',
        'optionA': 'a',
        'optionB': 'b',
        'optionC': 'c',
        'optionD': 'd',
        'correctAnswer': 'A',
        'explanation': 'x',
        'difficulty': 'Medium',
      }).ok,
      isFalse,
    );
    expect(
      AiGeneratedMcqValidation.check({
        'question': 'Q',
        'optionA': 'a',
        'optionB': 'b',
        'optionC': '',
        'optionD': 'd',
        'correctAnswer': 'A',
        'explanation': 'x',
        'difficulty': 'Medium',
      }).ok,
      isFalse,
    );
    expect(
      AiGeneratedMcqValidation.check({
        'question': 'Q',
        'options': ['a', 'b', 'c', 'd'],
        'correctAnswer': 'E',
        'explanation': 'x',
        'difficulty': 'Medium',
      }).ok,
      isFalse,
    );
  });

  test('Flashcard validation requires front and back', () {
    expect(
      AiGeneratedFlashcardValidation.errorFor({'front': '', 'back': 'b'}),
      isNotNull,
    );
    expect(
      AiGeneratedFlashcardValidation.errorFor({'front': 'f', 'back': 'b'}),
      isNull,
    );
  });

  test('parsed MCQ keeps citation, mapping, draft label, not PYQ', () {
    final draft = AiGeneratedMcqDraft.tryParse(
      {
        'question': 'Article 14?',
        'options': ['eq', 'fr', 'eq+fr', 'none'],
        'correctIndex': 0,
        'explanation': 'Equality before law',
        'difficulty': 'Easy',
        'sourceCitation': 'Polity PDF p.12',
      },
      request: request,
      sourceCitation: 'fallback',
    );
    expect(draft, isNotNull);
    expect(draft!.practiceLabel, 'AI Practice Question');
    expect(draft.toContentMap()['isActualPyq'], isFalse);
    expect(draft.toContentMap()['status'], 'draft');
    expect(draft.examId, kGroupBCombinedExamId);
    expect(draft.subjectId, 'sub1');
    expect(draft.chapterId, 'ch1');
    expect(draft.topicId, 'tp1');
    expect(draft.sourceCitation, 'Polity PDF p.12');
  });

  test('fingerprint de-dupes retry MCQs', () {
    final a = AiGeneratedContentRepository.fingerprintFor(
      AiGeneratedContentType.mcq,
      {'question': 'Same Q'},
    );
    final b = AiGeneratedContentRepository.fingerprintFor(
      AiGeneratedContentType.mcq,
      {'question': 'same q'},
    );
    expect(a, b);
  });

  test('staging repo saves draft status and batch', () async {
    final db = FakeFirebaseFirestore();
    final repo = AiGeneratedContentRepository(firestore: db);
    final id = await repo.add(
      AiGeneratedContentItem(
        id: '',
        examId: kGroupBCombinedExamId,
        subjectId: 'sub1',
        chapterId: 'ch1',
        sourceId: 'src1',
        contentType: AiGeneratedContentType.mcq,
        content: {
          'question': 'Q',
          'options': ['a', 'b', 'c', 'd'],
          'correctIndex': 0,
          'explanation': 'e',
          'label': 'AI Practice Question',
          'isActualPyq': false,
        },
        sourceCitation: 'cite',
        status: NoteWorkflowStatus.draft,
        generationBatchId: 'batch1',
      ),
    );
    final loaded = await repo.get(id);
    expect(loaded, isNotNull);
    expect(loaded!.status, NoteWorkflowStatus.draft);
    expect(loaded.isDraft, isTrue);
    expect(loaded.content['isActualPyq'], isFalse);
    final fps = await repo.existingFingerprints('batch1');
    expect(fps, contains('mcq:q'));
  });

  test('generator retrieves Ready source and saves validated MCQs only', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('ragSources').doc('src1').set({
      'title': 'Polity PDF',
      'published': true,
      'status': 'Ready',
      'examId': kGroupBCombinedExamId,
      'subjectId': 'sub1',
      'chapterId': 'ch1',
    });
    final sources = RagSourceRepository(firestore: db);
    final chunks = RagChunkRepository(firestore: db);
    final staging = AiGeneratedContentRepository(firestore: db);
    final gemini = _FakeGemini({
      'insufficient': false,
      'questions': [
        {
          'question': 'Good Q',
          'optionA': 'a',
          'optionB': 'b',
          'optionC': 'c',
          'optionD': 'd',
          'correctAnswer': 'A',
          'explanation': 'From source',
          'difficulty': 'Medium',
          'sourceCitation': 'Polity PDF p.1',
        },
        {
          'question': '',
          'optionA': 'a',
          'optionB': 'b',
          'optionC': 'c',
          'optionD': 'd',
          'correctAnswer': 'A',
          'explanation': 'bad',
          'difficulty': 'Medium',
        },
      ],
    });
    final hits = [
      RagHit(
        chunk: const RagChunk(
          id: 'c1',
          sourceId: 'src1',
          sourceTitle: 'Polity PDF',
          subject: 'Polity',
          chapter: 'Rights',
          text: 'Article 14 equality before law.',
          embedding: [],
          language: 'en',
          sourceType: 'pdf',
          pageNumber: 1,
        ),
        score: 0.9,
      ),
    ];

    final service = AIContentGenerationService(
      retrieval: _FakeRetrieval(hits, sources: sources, chunks: chunks),
      sources: sources,
      gemini: gemini,
      staging: staging,
      apiKey: 'test',
    );

    final result = await service.generate(request);
    expect(result.hitCount, 1);
    expect(result.savedCount, 1);
    expect(gemini.calls, greaterThan(0));
    final drafts = await staging.getBatchOnce(result.batchId);
    expect(drafts, hasLength(1));
    expect(drafts.single.status, NoteWorkflowStatus.draft);
    expect(drafts.single.content['label'], 'AI Practice Question');
    expect(drafts.single.content['isActualPyq'], isFalse);
  });

  test('rejects unpublished / non-Ready sources', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('ragSources').doc('srcBad').set({
      'title': 'Draft PDF',
      'published': false,
      'status': 'Processing',
    });
    final sources = RagSourceRepository(firestore: db);
    final chunks = RagChunkRepository(firestore: db);
    final service = AIContentGenerationService(
      sources: sources,
      staging: AiGeneratedContentRepository(firestore: db),
      gemini: _FakeGemini({}),
      retrieval: _FakeRetrieval(const [], sources: sources, chunks: chunks),
    );
    final result = await service.generate(
      request.copyWithSource('srcBad'),
    );
    expect(result.savedCount, 0);
    expect(result.failures, isNotEmpty);
    expect(result.failures.first.message, contains('Ready'));
  });
}

extension on AiContentGenerationRequest {
  AiContentGenerationRequest copyWithSource(String sourceId) {
    return AiContentGenerationRequest(
      examId: examId,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      sourceId: sourceId,
      types: types,
      mcqCount: mcqCount,
      flashcardCount: flashcardCount,
      difficulty: difficulty,
      subjectTitle: subjectTitle,
      chapterTitle: chapterTitle,
      topicTitle: topicTitle,
      sourceTitle: sourceTitle,
      examTitle: examTitle,
    );
  }
}
