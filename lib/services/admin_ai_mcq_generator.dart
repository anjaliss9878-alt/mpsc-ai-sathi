import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/models/rag_study_pack.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/gemini_rest_client.dart';
import 'package:mpsc_combine_ai/services/rag_grounded_learning_service.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Draft MCQs produced by existing Gemini / RAG infrastructure.
/// Always [NoteWorkflowStatus.draft] — never auto-published.
class AdminAiMcqGenerator {
  AdminAiMcqGenerator({
    RagGroundedLearningService? rag,
    GeminiRestClient? gemini,
    this.apiKey = const String.fromEnvironment('AI_API_KEY'),
  })  : _rag = rag,
        _gemini = gemini;

  final RagGroundedLearningService? _rag;
  final GeminiRestClient? _gemini;
  final String apiKey;

  Future<List<McqItem>> generate({
    required String setTitle,
    required String subjectTitle,
    required String chapterTitle,
    required String topicTitle,
    required String difficulty,
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

    final fromRag = await _fromRag(topicLabel, n);
    final raw = fromRag.isNotEmpty
        ? fromRag
        : await _fromGemini(
            topicLabel: topicLabel,
            difficulty: difficulty,
            count: n,
          );

    final out = <McqItem>[];
    for (var i = 0; i < raw.length && out.length < n; i++) {
      final q = raw[i];
      if (q.question.trim().isEmpty || q.options.length != 4) continue;
      var correct = q.correctIndex;
      if (correct < 0 || correct > 3) correct = 0;
      out.add(
        McqItem(
          id: '',
          setTitle: setTitle,
          subject: subjectTitle,
          difficulty: q.difficulty.isNotEmpty ? q.difficulty : difficulty,
          question: q.question.trim(),
          options: q.options,
          correctIndex: correct,
          explanation: q.explanation.trim(),
          order: DateTime.now().millisecondsSinceEpoch + i,
          tags: const ['ai-generated'],
          subjectId: subjectId,
          chapterId: chapterId,
          published: false,
          examId: examId.isEmpty ? kDefaultExamId : examId,
          targetGroup: targetGroup,
          topicId: topicId,
          status: NoteWorkflowStatus.draft,
        ),
      );
    }
    return out;
  }

  Future<List<RagGeneratedMcq>> _fromRag(String topic, int count) async {
    final rag = _rag ?? RagGroundedLearningService();
    try {
      final qs = await rag.mcqs(topic: topic, subjectHint: topic);
      return qs.take(count).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<RagGeneratedMcq>> _fromGemini({
    required String topicLabel,
    required String difficulty,
    required int count,
  }) async {
    final client = _gemini ??
        GeminiRestClient(apiKey: apiKey, model: 'gemini-flash-lite-latest');
    final payload = await client.generateJson(
      systemPrompt:
          'You write MPSC Combine Group B / Group C practice MCQs. '
          'Return JSON only. Exam is $kMpscDefaultExam. Do not mention Rajyaseva. '
          'Each question must have exactly 4 options and one correctIndex 0-3.',
      userText: 'Generate $count $difficulty MCQs for: $topicLabel.\n'
          'JSON shape: {"questions":[{"question":"","options":["","","",""],'
          '"correctIndex":0,"explanation":"","difficulty":"$difficulty"}]}',
    );
    final out = <RagGeneratedMcq>[];
    for (final row in asMapList(payload['questions'])) {
      final options = asStringList(row['options']);
      if (row['question'] == null || options.length != 4) continue;
      var correct = asInt(row['correctIndex']);
      if (correct < 0 || correct > 3) correct = 0;
      out.add(
        RagGeneratedMcq(
          question: '${row['question']}'.trim(),
          options: options,
          correctIndex: correct,
          explanation: '${row['explanation'] ?? ''}'.trim(),
          difficulty: '${row['difficulty'] ?? difficulty}'.trim(),
          topic: topicLabel,
        ),
      );
    }
    return out;
  }
}
