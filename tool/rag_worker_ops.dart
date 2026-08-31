import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/gemini_rest_client.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Local-worker RAG extract/embed (same contract as Netlify `/rag/*`).
class RagWorkerOps {
  RagWorkerOps({required this.apiKey, required this.model, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  static const _embedModel = 'gemini-embedding-001';
  static const _maxPdfBytes = 8 * 1024 * 1024;

  Future<Map<String, dynamic>> embed({
    required List<String> texts,
    String task = 'document',
  }) async {
    if (texts.isEmpty) {
      throw StateError('texts required');
    }
    final taskType =
        task == 'query' ? 'RETRIEVAL_QUERY' : 'RETRIEVAL_DOCUMENT';
    final embeddings = <List<double>>[];
    const batchSize = 16;
    for (var i = 0; i < texts.length; i += batchSize) {
      final slice = texts.sublist(
        i,
        i + batchSize > texts.length ? texts.length : i + batchSize,
      );
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_embedModel:embedContent',
      );
      for (final text in slice) {
        final clipped = text.length > 8000 ? text.substring(0, 8000) : text;
        final response = await _client
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'x-goog-api-key': apiKey,
              },
              body: jsonEncode({
                'content': {
                  'parts': [
                    {'text': clipped},
                  ],
                },
                'taskType': taskType,
                'outputDimensionality': kRagEmbeddingDimensions,
              }),
            )
            .timeout(const Duration(seconds: 60));
        if (response.statusCode != 200) {
          final snippet = response.body.length > 400
              ? '${response.body.substring(0, 400)}…'
              : response.body;
          throw GeminiApiException(
            'embedding failure HTTP ${response.statusCode}: $snippet',
            statusCode: response.statusCode,
          );
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          throw const GeminiApiException('embedding failure');
        }
        final embedding = decoded['embedding'];
        final values = embedding is Map ? embedding['values'] : null;
        if (values is! List) {
          throw const GeminiApiException('embedding failure');
        }
        embeddings.add([for (final n in values) (n as num).toDouble()]);
      }
    }
    return {'embeddings': embeddings};
  }

  Future<Map<String, dynamic>> extractPdf({
    required String fileUrl,
    String title = '',
  }) async {
    final response = await _client.get(Uri.parse(fileUrl)).timeout(
          const Duration(seconds: 60),
        );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('PDF extraction failed: download HTTP ${response.statusCode}');
    }
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw StateError('empty document');
    }
    if (bytes.length > _maxPdfBytes) {
      throw StateError('PDF extraction failed: file is larger than 8 MB');
    }
    return extractPdfBytes(bytes: bytes, title: title);
  }

  Future<Map<String, dynamic>> extractPdfBytes({
    required Uint8List bytes,
    String title = '',
  }) async {
    final gemini = GeminiRestClient(
      apiKey: apiKey,
      model: model,
      client: _client,
    );
    final prompt =
        'Extract ALL text from this MPSC study PDF.\n'
        'Return ONE JSON object only: {"pages":[{"page":1,"text":"..."}]}.\n'
        '"page" MUST be the 1-based index of the actual PDF file page you extracted.\n'
        'If you cannot observe real page boundaries, return '
        '{"pages":[{"text":"<full text>"}]} with NO page field — never guess a page number.\n'
        'Preserve Marathi (Devanagari) exactly. Do not translate. Do not invent facts.\n'
        'Title hint: ${title.isEmpty ? '(none)' : title}';
    final map = await gemini.generateJsonFromParts(
      systemPrompt:
          'You extract PDF text for RAG. JSON only. Never invent page numbers.',
      userParts: [
        {'text': prompt},
        {
          'inline_data': {
            'mime_type': 'application/pdf',
            'data': base64Encode(bytes),
          },
        },
      ],
      temperature: 0.1,
      maxOutputTokens: 8192,
    );
    final pages = asMapList(map['pages']);
    final cleaned = <Map<String, dynamic>>[];
    for (final p in pages) {
      final text = '${p['text'] ?? ''}'.trim();
      if (text.isEmpty) continue;
      final page = p['page'];
      if (page is num && page.toInt() >= 1) {
        cleaned.add({'page': page.toInt(), 'text': text});
      } else {
        cleaned.add({'text': text});
      }
    }
    if (cleaned.isEmpty) {
      final blob = '${map['text'] ?? ''}'.trim();
      if (blob.isEmpty) throw StateError('empty document');
      cleaned.add({'text': blob});
    }
    return {'pages': cleaned};
  }

  Future<Map<String, dynamic>> learn({
    required String mode,
    required String question,
    required List<dynamic> chunks,
    List<dynamic> history = const [],
    String teachingStyle = '',
  }) async {
    final q = question.trim();
    if (q.isEmpty) {
      throw const GeminiApiException('question required');
    }
    if (chunks.isEmpty) {
      return {'insufficient': true, 'answer': ''};
    }
    final allowed = {
      'answer',
      'summary',
      'mcq',
      'flashcards',
      'revision',
      'memory',
    };
    final m = allowed.contains(mode) ? mode : 'answer';
    final gemini = GeminiRestClient(
      apiKey: apiKey,
      model: model,
      client: _client,
    );
    return gemini.generateJson(
      systemPrompt: _learnSystemPrompt(m, teachingStyle),
      userText: _learnUserText(
        mode: m,
        question: q,
        chunks: chunks,
        history: history,
      ),
      temperature: 0.25,
    );
  }
}

String _learnSystemPrompt(String mode, String teachingStyle) {
  return 'You are a grounded MPSC Combined Group B/C AI Teacher.\n'
      'Retrieved numbered chunks are PRIMARY EVIDENCE. The app will attach citations from chunk indexes.\n'
      'HARD RULES:\n'
      '- Use only facts supported by the numbered chunks.\n'
      '- Never invent sources, citations, page numbers, PYQs, years, article numbers, dates, committees, or personalities.\n'
      '- If the chunks do not contain enough information, set insufficient=true and leave content empty.\n'
      '- Do NOT write a Sources section or page numbers in the text. Return chunkIndexes instead.\n'
      '- If the student question uses Devanagari, answer in natural Marathi. Otherwise English.\n'
      '- Explain step-by-step with MPSC exam-oriented examples drawn from the chunks.\n'
      '- If the student asks to compare topics, use a Markdown table from chunk facts only.\n'
      '- Memory tricks must not change the meaning of source facts.\n'
      '- MCQ difficulty must be exactly Easy, Medium, or Hard.\n'
      '- chunkIndexes must be integers from the provided chunk list only.\n'
      '$teachingStyle\n'
      'Mode: $mode';
}

String _learnUserText({
  required String mode,
  required String question,
  required List<dynamic> chunks,
  required List<dynamic> history,
}) {
  final chunkBlock = <String>[];
  for (var i = 0; i < chunks.length; i++) {
    final c = chunks[i];
    if (c is! Map) continue;
    final idx = c['index'] is num ? (c['index'] as num).toInt() : i;
    final page = c['pageNumber'];
    final pageLabel =
        page is num && page.toInt() >= 1 ? ' page=${page.toInt()}' : ' page=unknown';
    chunkBlock.add(
      '[$idx] subject=${c['subject'] ?? ''} chapter=${c['chapter'] ?? ''} '
      'topic=${c['topic'] ?? ''}$pageLabel\n${c['text'] ?? ''}',
    );
  }
  final hist = history.map((m) {
    if (m is! Map) return '';
    final role = '${m['role'] ?? ''}' == 'user' ? 'Student' : 'Teacher';
    return '$role: ${m['content'] ?? ''}';
  }).where((s) => s.isNotEmpty).join('\n');
  const schemas = {
    'answer':
        '{"insufficient":boolean,"answer":string,"chunkIndexes":number[]}',
    'summary':
        '{"insufficient":boolean,"detailed":string,"shortNotes":string,"fiveMinuteRevision":string,"importantFacts":string[],"examPoints":string[],"commonMistakes":string[],"chunkIndexes":number[]}',
    'mcq':
        '{"insufficient":boolean,"questions":[{"question":string,"options":[string,string,string,string],"correctIndex":0,"explanation":string,"difficulty":"Easy|Medium|Hard","topic":string,"chunkIndexes":number[]}]}',
    'flashcards':
        '{"insufficient":boolean,"cards":[{"front":string,"back":string,"explanation":string,"chunkIndexes":number[]}]}',
    'revision':
        '{"insufficient":boolean,"keyFacts":string[],"terms":string[],"dates":string[],"articles":string[],"committees":string[],"personalities":string[],"examTraps":string[],"chunkIndexes":number[]}',
    'memory':
        '{"insufficient":boolean,"tricks":[{"trick":string,"chunkIndexes":number[]}]}',
  };
  return 'Student question:\n$question\n\n'
      'Recent chat (for pronouns / follow-ups only; do not invent facts from it):\n'
      '${hist.isEmpty ? '(none)' : hist}\n\n'
      'Retrieved chunks:\n${chunkBlock.isEmpty ? '(none)' : chunkBlock.join('\n\n')}\n\n'
      'Return ONE JSON object matching:\n${schemas[mode] ?? '{"insufficient":boolean}'}';
}
