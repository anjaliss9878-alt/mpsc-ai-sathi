import 'package:mpsc_combine_ai/models/chat_message.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/models/rag_study_pack.dart';
import 'package:mpsc_combine_ai/rag/rag_citations.dart';
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// NotebookLM-style study layer: retrieve MPSC chunks, then Gemini, then
/// citations built from chunk metadata (never from model-invented pages).
class RagGroundedLearningService {
  RagGroundedLearningService({
    RagRetrievalService? retrieval,
    RagBackendClient? backend,
    PyqRepository? pyqs,
    Future<List<PyqItem>> Function()? loadPublishedPyqs,
  })  : _retrievalOverride = retrieval,
        _backendOverride = backend,
        _pyqsOverride = pyqs,
        _loadPublishedPyqsOverride = loadPublishedPyqs;

  final RagRetrievalService? _retrievalOverride;
  final RagBackendClient? _backendOverride;
  final PyqRepository? _pyqsOverride;
  final Future<List<PyqItem>> Function()? _loadPublishedPyqsOverride;

  RagRetrievalService get _retrieval =>
      _retrievalOverride ?? ragRetrievalService;
  RagBackendClient get _backend => _backendOverride ?? ragBackendClient;
  Future<List<PyqItem>> Function() get _loadPublishedPyqs =>
      _loadPublishedPyqsOverride ??
      (() => (_pyqsOverride ?? pyqRepository).watchPublished().first);

  /// Last retrieval used (tests + UI can inspect).
  List<RagHit> lastHits = const [];

  Future<RagTeacherAnswer> answer({
    required String question,
    List<ChatMessage> history = const [],
    RagSourceFilter filter = RagSourceFilter.allPublished,
    String subjectHint = '',
    List<RagHit>? prefetchedHits,
  }) async {
    final retrieved = await _retrieveOrInsufficient(
      question: question,
      history: history,
      filter: filter,
      prefetchedHits: prefetchedHits,
    );
    if (retrieved.insufficient) return retrieved.asTeacherAnswer();

    final payload = await _learn(
      mode: 'answer',
      question: question,
      hits: retrieved.hits,
      history: history,
      subjectHint: subjectHint,
    );
    if (_isInsufficient(payload)) {
      return const RagTeacherAnswer(
        markdown: kRagInsufficientEvidence,
        citations: [],
        insufficient: true,
      );
    }
    final indexes = parseChunkIndexes(payload['chunkIndexes']);
    final citations = indexes.isEmpty
        ? citationsFromHits(retrieved.hits)
        : citationsFromChunkIndexes(retrieved.hits, indexes);
    final answer = '${payload['answer'] ?? ''}'.trim();
    if (answer.isEmpty) {
      return const RagTeacherAnswer(
        markdown: kRagInsufficientEvidence,
        citations: [],
        insufficient: true,
      );
    }
    return RagTeacherAnswer(
      markdown: answer,
      citations: citations,
      insufficient: false,
    );
  }

  Future<RagSourceSummary> summary({
    required String topic,
    List<ChatMessage> history = const [],
    RagSourceFilter filter = RagSourceFilter.allPublished,
    String subjectHint = '',
    List<RagHit>? prefetchedHits,
  }) async {
    final retrieved = await _retrieveOrInsufficient(
      question: topic,
      history: history,
      filter: filter.copyWith(topK: 12),
      prefetchedHits: prefetchedHits,
    );
    if (retrieved.insufficient) {
      return const RagSourceSummary(
        detailed: kRagInsufficientEvidence,
        shortNotes: kRagInsufficientEvidence,
        fiveMinuteRevision: kRagInsufficientEvidence,
      );
    }
    final payload = await _learn(
      mode: 'summary',
      question: topic,
      hits: retrieved.hits,
      history: history,
      subjectHint: subjectHint,
    );
    if (_isInsufficient(payload)) {
      return const RagSourceSummary(
        detailed: kRagInsufficientEvidence,
        shortNotes: kRagInsufficientEvidence,
        fiveMinuteRevision: kRagInsufficientEvidence,
      );
    }
    final citations = _citations(retrieved.hits, payload);
    return RagSourceSummary(
      detailed: '${payload['detailed'] ?? ''}'.trim(),
      shortNotes: '${payload['shortNotes'] ?? ''}'.trim(),
      fiveMinuteRevision: '${payload['fiveMinuteRevision'] ?? ''}'.trim(),
      importantFacts: asStringList(payload['importantFacts']),
      examPoints: asStringList(payload['examPoints']),
      commonMistakes: asStringList(payload['commonMistakes']),
      citations: citations,
    );
  }

  Future<List<RagGeneratedMcq>> mcqs({
    required String topic,
    List<ChatMessage> history = const [],
    RagSourceFilter filter = RagSourceFilter.allPublished,
    String subjectHint = '',
    List<RagHit>? prefetchedHits,
  }) async {
    final retrieved = await _retrieveOrInsufficient(
      question: topic,
      history: history,
      filter: filter.copyWith(topK: 12),
      prefetchedHits: prefetchedHits,
    );
    if (retrieved.insufficient) return const [];
    final payload = await _learn(
      mode: 'mcq',
      question: topic,
      hits: retrieved.hits,
      history: history,
      subjectHint: subjectHint,
    );
    if (_isInsufficient(payload)) return const [];
    final out = <RagGeneratedMcq>[];
    for (final row in asMapList(payload['questions'])) {
      final options = asStringList(row['options']);
      if (row['question'] == null || options.length != 4) continue;
      var correct = asInt(row['correctIndex']);
      if (correct < 0 || correct > 3) correct = 0;
      final difficulty = _normalizeDifficulty('${row['difficulty'] ?? ''}');
      final indexes = parseChunkIndexes(row['chunkIndexes']);
      out.add(
        RagGeneratedMcq(
          question: '${row['question']}'.trim(),
          options: options,
          correctIndex: correct,
          explanation: '${row['explanation'] ?? ''}'.trim(),
          difficulty: difficulty,
          topic: '${row['topic'] ?? topic}'.trim(),
          citations: indexes.isEmpty
              ? citationsFromHits(retrieved.hits)
              : citationsFromChunkIndexes(retrieved.hits, indexes),
        ),
      );
    }
    return out;
  }

  Future<List<RagFlashcard>> flashcards({
    required String topic,
    List<ChatMessage> history = const [],
    RagSourceFilter filter = RagSourceFilter.allPublished,
    String subjectHint = '',
    List<RagHit>? prefetchedHits,
  }) async {
    final retrieved = await _retrieveOrInsufficient(
      question: topic,
      history: history,
      filter: filter.copyWith(topK: 12),
      prefetchedHits: prefetchedHits,
    );
    if (retrieved.insufficient) return const [];
    final payload = await _learn(
      mode: 'flashcards',
      question: topic,
      hits: retrieved.hits,
      history: history,
      subjectHint: subjectHint,
    );
    if (_isInsufficient(payload)) return const [];
    final out = <RagFlashcard>[];
    for (final row in asMapList(payload['cards'])) {
      final front = '${row['front'] ?? ''}'.trim();
      final back = '${row['back'] ?? ''}'.trim();
      if (front.isEmpty || back.isEmpty) continue;
      final indexes = parseChunkIndexes(row['chunkIndexes']);
      out.add(
        RagFlashcard(
          front: front,
          back: back,
          explanation: '${row['explanation'] ?? ''}'.trim(),
          citations: indexes.isEmpty
              ? citationsFromHits(retrieved.hits)
              : citationsFromChunkIndexes(retrieved.hits, indexes),
        ),
      );
    }
    return out;
  }

  Future<RagQuickRevision> quickRevision({
    required String topic,
    List<ChatMessage> history = const [],
    RagSourceFilter filter = RagSourceFilter.allPublished,
    String subjectHint = '',
    List<RagHit>? prefetchedHits,
  }) async {
    final retrieved = await _retrieveOrInsufficient(
      question: topic,
      history: history,
      filter: filter.copyWith(topK: 12),
      prefetchedHits: prefetchedHits,
    );
    if (retrieved.insufficient) {
      return const RagQuickRevision();
    }
    final payload = await _learn(
      mode: 'revision',
      question: topic,
      hits: retrieved.hits,
      history: history,
      subjectHint: subjectHint,
    );
    if (_isInsufficient(payload)) return const RagQuickRevision();
    return RagQuickRevision(
      keyFacts: asStringList(payload['keyFacts']),
      terms: asStringList(payload['terms']),
      dates: asStringList(payload['dates']),
      articles: asStringList(payload['articles']),
      committees: asStringList(payload['committees']),
      personalities: asStringList(payload['personalities']),
      examTraps: asStringList(payload['examTraps']),
      citations: _citations(retrieved.hits, payload),
    );
  }

  Future<List<RagMemoryTrick>> memoryTricks({
    required String topic,
    List<ChatMessage> history = const [],
    RagSourceFilter filter = RagSourceFilter.allPublished,
    String subjectHint = '',
    List<RagHit>? prefetchedHits,
  }) async {
    final retrieved = await _retrieveOrInsufficient(
      question: topic,
      history: history,
      filter: filter.copyWith(topK: 12),
      prefetchedHits: prefetchedHits,
    );
    if (retrieved.insufficient) return const [];
    final payload = await _learn(
      mode: 'memory',
      question: topic,
      hits: retrieved.hits,
      history: history,
      subjectHint: subjectHint,
    );
    if (_isInsufficient(payload)) return const [];
    final out = <RagMemoryTrick>[];
    for (final row in asMapList(payload['tricks'])) {
      final trick = '${row['trick'] ?? ''}'.trim();
      if (trick.isEmpty) continue;
      final indexes = parseChunkIndexes(row['chunkIndexes']);
      out.add(
        RagMemoryTrick(
          trick: trick,
          citations: indexes.isEmpty
              ? citationsFromHits(retrieved.hits)
              : citationsFromChunkIndexes(retrieved.hits, indexes),
        ),
      );
    }
    return out;
  }

  /// Real published PYQs only. Never invents a question or year.
  Future<List<RagVerifiedPyq>> pyqConnections({
    required String topic,
    List<ChatMessage> history = const [],
    RagSourceFilter filter = RagSourceFilter.allPublished,
    List<RagHit>? prefetchedHits,
  }) async {
    final retrieved = await _retrieveOrInsufficient(
      question: topic,
      history: history,
      filter: filter.copyWith(topK: 12),
      prefetchedHits: prefetchedHits,
    );
    if (retrieved.insufficient) return const [];

    final fromChunks = <RagVerifiedPyq>[];
    for (final hit in retrieved.hits) {
      if (hit.chunk.sourceType.toLowerCase() != 'pyq') continue;
      final text = hit.chunk.text.trim();
      if (text.isEmpty) continue;
      fromChunks.add(
        RagVerifiedPyq(
          question: text.length > 400 ? '${text.substring(0, 400)}…' : text,
          answer: '',
          examName: hit.chunk.sourceTitle,
          citations: [citationFromChunk(hit.chunk)],
        ),
      );
    }

    List<PyqItem> published;
    try {
      published = await _loadPublishedPyqs();
    } catch (e) {
      throw RagException.fromError(e);
    }

    final matched = <RagVerifiedPyq>[];
    for (final item in published) {
      if (!_pyqMatchesHits(item, retrieved.hits, topic)) continue;
      final question = item.isStructuredQuestion
          ? item.question.trim()
          : item.title.trim();
      if (question.isEmpty) continue;
      matched.add(
        RagVerifiedPyq(
          question: question,
          answer: item.answer.trim(),
          year: item.year,
          explanation: item.explanation.trim(),
          examName: item.examName.trim().isNotEmpty
              ? item.examName.trim()
              : item.subtitle.trim(),
          citations: [
            RagCitation(
              sourceId: item.id,
              subject: item.subject,
              chapter: '',
              topic: item.title,
              sourceType: 'pyq',
            ),
          ],
        ),
      );
    }

    final combined = [...matched, ...fromChunks];
    final seen = <String>{};
    return [
      for (final p in combined)
        if (seen.add('${p.year}|${p.question}')) p,
    ];
  }

  Future<_Retrieved> _retrieveOrInsufficient({
    required String question,
    required List<ChatMessage> history,
    required RagSourceFilter filter,
    List<RagHit>? prefetchedHits,
  }) async {
    if (prefetchedHits != null) {
      lastHits = prefetchedHits;
      if (prefetchedHits.isEmpty) {
        return const _Retrieved(hits: [], insufficient: true);
      }
      return _Retrieved(hits: prefetchedHits, insufficient: false);
    }
    final q = question.trim();
    if (q.isEmpty) throw RagException.emptyQuestion();
    try {
      final query = _retrievalQuery(q, history);
      lastHits = await _retrieval.retrieve(query: query, filter: filter);
    } catch (e) {
      throw RagException.fromError(e);
    }
    if (lastHits.isEmpty) {
      return const _Retrieved(hits: [], insufficient: true);
    }
    return _Retrieved(hits: lastHits, insufficient: false);
  }

  Future<Map<String, dynamic>> _learn({
    required String mode,
    required String question,
    required List<RagHit> hits,
    required List<ChatMessage> history,
    required String subjectHint,
  }) async {
    final chunks = <Map<String, dynamic>>[];
    for (var i = 0; i < hits.length; i++) {
      final c = hits[i].chunk;
      chunks.add({
        'index': i,
        'subject': c.subject,
        'chapter': c.chapter,
        'topic': c.sourceTitle,
        'pageNumber': c.pageNumber,
        'text': c.text,
      });
    }
    final recent = history.length > 8 ? history.sublist(history.length - 8) : history;
    try {
      return await _backend.learn({
        'mode': mode,
        'question': question.trim(),
        'teachingStyle': ragGroundedTeachingStyle(question, hint: subjectHint),
        'chunks': chunks,
        'history': [
          for (final m in recent)
            {
              'role': m.isUser ? 'user' : 'assistant',
              'content': m.content,
            },
        ],
      });
    } catch (e) {
      throw RagException.fromError(e);
    }
  }

  List<RagCitation> _citations(List<RagHit> hits, Map<String, dynamic> payload) {
    final indexes = parseChunkIndexes(payload['chunkIndexes']);
    if (indexes.isEmpty) return citationsFromHits(hits);
    return citationsFromChunkIndexes(hits, indexes);
  }

  bool _isInsufficient(Map<String, dynamic> payload) {
    final flag = payload['insufficient'];
    if (flag == true) return true;
    if (flag is String && flag.toLowerCase() == 'true') return true;
    return false;
  }

  String _retrievalQuery(String question, List<ChatMessage> history) {
    final prior = history
        .where((m) => m.isUser)
        .map((m) => m.content.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (prior.isEmpty) return question;
    final last = prior.length > 2 ? prior.sublist(prior.length - 2) : prior;
    return '${last.join(' ')} $question';
  }

  String _normalizeDifficulty(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.startsWith('hard') || t == 'कठीण') return 'Hard';
    if (t.startsWith('easy') || t == 'सोपे' || t == 'सुलभ') return 'Easy';
    return 'Medium';
  }

  bool _pyqMatchesHits(PyqItem item, List<RagHit> hits, String topic) {
    final topicLower = topic.toLowerCase();
    for (final hit in hits) {
      final c = hit.chunk;
      if (item.chapterId.isNotEmpty &&
          c.chapterId.isNotEmpty &&
          item.chapterId == c.chapterId) {
        return true;
      }
      if (item.subjectId.isNotEmpty &&
          c.subjectId.isNotEmpty &&
          item.subjectId == c.subjectId) {
        return true;
      }
      final subject = item.subject.trim().toLowerCase();
      if (subject.isNotEmpty && c.subject.trim().toLowerCase() == subject) {
        return true;
      }
      final chapter = c.chapter.trim().toLowerCase();
      if (chapter.isNotEmpty) {
        final blob =
            '${item.title} ${item.question} ${item.tags.join(' ')} ${item.subtitle}'
                .toLowerCase();
        if (blob.contains(chapter)) return true;
      }
    }
    if (topicLower.length >= 4) {
      final blob =
          '${item.title} ${item.question} ${item.tags.join(' ')} ${item.subject}'
              .toLowerCase();
      if (blob.contains(topicLower)) return true;
    }
    return false;
  }
}

class _Retrieved {
  const _Retrieved({required this.hits, required this.insufficient});

  final List<RagHit> hits;
  final bool insufficient;

  RagTeacherAnswer asTeacherAnswer() {
    return const RagTeacherAnswer(
      markdown: kRagInsufficientEvidence,
      citations: [],
      insufficient: true,
    );
  }
}

final RagGroundedLearningService ragGroundedLearningService =
    RagGroundedLearningService();
