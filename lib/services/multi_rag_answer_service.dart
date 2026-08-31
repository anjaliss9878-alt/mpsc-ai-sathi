import 'package:mpsc_combine_ai/models/chat_message.dart';
import 'package:mpsc_combine_ai/models/multi_rag_result.dart';
import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/models/rag_study_pack.dart';
import 'package:mpsc_combine_ai/rag/multi_rag_context.dart';
import 'package:mpsc_combine_ai/rag/rag_citations.dart';
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/multi_rag_retrieval.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';

/// Which generation backend produced the answer.
enum MultiRagProvider { vertex, existingRag }

/// Grounded Multi-RAG answer with provider + source refs.
class MultiRagAnswer {
  const MultiRagAnswer({
    required this.markdown,
    required this.citations,
    required this.insufficient,
    required this.provider,
    this.fellBack = false,
    this.embedProvider = MultiRagProvider.existingRag,
  });

  final String markdown;
  final List<RagCitation> citations;
  final bool insufficient;
  final MultiRagProvider provider;
  final bool fellBack;
  final MultiRagProvider embedProvider;

  RagTeacherAnswer get asTeacherAnswer => RagTeacherAnswer(
        markdown: markdown,
        citations: citations,
        insufficient: insufficient,
      );
}

/// Student App → existing backend → Multi-RAG router → Vertex embed/generate
/// with the **existing** RAG pipeline as fallback.
///
/// Vertex credentials never enter this class — they stay on `/rag/vertex-*`.
class MultiRagAnswerService {
  MultiRagAnswerService({
    MultiRagRetriever? retrieval,
    RagBackendClient? backend,
    MultiRagContextBuilder contextBuilder = multiRagContextBuilder,
  })  : _retrieval = retrieval ?? multiRagRetrievalService,
        _backend = backend ?? ragBackendClient,
        _contextBuilder = contextBuilder;

  final MultiRagRetriever _retrieval;
  final RagBackendClient _backend;
  final MultiRagContextBuilder _contextBuilder;

  Future<MultiRagAnswer> answer(
    MultiRagQuery query, {
    List<ChatMessage> history = const [],
    String subjectHint = '',
  }) async {
    final q = query.query.trim();
    if (q.isEmpty) throw RagException.emptyQuestion();

    var embedProvider = MultiRagProvider.existingRag;
    List<double>? embedding = query.queryEmbedding;
    if (embedding == null) {
      try {
        embedding = await _backend.vertexEmbedQuery(q);
        embedProvider = MultiRagProvider.vertex;
      } catch (_) {
        try {
          embedding = await _backend.embedQuery(q);
        } catch (e) {
          throw RagException.fromError(e);
        }
      }
    }

    final retrieved = await _retrieval.retrieve(
      MultiRagQuery(
        query: q,
        context: query.context,
        domains: query.domains,
        examId: query.examId,
        subjectId: query.subjectId,
        chapterId: query.chapterId,
        topicId: query.topicId,
        language: query.language,
        year: query.year,
        topKPerDomain: query.topKPerDomain,
        similarityThreshold: query.similarityThreshold,
        hybrid: query.hybrid,
        performance: query.performance,
        queryEmbedding: embedding,
      ),
    );

    final context = _contextBuilder.build(retrieved);
    if (!context.hasEvidence) {
      return MultiRagAnswer(
        markdown: kRagInsufficientEvidence,
        citations: const [],
        insufficient: true,
        provider: MultiRagProvider.existingRag,
        fellBack: embedProvider != MultiRagProvider.vertex,
        embedProvider: embedProvider,
      );
    }

    final body = _learnBody(
      mode: 'answer',
      question: q,
      context: context,
      history: history,
      subjectHint: subjectHint,
    );

    var fellBack = embedProvider != MultiRagProvider.vertex;
    var provider = MultiRagProvider.vertex;
    Map<String, dynamic> payload;
    try {
      payload = await _backend.vertexLearn(body);
    } catch (_) {
      payload = await _backend.learn(body);
      provider = MultiRagProvider.existingRag;
      fellBack = true;
    }

    if (_isInsufficient(payload)) {
      return MultiRagAnswer(
        markdown: kRagInsufficientEvidence,
        citations: const [],
        insufficient: true,
        provider: provider,
        fellBack: fellBack,
        embedProvider: embedProvider,
      );
    }

    final answer = '${payload['answer'] ?? ''}'.trim();
    if (answer.isEmpty) {
      return MultiRagAnswer(
        markdown: kRagInsufficientEvidence,
        citations: const [],
        insufficient: true,
        provider: provider,
        fellBack: fellBack,
        embedProvider: embedProvider,
      );
    }

    final indexes = parseChunkIndexes(payload['chunkIndexes']);
    final citations = _citationsFromContext(context, indexes);
    if (citations.isEmpty) {
      return MultiRagAnswer(
        markdown: kRagInsufficientEvidence,
        citations: const [],
        insufficient: true,
        provider: provider,
        fellBack: fellBack,
        embedProvider: embedProvider,
      );
    }

    return MultiRagAnswer(
      markdown: answer,
      citations: citations,
      insufficient: false,
      provider: provider,
      fellBack: fellBack,
      embedProvider: embedProvider,
    );
  }

  Map<String, dynamic> _learnBody({
    required String mode,
    required String question,
    required MultiRagContext context,
    required List<ChatMessage> history,
    required String subjectHint,
  }) {
    final recent =
        history.length > 8 ? history.sublist(history.length - 8) : history;
    return {
      'mode': mode,
      'question': question,
      'teachingStyle': ragGroundedTeachingStyle(question, hint: subjectHint),
      'chunks': context.chunks,
      'history': [
        for (final m in recent)
          {
            'role': m.isUser ? 'user' : 'assistant',
            'content': m.content,
          },
      ],
    };
  }

  List<RagCitation> _citationsFromContext(
    MultiRagContext context,
    List<int> indexes,
  ) {
    if (indexes.isEmpty) return context.citations;
    final out = <RagCitation>[];
    final seen = <String>{};
    for (final i in indexes) {
      if (i < 0 || i >= context.chunks.length) continue;
      final row = context.chunks[i];
      final chunkId = '${row['chunkId'] ?? ''}';
      final sourceId = '${row['sourceId'] ?? ''}';
      for (final citation in context.citations) {
        final key = '${citation.chunkId}|${citation.sourceId}';
        if (citation.chunkId == chunkId ||
            (chunkId.isEmpty && citation.sourceId == sourceId)) {
          if (seen.add(key)) out.add(citation);
          break;
        }
      }
    }
    return out.isEmpty ? context.citations : out;
  }

  bool _isInsufficient(Map<String, dynamic> payload) {
    final flag = payload['insufficient'];
    if (flag == true) return true;
    if (flag is String && flag.toLowerCase() == 'true') return true;
    return false;
  }
}

final MultiRagAnswerService multiRagAnswerService = MultiRagAnswerService();
