import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/ai_backend_base.dart';
import 'package:mpsc_combine_ai/services/backend_request_headers.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Server-side extract + embed client. API keys stay in Netlify / the local
/// classroom worker — never in the Flutter bundle.
class RagBackendClient {
  RagBackendClient({
    http.Client? client,
    String? baseUrl,
    IdTokenProvider? idToken,
  })  : _client = client ?? http.Client(),
        _baseUrlOverride = baseUrl,
        _idToken = idToken;

  final http.Client _client;
  final String? _baseUrlOverride;
  final IdTokenProvider? _idToken;

  String get _base {
    final configured = (_baseUrlOverride ?? aiBackendBase()).trim();
    return configured.replaceAll(RegExp(r'/$'), '');
  }

  /// Extracts per-page text from a PDF already in Firebase Storage.
  Future<List<RagExtractedPage>> extractPdf({
    required String fileUrl,
    String title = '',
  }) async {
    if (fileUrl.trim().isEmpty) {
      throw RagException.pdfExtraction('fileUrl is empty.');
    }
    final payload = await _post('/rag/extract', {
      'fileUrl': fileUrl.trim(),
      'title': title,
    });
    return _pagesFrom(payload);
  }

  /// Embeds texts. [task] is `document` (chunks) or `query`.
  Future<List<List<double>>> embed({
    required List<String> texts,
    String task = 'document',
  }) async {
    if (texts.isEmpty) return const [];
    final payload = await _post('/rag/embed', {
      'texts': texts,
      'task': task,
    });
    final out = _embeddingsFrom(payload);
    if (out.length != texts.length) {
      throw RagException.embedding(
        'Embedding count ${out.length} != text count ${texts.length}.',
      );
    }
    for (final v in out) {
      if (v.length != kRagEmbeddingDimensions) {
        throw RagException.embedding(
          'Expected $kRagEmbeddingDimensions-d embeddings, got ${v.length}.',
        );
      }
    }
    return out;
  }

  Future<List<double>> embedQuery(String query) async {
    final rows = await embed(texts: [query], task: 'query');
    if (rows.isEmpty) {
      throw RagException.embedding('Empty query embedding.');
    }
    return rows.first;
  }

  /// Source-grounded Gemini JSON (answer / summary / MCQ / flashcards / …).
  /// API keys stay on the server. [body] must include retrieved chunk texts.
  Future<Map<String, dynamic>> learn(Map<String, dynamic> body) {
    return _post('/rag/learn', body);
  }

  /// Server-side vector retrieval. Returns null when the backend asks the
  /// client to fall back to the existing in-memory path.
  Future<RagServerRetrieveResult?> retrieveChunks({
    required String query,
    String examId = '',
    String subjectId = '',
    String chapterId = '',
    String topicId = '',
    List<String> domains = const [],
    List<String> sourceIds = const [],
    int topK = 8,
    double similarityThreshold = 0.05,
    bool hybrid = true,
  }) async {
    if (query.trim().isEmpty) {
      return const RagServerRetrieveResult(hits: []);
    }
    final payload = await _post('/rag/retrieve', {
      'query': query.trim(),
      'examId': examId,
      'subjectId': subjectId,
      'chapterId': chapterId,
      'topicId': topicId,
      'domains': domains,
      'sourceIds': sourceIds,
      'topK': topK,
      'similarityThreshold': similarityThreshold,
      'hybrid': hybrid,
    });
    if (payload['fallback'] == true) return null;
    return RagServerRetrieveResult.fromMap(payload);
  }

  List<RagExtractedPage> _pagesFrom(Map<String, dynamic> payload) {
    final error = '${payload['error'] ?? ''}'.trim();
    if (error.isNotEmpty) {
      throw RagException.pdfExtraction(error);
    }
    final pages = asMapList(payload['pages']);
    if (pages.isEmpty) {
      final text = '${payload['text'] ?? ''}'.trim();
      if (text.isEmpty) throw RagException.emptyDoc();
      return [RagExtractedPage(text: text)];
    }
    final out = <RagExtractedPage>[];
    for (final p in pages) {
      final text = '${p['text'] ?? ''}'.trim();
      if (text.isEmpty) continue;
      final rawPage = p['page'] ?? p['pageNumber'];
      int? pageNumber;
      if (rawPage is num) {
        final n = rawPage.toInt();
        pageNumber = n >= 1 ? n : null;
      }
      out.add(RagExtractedPage(pageNumber: pageNumber, text: text));
    }
    if (out.isEmpty) throw RagException.emptyDoc();
    return out;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$_base$path');
    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: await backendJsonHeaders(idToken: _idToken),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 180));
    } catch (e) {
      throw RagException.fromError(e);
    }
    Map<String, dynamic> decoded;
    try {
      final raw = jsonDecode(response.body);
      decoded = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{'error': response.body};
    } catch (_) {
      throw RagException.gemini(
        'Backend returned a non-JSON response (HTTP ${response.statusCode}).',
      );
    }
    if (response.statusCode != 200) {
      final err = '${decoded['error'] ?? 'HTTP ${response.statusCode}'}'.trim();
      throw RagException.fromError(err);
    }
    return decoded;
  }

  /// Vertex-only embed. Throws when Vertex is unavailable so callers
  /// can fall back to [embed] (existing Gemini Developer API).
  Future<List<List<double>>> vertexEmbed({
    required List<String> texts,
    String task = 'document',
  }) async {
    if (texts.isEmpty) return const [];
    final payload = await _post('/rag/vertex-embed', {
      'texts': texts,
      'task': task,
    });
    final out = _embeddingsFrom(payload);
    if (out.length != texts.length) {
      throw RagException.embedding(
        'Vertex embedding count ${out.length} != text count ${texts.length}.',
      );
    }
    for (final v in out) {
      if (v.length != kRagEmbeddingDimensions) {
        throw RagException.embedding(
          'Expected $kRagEmbeddingDimensions-d Vertex embeddings, got ${v.length}.',
        );
      }
    }
    return out;
  }

  Future<List<double>> vertexEmbedQuery(String query) async {
    final rows = await vertexEmbed(texts: [query], task: 'query');
    if (rows.isEmpty) {
      throw RagException.embedding('Empty Vertex query embedding.');
    }
    return rows.first;
  }

  /// Vertex-only grounded generation. Throws when Vertex is unavailable.
  Future<Map<String, dynamic>> vertexLearn(Map<String, dynamic> body) {
    return _post('/rag/vertex-learn', body);
  }

  List<List<double>> _embeddingsFrom(Map<String, dynamic> payload) {
    final raw = payload['embeddings'];
    if (raw is! List) {
      throw RagException.embedding('Backend returned no embeddings.');
    }
    final out = <List<double>>[];
    for (final row in raw) {
      if (row is! List) {
        throw RagException.embedding('Malformed embedding row.');
      }
      out.add([
        for (final n in row) (n as num).toDouble(),
      ]);
    }
    return out;
  }
}

final RagBackendClient ragBackendClient = RagBackendClient();

/// Top-K payload from `/rag/retrieve`. Chunk embeddings are omitted.
class RagServerRetrieveResult {
  const RagServerRetrieveResult({
    required this.hits,
    this.embeddingProvider = '',
    this.vectorIndex = '',
    this.embeddingModel = '',
    this.embeddingDimensions = kRagEmbeddingDimensions,
  });

  final List<Map<String, dynamic>> hits;
  final String embeddingProvider;
  final String vectorIndex;
  final String embeddingModel;
  final int embeddingDimensions;

  factory RagServerRetrieveResult.fromMap(Map<String, dynamic> map) {
    final rows = map['hits'];
    final hits = <Map<String, dynamic>>[];
    if (rows is List) {
      for (final row in rows) {
        if (row is Map) hits.add(Map<String, dynamic>.from(row));
      }
    }
    return RagServerRetrieveResult(
      hits: hits,
      embeddingProvider: '${map['embeddingProvider'] ?? ''}',
      vectorIndex: '${map['vectorIndex'] ?? ''}',
      embeddingModel: '${map['embeddingModel'] ?? ''}',
      embeddingDimensions:
          (map['embeddingDimensions'] as num?)?.toInt() ??
              kRagEmbeddingDimensions,
    );
  }
}
