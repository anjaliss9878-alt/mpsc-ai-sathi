import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/flashcard_item.dart';
import 'package:mpsc_combine_ai/models/rag_study_pack.dart';
import 'package:mpsc_combine_ai/models/smart_trick_item.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/gemini_rest_client.dart';
import 'package:mpsc_combine_ai/services/rag_grounded_learning_service.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Draft Flashcards / Smart Tricks from existing Gemini / RAG infrastructure.
/// Always [NoteWorkflowStatus.draft] — never auto-published.
class AdminAiStudyGenerator {
  AdminAiStudyGenerator({
    RagGroundedLearningService? rag,
    GeminiRestClient? gemini,
    this.apiKey = const String.fromEnvironment('AI_API_KEY'),
  })  : _rag = rag,
        _gemini = gemini;

  final RagGroundedLearningService? _rag;
  final GeminiRestClient? _gemini;
  final String apiKey;

  static FlashcardItem flashcardDraft({
    required RagFlashcard card,
    required String examId,
    required String targetGroup,
    required String subjectId,
    required String chapterId,
    required String topicId,
    String language = 'mr',
    int order = 0,
  }) {
    return FlashcardItem(
      id: '',
      title: card.front,
      front: card.front,
      back: card.back,
      explanation: card.explanation,
      tags: const ['ai-generated'],
      examId: examId.isEmpty ? kDefaultExamId : examId,
      targetGroup: targetGroup,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      language: language,
      published: false,
      status: NoteWorkflowStatus.draft,
      order: order,
    );
  }

  static SmartTrickItem smartTrickDraft({
    required String title,
    required String concept,
    required String memoryTrick,
    required String explanation,
    required String example,
    required String examId,
    required String targetGroup,
    required String subjectId,
    required String chapterId,
    required String topicId,
    String language = 'mr',
    int order = 0,
  }) {
    return SmartTrickItem(
      id: '',
      title: title,
      concept: concept,
      memoryTrick: memoryTrick,
      explanation: explanation,
      example: example,
      tags: const ['ai-generated'],
      examId: examId.isEmpty ? kDefaultExamId : examId,
      targetGroup: targetGroup,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      language: language,
      published: false,
      status: NoteWorkflowStatus.draft,
      order: order,
    );
  }

  Future<List<FlashcardItem>> generateFlashcards({
    required String subjectTitle,
    required String chapterTitle,
    required String topicTitle,
    required int count,
    required String examId,
    required String targetGroup,
    required String subjectId,
    required String chapterId,
    required String topicId,
  }) async {
    final n = count.clamp(1, 20);
    final topicLabel = [
      if (subjectTitle.isNotEmpty) subjectTitle,
      if (chapterTitle.isNotEmpty) chapterTitle,
      if (topicTitle.isNotEmpty) topicTitle,
    ].join(' / ');

    final fromRag = await _flashcardsFromRag(topicLabel, n);
    final raw = fromRag.isNotEmpty
        ? fromRag
        : await _flashcardsFromGemini(topicLabel: topicLabel, count: n);

    final out = <FlashcardItem>[];
    for (var i = 0; i < raw.length && out.length < n; i++) {
      final card = raw[i];
      if (card.front.trim().isEmpty || card.back.trim().isEmpty) continue;
      out.add(
        flashcardDraft(
          card: card,
          examId: examId,
          targetGroup: targetGroup,
          subjectId: subjectId,
          chapterId: chapterId,
          topicId: topicId,
          order: DateTime.now().millisecondsSinceEpoch + i,
        ),
      );
    }
    return out;
  }

  Future<List<SmartTrickItem>> generateSmartTricks({
    required String subjectTitle,
    required String chapterTitle,
    required String topicTitle,
    required int count,
    required String examId,
    required String targetGroup,
    required String subjectId,
    required String chapterId,
    required String topicId,
  }) async {
    final n = count.clamp(1, 10);
    final topicLabel = [
      if (subjectTitle.isNotEmpty) subjectTitle,
      if (chapterTitle.isNotEmpty) chapterTitle,
      if (topicTitle.isNotEmpty) topicTitle,
    ].join(' / ');

    final fromRag = await _tricksFromRag(topicLabel, n);
    final raw = fromRag.isNotEmpty
        ? fromRag
        : await _tricksFromGemini(topicLabel: topicLabel, count: n);

    final out = <SmartTrickItem>[];
    for (var i = 0; i < raw.length && out.length < n; i++) {
      final row = raw[i];
      if (row.memoryTrick.trim().isEmpty) continue;
      out.add(
        smartTrickDraft(
          title: row.title.isNotEmpty ? row.title : topicTitle,
          concept: row.concept.isNotEmpty ? row.concept : topicLabel,
          memoryTrick: row.memoryTrick,
          explanation: row.explanation,
          example: row.example,
          examId: examId,
          targetGroup: targetGroup,
          subjectId: subjectId,
          chapterId: chapterId,
          topicId: topicId,
          order: DateTime.now().millisecondsSinceEpoch + i,
        ),
      );
    }
    return out;
  }

  Future<List<RagFlashcard>> _flashcardsFromRag(String topic, int count) async {
    final rag = _rag ?? RagGroundedLearningService();
    try {
      final cards = await rag.flashcards(topic: topic, subjectHint: topic);
      return cards.take(count).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<RagFlashcard>> _flashcardsFromGemini({
    required String topicLabel,
    required int count,
  }) async {
    final client = _gemini ??
        GeminiRestClient(apiKey: apiKey, model: 'gemini-flash-lite-latest');
    final payload = await client.generateJson(
      systemPrompt:
          'You write MPSC Combine Group B / Group C flashcards. '
          'Return JSON only. Exam is $kMpscDefaultExam. Do not mention Rajyaseva.',
      userText: 'Generate $count flashcards for: $topicLabel.\n'
          'JSON shape: {"cards":[{"front":"","back":"","explanation":""}]}',
    );
    final out = <RagFlashcard>[];
    for (final row in asMapList(payload['cards'])) {
      final front = '${row['front'] ?? ''}'.trim();
      final back = '${row['back'] ?? ''}'.trim();
      if (front.isEmpty || back.isEmpty) continue;
      out.add(
        RagFlashcard(
          front: front,
          back: back,
          explanation: '${row['explanation'] ?? ''}'.trim(),
        ),
      );
    }
    return out;
  }

  Future<List<_TrickDraft>> _tricksFromRag(String topic, int count) async {
    final rag = _rag ?? RagGroundedLearningService();
    try {
      final tricks = await rag.memoryTricks(topic: topic, subjectHint: topic);
      return [
        for (final t in tricks.take(count))
          _TrickDraft(
            title: topic,
            concept: topic,
            memoryTrick: t.trick,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<_TrickDraft>> _tricksFromGemini({
    required String topicLabel,
    required int count,
  }) async {
    final client = _gemini ??
        GeminiRestClient(apiKey: apiKey, model: 'gemini-flash-lite-latest');
    final payload = await client.generateJson(
      systemPrompt:
          'You write MPSC Combine Group B / Group C memory tricks. '
          'Return JSON only. Exam is $kMpscDefaultExam. Do not mention Rajyaseva.',
      userText: 'Generate $count memory tricks for: $topicLabel.\n'
          'JSON shape: {"tricks":[{"title":"","concept":"","memoryTrick":"",'
          '"explanation":"","example":""}]}',
    );
    final out = <_TrickDraft>[];
    for (final row in asMapList(payload['tricks'])) {
      final trick = '${row['memoryTrick'] ?? row['trick'] ?? ''}'.trim();
      if (trick.isEmpty) continue;
      out.add(
        _TrickDraft(
          title: '${row['title'] ?? ''}'.trim(),
          concept: '${row['concept'] ?? topicLabel}'.trim(),
          memoryTrick: trick,
          explanation: '${row['explanation'] ?? ''}'.trim(),
          example: '${row['example'] ?? ''}'.trim(),
        ),
      );
    }
    return out;
  }
}

class _TrickDraft {
  const _TrickDraft({
    required this.title,
    required this.concept,
    required this.memoryTrick,
    this.explanation = '',
    this.example = '',
  });

  final String title;
  final String concept;
  final String memoryTrick;
  final String explanation;
  final String example;
}
