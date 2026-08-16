import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/utils/ai_generation_error.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Classified Gemini REST failure. [message] is safe to show in development.
class GeminiApiException implements Exception {
  const GeminiApiException(this.message, {this.statusCode, this.model});

  final String message;
  final int? statusCode;
  final String? model;

  @override
  String toString() => message;
}

/// Google Gemini generateContent helper with no Flutter/Firebase imports.
class GeminiRestClient {
  GeminiRestClient({
    required this.apiKey,
    this.model = 'gemini-flash-lite-latest',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Live models that currently accept generateContent for this API key.
  /// Older ids such as gemini-2.0-flash return 404 for new projects.
  static const List<String> fallbackModels = [
    'gemini-flash-lite-latest',
    'gemini-pro-latest',
    'gemini-3.1-flash-lite',
    'gemini-3.5-flash',
    'gemini-3-flash-preview',
  ];

  Future<Map<String, dynamic>> generateJson({
    required String systemPrompt,
    required String userText,
    double temperature = 0.35,
    int maxOutputTokens = 8192,
  }) {
    return generateJsonFromParts(
      systemPrompt: systemPrompt,
      userParts: [
        {'text': userText},
      ],
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
    );
  }

  Future<Map<String, dynamic>> generateJsonFromParts({
    required String systemPrompt,
    required List<Map<String, dynamic>> userParts,
    double temperature = 0.35,
    int maxOutputTokens = 8192,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const GeminiApiException('Gemini API key missing');
    }
    final models = <String>[
      if (model.trim().isNotEmpty) model.trim(),
      ...fallbackModels,
    ];
    final tried = <String>{};
    Object? lastError;
    for (final candidate in models) {
      if (!tried.add(candidate)) continue;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          return await _postJson(
            modelName: candidate,
            systemPrompt: systemPrompt,
            userParts: userParts,
            temperature: temperature,
            maxOutputTokens: maxOutputTokens,
          );
        } on GeminiApiException catch (e) {
          lastError = e;
          final overloaded = e.statusCode == 503 ||
              e.message == 'network error' ||
              e.message == 'quota exceeded';
          final missingModel = e.message == 'model not found';
          if (overloaded && attempt == 0) {
            await Future<void>.delayed(const Duration(seconds: 2));
            continue;
          }
          if (overloaded || missingModel) break;
          rethrow;
        } catch (e) {
          lastError = e;
          final classified = classifyAiGenerationFailure(e);
          if (classified == 'network error' && attempt == 0) {
            await Future<void>.delayed(const Duration(seconds: 2));
            continue;
          }
          throw GeminiApiException(classified);
        }
      }
    }
    final leftover = lastError;
    if (leftover is GeminiApiException) throw leftover;
    throw GeminiApiException(classifyAiGenerationFailure(leftover ?? 'invalid request'));
  }

  Future<Map<String, dynamic>> _postJson({
    required String modelName,
    required String systemPrompt,
    required List<Map<String, dynamic>> userParts,
    required double temperature,
    required int maxOutputTokens,
  }) async {
    final uri = Uri.parse('$_baseUrl/$modelName:generateContent');
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': userParts,
        },
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'temperature': temperature,
        'maxOutputTokens': maxOutputTokens,
      },
    });

    print('[AI-CHAPTER] gemini_request_started model=$modelName');
    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 180));
    } on TimeoutException {
      throw GeminiApiException(
        'network error',
        statusCode: 408,
        model: modelName,
      );
    } catch (e) {
      throw GeminiApiException(
        classifyAiGenerationFailure(e),
        model: modelName,
      );
    }

    if (response.statusCode != 200) {
      final classified = _classifyHttp(response.statusCode, response.body);
      print(
        '[AI-CHAPTER] gemini_http status=${response.statusCode} '
        'model=$modelName reason=$classified',
      );
      throw GeminiApiException(
        classified,
        statusCode: response.statusCode,
        model: modelName,
      );
    }
    print(
      '[AI-CHAPTER] gemini_http status=${response.statusCode} model=$modelName',
    );

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = asMapList(decoded['candidates']);
    final firstCandidate = candidates.isNotEmpty ? candidates.first : null;
    final content = firstCandidate?['content'];
    final contentMap =
        content is Map ? Map<String, dynamic>.from(content) : null;
    final parts = asMapList(contentMap?['parts']);
    final text = parts.isNotEmpty ? parts.first['text'] as String? : null;
    if (text == null || text.trim().isEmpty) {
      throw GeminiApiException(
        'response parsing error',
        model: modelName,
      );
    }
    print(
      '[AI-CHAPTER] gemini_response_received model=$modelName chars=${text.trim().length}',
    );

    var jsonText = text.trim();
    final decodedMap = tryDecodeJsonObject(jsonText);
    if (decodedMap == null) {
      print(
        '[AI-CHAPTER] response_parsing failure '
        'finishReason=${firstCandidate?['finishReason']} chars=${jsonText.length}',
      );
      throw const GeminiApiException('response parsing error');
    }
    print(
      '[AI-CHAPTER] response_parsing success keys=${decodedMap.keys.join(',')}',
    );
    return decodedMap;
  }

  Future<String> generateText({
    required String systemPrompt,
    required String userText,
    List<Map<String, dynamic>> history = const [],
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const GeminiApiException('Gemini API key missing');
    }
    final models = <String>[
      if (model.trim().isNotEmpty) model.trim(),
      ...fallbackModels,
    ];
    final tried = <String>{};
    Object? lastError;
    for (final candidate in models) {
      if (!tried.add(candidate)) continue;
      try {
        return await _postText(
          modelName: candidate,
          systemPrompt: systemPrompt,
          userText: userText,
          history: history,
        );
      } on GeminiApiException catch (e) {
        lastError = e;
        final retry = e.message == 'model not found' ||
            e.message == 'network error' ||
            e.message == 'quota exceeded' ||
            e.statusCode == 503;
        if (retry) continue;
        rethrow;
      }
    }
    final leftover = lastError;
    if (leftover is GeminiApiException) throw leftover;
    throw GeminiApiException(classifyAiGenerationFailure(leftover ?? 'invalid request'));
  }

  Future<String> _postText({
    required String modelName,
    required String systemPrompt,
    required String userText,
    required List<Map<String, dynamic>> history,
  }) async {
    final uri = Uri.parse('$_baseUrl/$modelName:generateContent');
    final contents = [
      ...history,
      {
        'role': 'user',
        'parts': [
          {'text': userText},
        ],
      },
    ];
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'contents': contents,
    });
    print('[AI-CHAPTER] gemini_request_started model=$modelName');
    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw GeminiApiException(
        'network error',
        statusCode: 408,
        model: modelName,
      );
    } catch (e) {
      throw GeminiApiException(
        classifyAiGenerationFailure(e),
        model: modelName,
      );
    }
    if (response.statusCode != 200) {
      final classified = _classifyHttp(response.statusCode, response.body);
      print(
        '[AI-CHAPTER] gemini_http status=${response.statusCode} '
        'model=$modelName reason=$classified',
      );
      throw GeminiApiException(
        classified,
        statusCode: response.statusCode,
        model: modelName,
      );
    }
    print(
      '[AI-CHAPTER] gemini_http status=${response.statusCode} model=$modelName',
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = asMapList(decoded['candidates']);
    final firstCandidate = candidates.isNotEmpty ? candidates.first : null;
    final content = firstCandidate?['content'];
    final contentMap =
        content is Map ? Map<String, dynamic>.from(content) : null;
    final parts = asMapList(contentMap?['parts']);
    final text = parts.isNotEmpty ? parts.first['text'] as String? : null;
    if (text == null || text.trim().isEmpty) {
      throw GeminiApiException(
        'response parsing error',
        model: modelName,
      );
    }
    return text.trim();
  }

  static String _classifyHttp(int statusCode, String body) {
    final lower = body.toLowerCase();
    String statusName = '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        statusName = '${(decoded['error'] as Map)['status']}'.toUpperCase();
      }
    } catch (_) {}
    if (statusCode == 401 ||
        statusCode == 403 ||
        statusName.contains('PERMISSION') ||
        lower.contains('api_key_invalid') ||
        lower.contains('unauth')) {
      return 'Gemini API unauthorized';
    }
    if (statusCode == 404 ||
        statusName.contains('NOT_FOUND') ||
        lower.contains('not found') ||
        lower.contains('no longer available')) {
      return 'model not found';
    }
    if (statusCode == 429 ||
        statusName.contains('RESOURCE_EXHAUSTED') ||
        lower.contains('quota')) {
      return 'quota exceeded';
    }
    if (statusCode == 400 || statusName.contains('INVALID_ARGUMENT')) {
      return 'invalid request';
    }
    if (statusCode == 503 ||
        statusName.contains('UNAVAILABLE') ||
        lower.contains('high demand')) {
      return 'network error';
    }
    return classifyAiGenerationFailure('HTTP $statusCode $body');
  }
}

/// Pulls the first JSON object out of a model reply that may include
/// markdown fences or leading/trailing prose.
Map<String, dynamic>? tryDecodeJsonObject(String raw) {
  var jsonText = raw.trim();
  if (jsonText.startsWith('```')) {
    jsonText = jsonText.substring(3);
    final langBreak = jsonText.indexOf('\n');
    if (langBreak != -1 && langBreak < 12) {
      jsonText = jsonText.substring(langBreak + 1);
    }
  }
  if (jsonText.endsWith('```')) {
    jsonText = jsonText.substring(0, jsonText.length - 3);
  }
  jsonText = jsonText.trim();
  final start = jsonText.indexOf('{');
  if (start < 0) return null;
  jsonText = jsonText.substring(start);
  return _decodeMap(jsonText) ??
      _decodeMap(_closeJson(jsonText)) ??
      _decodeMap(_closeJson(_trimIncompleteTail(jsonText)));
}

Map<String, dynamic>? _decodeMap(String jsonText) {
  try {
    final map = jsonDecode(jsonText);
    if (map is Map<String, dynamic>) return map;
    if (map is Map) return Map<String, dynamic>.from(map);
  } catch (_) {}
  return null;
}

String _trimIncompleteTail(String s) {
  for (var i = s.length - 1; i >= 0; i--) {
    final c = s[i];
    if (c == '}' || c == ']') {
      return s.substring(0, i + 1);
    }
  }
  return s;
}

String _closeJson(String raw) {
  var s = raw.trimRight();
  while (s.endsWith(',') || s.endsWith(':')) {
    s = s.substring(0, s.length - 1).trimRight();
  }
  var braces = 0;
  var brackets = 0;
  var inStr = false;
  var escape = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inStr) {
      if (escape) {
        escape = false;
        continue;
      }
      if (c == '\\') {
        escape = true;
        continue;
      }
      if (c == '"') inStr = false;
      continue;
    }
    if (c == '"') {
      inStr = true;
      continue;
    }
    if (c == '{') braces++;
    if (c == '}') braces--;
    if (c == '[') brackets++;
    if (c == ']') brackets--;
  }
  if (inStr) s = '$s"';
  while (brackets > 0) {
    s = '$s]';
    brackets--;
  }
  while (braces > 0) {
    s = '$s}';
    braces--;
  }
  return s;
}
