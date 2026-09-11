import 'package:mpsc_combine_ai/models/ai_generated_content.dart';
import 'package:mpsc_combine_ai/models/ai_teacher_content_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/flashcard_item.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/models/smart_trick_item.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/services/ai_generated_content_repository.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_content_repository.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/gemini_rest_client.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/flashcard_repository.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';
import 'package:mpsc_combine_ai/services/smart_trick_repository.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

typedef AiGenerationProgress = void Function(
  AiGenerationStage stage,
  String detail,
);

class AiGenerationFailure {
  const AiGenerationFailure({
    required this.contentType,
    required this.message,
  });

  final AiGeneratedContentType contentType;
  final String message;
}

class AiGenerationResult {
  const AiGenerationResult({
    required this.batchId,
    required this.savedIds,
    required this.failures,
    required this.hitCount,
    this.insufficientEvidence = false,
  });

  final String batchId;
  final List<String> savedIds;
  final List<AiGenerationFailure> failures;
  final int hitCount;
  final bool insufficientEvidence;

  int get savedCount => savedIds.length;
  bool get hasFailures => failures.isNotEmpty;
}

/// RAG-grounded Admin content generator. Never auto-publishes.
///
/// Uses existing [RagRetrievalService] chunks (published + Ready only) and
/// [GeminiRestClient] for structured JSON. Drafts land in
/// `aiGeneratedContent` until Admin explicitly publishes into live repos.
class AIContentGenerationService {
  AIContentGenerationService({
    RagRetrievalService? retrieval,
    RagSourceRepository? sources,
    GeminiRestClient? gemini,
    AiGeneratedContentRepository? staging,
    this.apiKey = '',
    this.mcqBatchSize = 10,
  })  : _retrieval = retrieval,
        _sources = sources,
        _gemini = gemini,
        _staging = staging;

  final RagRetrievalService? _retrieval;
  final RagSourceRepository? _sources;
  final GeminiRestClient? _gemini;
  final AiGeneratedContentRepository? _staging;
  final String apiKey;
  final int mcqBatchSize;

  RagRetrievalService get retrieval => _retrieval ?? ragRetrievalService;
  RagSourceRepository get sources => _sources ?? ragSourceRepository;
  AiGeneratedContentRepository get staging =>
      _staging ?? aiGeneratedContentRepository;

  GeminiRestClient _client() =>
      _gemini ??
      GeminiRestClient(
        apiKey: apiKey,
        model: 'gemini-flash-lite-latest',
      );

  static const String _groundingRules =
      'Use ONLY the supplied retrieved source excerpts. '
      'Do not invent facts or use outside knowledge. '
      'If the source lacks enough information, return '
      '{"insufficient":true,"reason":"..."} instead of guessing. '
      'Never label anything as an MPSC Previous Year Question / actual PYQ. '
      'Generated MCQs are AI Practice Questions only. '
      'Every item must include a sourceCitation string when possible. '
      'Return JSON only.';

  Future<AiGenerationResult> generate(
    AiContentGenerationRequest request, {
    AiGenerationProgress? onProgress,
    String? reuseBatchId,
  }) async {
    final batchId = (reuseBatchId != null && reuseBatchId.isNotEmpty)
        ? reuseBatchId
        : 'gen_${DateTime.now().millisecondsSinceEpoch}';
    final failures = <AiGenerationFailure>[];
    final savedIds = <String>[];

    onProgress?.call(AiGenerationStage.retrieving, 'Loading Ready RAG source…');
    final source = await sources.get(request.sourceId);
    if (source == null) {
      return AiGenerationResult(
        batchId: batchId,
        savedIds: const [],
        failures: [
          AiGenerationFailure(
            contentType: AiGeneratedContentType.notes,
            message: 'RAG source not found: ${request.sourceId}',
          ),
        ],
        hitCount: 0,
      );
    }
    if (!source.published || !source.isReady) {
      return AiGenerationResult(
        batchId: batchId,
        savedIds: const [],
        failures: [
          AiGenerationFailure(
            contentType: AiGeneratedContentType.notes,
            message:
                'Source must be published == true and status == Ready '
                '(got published=${source.published}, status=${source.status})',
          ),
        ],
        hitCount: 0,
      );
    }

    final filter = RagSourceFilter(
      scope: RagSourceScope.selectedSources,
      sourceIds: [request.sourceId],
      examId: request.examId,
      subjectId: request.subjectId,
      chapterId: request.chapterId,
      topicId: request.topicId,
      onlyPublishedReady: true,
      topK: 14,
    );
    final query = request.topicLabel.isNotEmpty
        ? request.topicLabel
        : (request.sourceTitle.isNotEmpty
            ? request.sourceTitle
            : source.title);
    final hits = await retrieval.retrieve(query: query, filter: filter);
    if (hits.isEmpty) {
      return AiGenerationResult(
        batchId: batchId,
        savedIds: const [],
        failures: [
          const AiGenerationFailure(
            contentType: AiGeneratedContentType.notes,
            message: 'No relevant RAG chunks retrieved for this source/topic.',
          ),
        ],
        hitCount: 0,
        insufficientEvidence: true,
      );
    }

    final excerpt = _formatHits(hits);
    final citation = _defaultCitation(hits, source.title);
    final existing = await staging.existingFingerprints(batchId);

    Future<void> saveType(
      AiGeneratedContentType type,
      List<Map<String, dynamic>> rows,
    ) async {
      onProgress?.call(AiGenerationStage.validating, 'Validating ${aiGeneratedContentTypeLabel(type)}…');
      onProgress?.call(AiGenerationStage.saving, 'Saving ${aiGeneratedContentTypeLabel(type)} drafts…');
      for (final row in rows) {
        final fp = AiGeneratedContentRepository.fingerprintFor(type, row);
        if (existing.contains(fp)) continue;
        final item = AiGeneratedContentItem(
          id: '',
          examId: request.examId,
          subjectId: request.subjectId,
          chapterId: request.chapterId,
          topicId: request.topicId,
          sourceId: request.sourceId,
          contentType: type,
          content: row,
          sourceCitation: '${row['sourceCitation'] ?? citation}'.trim(),
          status: NoteWorkflowStatus.draft,
          generationBatchId: batchId,
        );
        final id = await staging.add(item);
        savedIds.add(id);
        existing.add(fp);
      }
    }

    if (request.types.contains(AiGeneratedContentType.mcq)) {
      onProgress?.call(AiGenerationStage.generatingMcqs, 'Generating MCQs…');
      try {
        final rows = await _generateMcqs(
          request: request,
          excerpt: excerpt,
          citation: citation,
        );
        await saveType(AiGeneratedContentType.mcq, rows);
      } catch (e) {
        failures.add(AiGenerationFailure(
          contentType: AiGeneratedContentType.mcq,
          message: '$e',
        ));
      }
    }

    if (request.types.contains(AiGeneratedContentType.flashcard)) {
      onProgress?.call(
        AiGenerationStage.generatingFlashcards,
        'Generating flashcards…',
      );
      try {
        final rows = await _generateFlashcards(
          request: request,
          excerpt: excerpt,
          citation: citation,
        );
        await saveType(AiGeneratedContentType.flashcard, rows);
      } catch (e) {
        failures.add(AiGenerationFailure(
          contentType: AiGeneratedContentType.flashcard,
          message: '$e',
        ));
      }
    }

    if (request.types.contains(AiGeneratedContentType.notes)) {
      onProgress?.call(AiGenerationStage.generatingNotes, 'Generating notes…');
      try {
        final row = await _generateNotes(
          request: request,
          excerpt: excerpt,
          citation: citation,
        );
        if (row != null) await saveType(AiGeneratedContentType.notes, [row]);
      } catch (e) {
        failures.add(AiGenerationFailure(
          contentType: AiGeneratedContentType.notes,
          message: '$e',
        ));
      }
    }

    if (request.types.contains(AiGeneratedContentType.revisionSummary)) {
      onProgress?.call(
        AiGenerationStage.generatingRevision,
        'Creating revision summary…',
      );
      try {
        final row = await _generateRevision(
          request: request,
          excerpt: excerpt,
          citation: citation,
        );
        if (row != null) {
          await saveType(AiGeneratedContentType.revisionSummary, [row]);
        }
      } catch (e) {
        failures.add(AiGenerationFailure(
          contentType: AiGeneratedContentType.revisionSummary,
          message: '$e',
        ));
      }
    }

    if (request.types.contains(AiGeneratedContentType.importantPoints)) {
      onProgress?.call(
        AiGenerationStage.generatingImportantPoints,
        'Creating important points…',
      );
      try {
        final row = await _generateImportantPoints(
          request: request,
          excerpt: excerpt,
          citation: citation,
        );
        if (row != null) {
          await saveType(AiGeneratedContentType.importantPoints, [row]);
        }
      } catch (e) {
        failures.add(AiGenerationFailure(
          contentType: AiGeneratedContentType.importantPoints,
          message: '$e',
        ));
      }
    }

    if (request.types.contains(AiGeneratedContentType.smartTrick)) {
      onProgress?.call(
        AiGenerationStage.generatingSmartTricks,
        'Generating smart tricks…',
      );
      try {
        final rows = await _generateSmartTricks(
          request: request,
          excerpt: excerpt,
          citation: citation,
        );
        await saveType(AiGeneratedContentType.smartTrick, rows);
      } catch (e) {
        failures.add(AiGenerationFailure(
          contentType: AiGeneratedContentType.smartTrick,
          message: '$e',
        ));
      }
    }

    if (request.types.contains(AiGeneratedContentType.aiTeacherLesson)) {
      onProgress?.call(
        AiGenerationStage.generatingLesson,
        'Generating AI Teacher lesson…',
      );
      try {
        final row = await _generateLesson(
          request: request,
          excerpt: excerpt,
          citation: citation,
        );
        if (row != null) {
          await saveType(AiGeneratedContentType.aiTeacherLesson, [row]);
        }
      } catch (e) {
        failures.add(AiGenerationFailure(
          contentType: AiGeneratedContentType.aiTeacherLesson,
          message: '$e',
        ));
      }
    }

    onProgress?.call(
      failures.isEmpty ? AiGenerationStage.done : AiGenerationStage.failed,
      failures.isEmpty
          ? 'Saved ${savedIds.length} draft(s).'
          : 'Saved ${savedIds.length}; ${failures.length} type(s) failed.',
    );

    return AiGenerationResult(
      batchId: batchId,
      savedIds: savedIds,
      failures: failures,
      hitCount: hits.length,
    );
  }

  /// Promote one staging draft into the live collection (still requires Admin).
  Future<String> publishDraft(AiGeneratedContentItem item) async {
    if (item.id.isEmpty) {
      throw StateError('Missing staging document id');
    }
    final c = item.content;
    String promotedCollection;
    String promotedId;

    switch (item.contentType) {
      case AiGeneratedContentType.mcq:
        final options = asStringList(c['options']);
        final opts = options.length == 4
            ? options
            : [
                '${c['optionA'] ?? ''}',
                '${c['optionB'] ?? ''}',
                '${c['optionC'] ?? ''}',
                '${c['optionD'] ?? ''}',
              ];
        var correct = asInt(c['correctIndex']);
        if (correct < 0 || correct > 3) {
          final letter = '${c['correctAnswer']}'.trim().toUpperCase();
          correct = letter.isEmpty ? 0 : letter.codeUnitAt(0) - 65;
        }
        promotedId = await mcqRepository.add(
          McqItem(
            id: '',
            setTitle: 'AI Practice Question',
            subject: '${c['subject'] ?? ''}',
            difficulty: '${c['difficulty'] ?? 'Medium'}',
            question: '${c['question']}',
            options: opts,
            correctIndex: correct.clamp(0, 3),
            explanation: () {
              final base = '${c['explanation']}'.trim();
              final cite = item.sourceCitation.trim().isNotEmpty
                  ? item.sourceCitation.trim()
                  : '${c['sourceCitation'] ?? ''}'.trim();
              if (cite.isEmpty) return base;
              if (base.contains(cite)) return base;
              return base.isEmpty ? 'Source: $cite' : '$base\n\nSource: $cite';
            }(),
            order: DateTime.now().millisecondsSinceEpoch,
            tags: const [
              'ai-generated',
              'ai-practice-question',
              'not-actual-pyq',
            ],
            subjectId: item.subjectId,
            chapterId: item.chapterId,
            topicId: item.topicId,
            examId: item.examId,
            published: true,
            status: NoteWorkflowStatus.published,
          ),
        );
        promotedCollection = McqRepository.collection;
        break;
      case AiGeneratedContentType.flashcard:
        promotedId = await flashcardRepository.add(
          FlashcardItem(
            id: '',
            title: '${c['front']}',
            front: '${c['front']}',
            back: '${c['back']}',
            explanation: '${c['explanation'] ?? ''}',
            tags: const ['ai-generated'],
            examId: item.examId,
            subjectId: item.subjectId,
            chapterId: item.chapterId,
            topicId: item.topicId,
            published: true,
            status: NoteWorkflowStatus.published,
            order: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        promotedCollection = FlashcardRepository.collection;
        break;
      case AiGeneratedContentType.smartTrick:
        promotedId = await smartTrickRepository.add(
          SmartTrickItem(
            id: '',
            title: '${c['title']}',
            concept: '${c['title']}',
            memoryTrick: '${c['trick']}',
            explanation: '${c['explanation']}',
            example: '${c['example'] ?? ''}',
            tags: const ['ai-generated'],
            examId: item.examId,
            subjectId: item.subjectId,
            chapterId: item.chapterId,
            topicId: item.topicId,
            published: true,
            status: NoteWorkflowStatus.published,
            order: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        promotedCollection = SmartTrickRepository.collection;
        break;
      case AiGeneratedContentType.notes:
      case AiGeneratedContentType.revisionSummary:
      case AiGeneratedContentType.importantPoints:
        final title = '${c['title']}'.trim().isEmpty
            ? 'AI Notes Draft'
            : '${c['title']}'.trim();
        final markdown = '${c['markdown'] ?? c['summary'] ?? ''}'.trim();
        final points = asStringList(c['keyPoints'] ?? c['points']);
        promotedId = await notesRepository.saveNote(
          examId: item.examId,
          subjectId: item.subjectId,
          chapterId: item.chapterId,
          topicId: item.topicId.isEmpty ? item.chapterId : item.topicId,
          title: title,
          description: '${c['summary'] ?? ''}'.trim(),
          contentMarkdown: markdown,
          importantPoints: points,
          revisionSummary: item.contentType ==
                  AiGeneratedContentType.revisionSummary
              ? points
              : asStringList(c['revisionSummary']),
          status: NoteWorkflowStatus.published,
          tags: const ['ai-generated'],
        );
        promotedCollection = 'notes';
        break;
      case AiGeneratedContentType.aiTeacherLesson:
        final sections = asStringList(c['sections']);
        final examples = asStringList(c['examples']);
        final quick = asStringList(c['quickRevision']);
        promotedId = await aiTeacherContentRepository.add(
          AiTeacherContentItem(
            id: '',
            lessonTitle: '${c['title']}'.trim().isEmpty
                ? 'AI Lesson'
                : '${c['title']}'.trim(),
            subjectName: '',
            summary: '${c['introduction'] ?? ''}'.trim(),
            keywords: asStringList(c['keywords']),
            aiPrompt: '',
            teachingScript: [
              if ('${c['introduction']}'.trim().isNotEmpty)
                '${c['introduction']}'.trim(),
              ...sections,
            ],
            slides: [
              for (var i = 0; i < sections.length; i++)
                GeneratedSlide(
                  title: 'Section ${i + 1}',
                  bullets: [sections[i]],
                ),
            ],
            quiz: const [],
            notes: [...examples, ...quick],
            order: DateTime.now().millisecondsSinceEpoch,
            examId: item.examId,
            subjectId: item.subjectId,
            chapterId: item.chapterId,
            topicId: item.topicId,
            published: true,
            status: NoteWorkflowStatus.published,
          ),
        );
        promotedCollection = AiTeacherContentRepository.collection;
        break;
    }

    await staging.update(
      item.copyWith(
        status: NoteWorkflowStatus.published,
        promotedCollection: promotedCollection,
        promotedDocId: promotedId,
      ),
    );
    return promotedId;
  }

  Future<List<Map<String, dynamic>>> _generateMcqs({
    required AiContentGenerationRequest request,
    required String excerpt,
    required String citation,
  }) async {
    final total = request.mcqCount.clamp(1, 50);
    final out = <Map<String, dynamic>>[];
    var remaining = total;
    while (remaining > 0 && out.length < total) {
      final n = remaining > mcqBatchSize ? mcqBatchSize : remaining;
      final payload = await _client().generateJson(
        systemPrompt: _groundingRules,
        userText: '''
Topic: ${request.topicLabel}
Difficulty: ${request.difficulty}
Generate exactly $n AI Practice MCQs (NOT previous-year questions).
Each question: exactly 4 options, one correctAnswer A/B/C/D, explanation grounded in sources.
JSON:
{"insufficient":false,"questions":[{"question":"","optionA":"","optionB":"","optionC":"","optionD":"","correctAnswer":"A","explanation":"","difficulty":"${request.difficulty}","sourceCitation":""}]}

SOURCE EXCERPTS:
$excerpt
''',
      );
      if (payload['insufficient'] == true) break;
      for (final row in asMapList(payload['questions'])) {
        final draft = AiGeneratedMcqDraft.tryParse(
          row,
          request: request,
          sourceCitation: citation,
        );
        if (draft == null) continue;
        if (draft.sourceCitation.isEmpty) {
          // Prefer model citation; fall back to retrieval citation.
          out.add({
            ...draft.toContentMap(),
            'sourceCitation': citation,
          });
        } else {
          out.add(draft.toContentMap());
        }
        if (out.length >= total) break;
      }
      remaining = total - out.length;
      if (asMapList(payload['questions']).isEmpty) break;
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _generateFlashcards({
    required AiContentGenerationRequest request,
    required String excerpt,
    required String citation,
  }) async {
    final n = request.flashcardCount.clamp(1, 30);
    final payload = await _client().generateJson(
      systemPrompt: _groundingRules,
      userText: '''
Topic: ${request.topicLabel}
Difficulty: ${request.difficulty}
Generate exactly $n flashcards from the source only.
JSON: {"insufficient":false,"cards":[{"front":"","back":"","difficulty":"${request.difficulty}","sourceCitation":""}]}

SOURCE EXCERPTS:
$excerpt
''',
    );
    if (payload['insufficient'] == true) return const [];
    final out = <Map<String, dynamic>>[];
    for (final row in asMapList(payload['cards'])) {
      final err = AiGeneratedFlashcardValidation.errorFor(row);
      if (err != null) continue;
      out.add({
        'front': '${row['front']}'.trim(),
        'back': '${row['back']}'.trim(),
        'difficulty': '${row['difficulty'] ?? request.difficulty}'.trim(),
        'sourceId': request.sourceId,
        'sourceCitation':
            '${row['sourceCitation'] ?? citation}'.trim().isEmpty
                ? citation
                : '${row['sourceCitation'] ?? citation}'.trim(),
        'examId': request.examId,
        'subjectId': request.subjectId,
        'chapterId': request.chapterId,
        'topicId': request.topicId,
        'status': 'draft',
      });
    }
    return out;
  }

  Future<Map<String, dynamic>?> _generateNotes({
    required AiContentGenerationRequest request,
    required String excerpt,
    required String citation,
  }) async {
    final payload = await _client().generateJson(
      systemPrompt: _groundingRules,
      userText: '''
Topic: ${request.topicLabel}
Write structured study notes from the source only (Marathi preferred when source is Marathi).
JSON: {"insufficient":false,"title":"","markdown":"","sourceCitation":""}

SOURCE EXCERPTS:
$excerpt
''',
    );
    if (payload['insufficient'] == true) return null;
    final title = '${payload['title'] ?? request.topicLabel}'.trim();
    final markdown = '${payload['markdown'] ?? ''}'.trim();
    if (title.isEmpty || markdown.isEmpty) return null;
    return {
      'title': title,
      'markdown': markdown,
      'sourceId': request.sourceId,
      'sourceCitation': '${payload['sourceCitation'] ?? citation}'.trim(),
      'examId': request.examId,
      'subjectId': request.subjectId,
      'chapterId': request.chapterId,
      'topicId': request.topicId,
      'status': 'draft',
    };
  }

  Future<Map<String, dynamic>?> _generateRevision({
    required AiContentGenerationRequest request,
    required String excerpt,
    required String citation,
  }) async {
    final payload = await _client().generateJson(
      systemPrompt: _groundingRules,
      userText: '''
Topic: ${request.topicLabel}
Create a short revision summary from the source only.
JSON: {"insufficient":false,"title":"","summary":"","keyPoints":["..."],"sourceCitation":""}

SOURCE EXCERPTS:
$excerpt
''',
    );
    if (payload['insufficient'] == true) return null;
    final title = '${payload['title'] ?? request.topicLabel}'.trim();
    final summary = '${payload['summary'] ?? ''}'.trim();
    final points = asStringList(payload['keyPoints']);
    if (title.isEmpty || (summary.isEmpty && points.isEmpty)) return null;
    return {
      'title': title,
      'summary': summary,
      'keyPoints': points,
      'sourceId': request.sourceId,
      'sourceCitation': '${payload['sourceCitation'] ?? citation}'.trim(),
      'examId': request.examId,
      'subjectId': request.subjectId,
      'chapterId': request.chapterId,
      'topicId': request.topicId,
      'status': 'draft',
    };
  }

  Future<Map<String, dynamic>?> _generateImportantPoints({
    required AiContentGenerationRequest request,
    required String excerpt,
    required String citation,
  }) async {
    final payload = await _client().generateJson(
      systemPrompt: _groundingRules,
      userText: '''
Topic: ${request.topicLabel}
Extract up to 10 important points from the source only.
JSON: {"insufficient":false,"title":"","points":["..."],"sourceCitation":""}

SOURCE EXCERPTS:
$excerpt
''',
    );
    if (payload['insufficient'] == true) return null;
    final points = asStringList(payload['points']);
    if (points.isEmpty) return null;
    return {
      'title': '${payload['title'] ?? 'Important Points'}'.trim(),
      'points': points,
      'sourceId': request.sourceId,
      'sourceCitation': '${payload['sourceCitation'] ?? citation}'.trim(),
      'examId': request.examId,
      'subjectId': request.subjectId,
      'chapterId': request.chapterId,
      'topicId': request.topicId,
      'status': 'draft',
    };
  }

  Future<List<Map<String, dynamic>>> _generateSmartTricks({
    required AiContentGenerationRequest request,
    required String excerpt,
    required String citation,
  }) async {
    final payload = await _client().generateJson(
      systemPrompt: _groundingRules,
      userText: '''
Topic: ${request.topicLabel}
Create up to 5 memory tricks grounded only in the source.
JSON: {"insufficient":false,"tricks":[{"title":"","trick":"","explanation":"","sourceCitation":""}]}

SOURCE EXCERPTS:
$excerpt
''',
    );
    if (payload['insufficient'] == true) return const [];
    final out = <Map<String, dynamic>>[];
    for (final row in asMapList(payload['tricks'])) {
      final title = '${row['title'] ?? ''}'.trim();
      final trick = '${row['trick'] ?? ''}'.trim();
      final explanation = '${row['explanation'] ?? ''}'.trim();
      if (title.isEmpty || trick.isEmpty || explanation.isEmpty) continue;
      out.add({
        'title': title,
        'trick': trick,
        'explanation': explanation,
        'sourceCitation':
            '${row['sourceCitation'] ?? citation}'.trim().isEmpty
                ? citation
                : '${row['sourceCitation'] ?? citation}'.trim(),
        'sourceId': request.sourceId,
        'examId': request.examId,
        'subjectId': request.subjectId,
        'chapterId': request.chapterId,
        'topicId': request.topicId,
        'status': 'draft',
      });
    }
    return out;
  }

  Future<Map<String, dynamic>?> _generateLesson({
    required AiContentGenerationRequest request,
    required String excerpt,
    required String citation,
  }) async {
    final payload = await _client().generateJson(
      systemPrompt: _groundingRules,
      userText: '''
Topic: ${request.topicLabel}
Create an AI Teacher lesson outline from the source only.
JSON: {"insufficient":false,"title":"","introduction":"","sections":["..."],"examples":["..."],"quickRevision":["..."],"keywords":["..."],"sourceCitation":""}

SOURCE EXCERPTS:
$excerpt
''',
    );
    if (payload['insufficient'] == true) return null;
    final title = '${payload['title'] ?? request.topicLabel}'.trim();
    final introduction = '${payload['introduction'] ?? ''}'.trim();
    final sections = asStringList(payload['sections']);
    if (title.isEmpty || (introduction.isEmpty && sections.isEmpty)) {
      return null;
    }
    return {
      'title': title,
      'introduction': introduction,
      'sections': sections,
      'examples': asStringList(payload['examples']),
      'quickRevision': asStringList(payload['quickRevision']),
      'keywords': asStringList(payload['keywords']),
      'sourceCitation': '${payload['sourceCitation'] ?? citation}'.trim(),
      'sourceId': request.sourceId,
      'examId': request.examId,
      'subjectId': request.subjectId,
      'chapterId': request.chapterId,
      'topicId': request.topicId,
      'status': 'draft',
    };
  }

  String _formatHits(List<RagHit> hits) {
    final buf = StringBuffer();
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      final c = h.chunk;
      buf.writeln('--- CHUNK ${i + 1} (score=${h.score.toStringAsFixed(3)}) ---');
      if (c.sourceTitle.isNotEmpty) buf.writeln('Source: ${c.sourceTitle}');
      if (c.pageNumber != null && c.pageNumber! > 0) {
        buf.writeln('Page: ${c.pageNumber}');
      }
      buf.writeln(c.text.trim());
      buf.writeln();
    }
    return buf.toString();
  }

  String _defaultCitation(List<RagHit> hits, String sourceTitle) {
    if (hits.isEmpty) return sourceTitle;
    final c = hits.first.chunk;
    final page =
        c.pageNumber != null && c.pageNumber! > 0 ? ' p.${c.pageNumber}' : '';
    final title = c.sourceTitle.isNotEmpty ? c.sourceTitle : sourceTitle;
    return '$title$page';
  }
}

final AIContentGenerationService aiContentGenerationService =
    AIContentGenerationService();
