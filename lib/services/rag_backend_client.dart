import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';
import 'package:mpsc_combine_ai/rag/rag_pdf_page_image.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/ai_backend_base.dart';
import 'package:mpsc_combine_ai/services/backend_request_headers.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// PDF extract can run many Gemini OCR calls. Fail instead of leaving
/// Admin on Processing forever.
const Duration kRagExtractTimeout = Duration(minutes: 10);

/// Server-side extract + embed client. API keys stay in Netlify / the local
/// classroom worker — never in the Flutter bundle.
class RagBackendClient {
  RagBackendClient({
    http.Client? client,
    String? baseUrl,
    this.idToken,
  })  : _client = client ?? http.Client(),
        _baseUrlOverride = baseUrl;

  final http.Client _client;
  final String? _baseUrlOverride;
  final IdTokenProvider? idToken;

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
    final payload = await _post(
      '/rag/extract',
      {
        'fileUrl': fileUrl.trim(),
        'title': title,
      },
      timeout: kRagExtractTimeout,
    );
    return _pagesFrom(payload);
  }

  /// Image-OCR extract used only after PDF-bytes text looks corrupted.
  Future<List<RagExtractedPage>> extractPdfPageImages({
    required List<RagPdfPageImage> images,
    String title = '',
    String fileUrl = '',
  }) async {
    if (images.isEmpty) {
      throw RagException.emptyDoc();
    }
    final payload = await _post(
      '/rag/extract',
      {
        if (fileUrl.trim().isNotEmpty) 'fileUrl': fileUrl.trim(),
        'title': title,
        'pageImages': [for (final image in images) image.toJson()],
      },
      timeout: kRagExtractTimeout,
    );
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

  bool get _mayFallbackToProduction =>
      _baseUrlOverride == null && isLoopbackAiBackend(_base);

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout = const Duration(seconds: 180),
  }) async {
    final headers = await backendJsonHeaders(idToken: idToken);
    final localDebugRag = kDebugMode &&
        (path == '/rag/extract' ||
            path == '/rag/embed' ||
            path == '/rag/learn' ||
            path == '/rag/retrieve');
    final bases = (_baseUrlOverride == null &&
            kDebugMode &&
            kIsWeb &&
            localDebugRag)
        ? lessonBackendBases()
        : [_base];
    Object? lastUnreachable;
    for (var i = 0; i < bases.length; i++) {
      try {
        return await _postTo(
          bases[i],
          path,
          body,
          headers: headers,
          allowProductionFallback: !localDebugRag,
          timeout: timeout,
        );
      } catch (e) {
        lastUnreachable = e;
        final more = i + 1 < bases.length;
        if (more && _isUnreachableBackend(e)) continue;
        rethrow;
      }
    }
    throw RagException.fromError(lastUnreachable ?? 'network error');
  }

  Future<Map<String, dynamic>> _postTo(
    String base,
    String path,
    Map<String, dynamic> body, {
    required Map<String, String> headers,
    required bool allowProductionFallback,
    Duration? timeout = const Duration(seconds: 180),
  }) async {
    final uri = Uri.parse('$base$path');
    http.Response response;
    try {
      final sent = _client.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
      response = timeout == null ? await sent : await sent.timeout(timeout);
    } catch (e) {
      if (allowProductionFallback &&
          _mayFallbackToProduction &&
          _isUnreachableBackend(e)) {
        return _postTo(
          kProductionAiBackendOrigin,
          path,
          body,
          headers: headers,
          allowProductionFallback: false,
          timeout: timeout,
        );
      }
      throw RagException.fromError(
        _unreachableMessage(base, path, e),
      );
    }
    Map<String, dynamic> decoded;
    try {
      final raw = jsonDecode(response.body);
      decoded = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{'error': response.body};
    } catch (_) {
      throw RagException.fromError(
        'HTTP ${response.statusCode} $base$path returned a non-JSON body: '
        '${response.body}',
      );
    }
    if (response.statusCode != 200) {
      final err = '${decoded['error'] ?? ''}'.trim();
      final snippet = err.isNotEmpty ? err : response.body.trim();
      throw RagException.fromError(
        'HTTP ${response.statusCode} $base$path: $snippet',
      );
    }
    return decoded;
  }

  Object _unreachableMessage(String base, String path, Object error) {
    if (!isLoopbackAiBackend(base)) return error;
    return 'Could not reach the RAG backend at $base$path. '
        'Start the local classroom worker, or use the production Student '
        'functions at $kProductionAiBackendOrigin. Original error: $error';
  }

  bool _isUnreachableBackend(Object error) {
    final lower = '$error'.toLowerCase();
    return lower.contains('failed to fetch') ||
        lower.contains('clientexception') ||
        lower.contains('socket') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('failed host lookup') ||
        lower.contains('xmlhttprequest');
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
