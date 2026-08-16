import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'package:mpsc_combine_ai/services/ai_video_render/marathi_ssml_converter.dart';

import 'tts_io_stub.dart' if (dart.library.io) 'tts_io_impl.dart' as tts_io;

/// Exact failure from Google Cloud Text-to-Speech (never a vague "Try again").
class GoogleCloudTtsException implements Exception {
  const GoogleCloudTtsException({
    required this.message,
    this.statusCode,
    this.body,
  });

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => displayMessage;

  String get displayMessage {
    final buf = StringBuffer(message);
    if (statusCode != null) buf.write(' (HTTP $statusCode)');
    if (body != null && body!.trim().isNotEmpty) {
      buf.write('\n');
      buf.write(body!.length > 500 ? '${body!.substring(0, 500)}…' : body);
    }
    return buf.toString();
  }
}

/// Result of a synthesis call — raw MP3 bytes plus optional on-disk path.
class TtsAudioClip {
  const TtsAudioClip({
    required this.bytes,
    required this.languageCode,
    required this.voiceName,
    required this.cacheKey,
    this.filePath,
  });

  final Uint8List bytes;
  final String languageCode;
  final String voiceName;
  final String cacheKey;
  final String? filePath;
}

/// Google Cloud Text-to-Speech REST client for AI Classroom narration.
///
/// Prefer this over Gemini TTS: Cloud TTS has stable `mr-IN` WaveNet voices,
/// SSML prosody, and works with a GCP service account already used here.
/// Gemini/`AI_API_KEY` alone is not sufficient for Cloud TTS (OAuth required).
///
/// Auth (compile-time / env), in order:
/// 1. `TTS_ACCESS_TOKEN` — short-lived Bearer token
/// 2. `TTS_SERVICE_ACCOUNT_JSON` — full service-account JSON string
/// 3. `TTS_SERVICE_ACCOUNT_PATH` — path to service-account JSON file
/// 4. `GOOGLE_APPLICATION_CREDENTIALS` — standard ADC path (native only)
/// 5. `GOOGLE_TTS_API_KEY` / `TTS_API_KEY` — API key (web-friendly; restrict by
///    HTTP referrer in GCP Console). `AI_API_KEY` is tried last and usually
///    rejected (Gemini AI Studio keys return HTTP 401).
///
/// Optional voice overrides:
/// - `GOOGLE_TTS_LANGUAGE_CODE` (default `mr-IN` / `en-IN` by script)
/// - `GOOGLE_TTS_VOICE_NAME` (default `mr-IN-Wavenet-A` / `en-IN-Wavenet-A`)
///
/// Audio is cached under app documents/`tts_cache` (native) or memory (web).
class GoogleCloudTtsService {
  GoogleCloudTtsService({http.Client? client})
      : _fallbackClient = client ?? http.Client();

  final http.Client _fallbackClient;
  AutoRefreshingAuthClient? _saClient;

  static const String _googleTtsKey =
      String.fromEnvironment('GOOGLE_TTS_API_KEY');
  static const String _ttsKey = String.fromEnvironment('TTS_API_KEY');
  static const String _aiKey = String.fromEnvironment('AI_API_KEY');
  static const String _accessToken = String.fromEnvironment('TTS_ACCESS_TOKEN');
  static const String _saJson =
      String.fromEnvironment('TTS_SERVICE_ACCOUNT_JSON');
  static const String _saPath =
      String.fromEnvironment('TTS_SERVICE_ACCOUNT_PATH');
  static const String _voiceOverride =
      String.fromEnvironment('GOOGLE_TTS_VOICE_NAME');
  static const String _langOverride =
      String.fromEnvironment('GOOGLE_TTS_LANGUAGE_CODE');

  static const String _endpoint =
      'https://texttospeech.googleapis.com/v1/text:synthesize';
  static const List<String> _scopes = <String>[
    'https://www.googleapis.com/auth/cloud-platform',
  ];

  /// Gentle classroom pace (~0.85–0.95). Player may still adjust speed.
  static const double defaultSpeakingRate = 0.95;

  /// Cloud TTS input limit is ~5000 bytes; stay under with UTF-8 Marathi.
  static const int maxChunkChars = 4200;

  static const int maxRetries = 3;
  /// Soft RAM cap for in-memory MP3 clips (~classroom < 1.2 GB target).
  static const int maxMemoryClips = 4;

  /// Best available Marathi neural female voice (WaveNet; no Neural2/Chirp3 for mr-IN).
  static const String defaultMarathiVoice = 'mr-IN-Wavenet-A';
  static const String defaultEnglishVoice = 'en-IN-Wavenet-A';
  static const String defaultMarathiLang = 'mr-IN';
  static const String defaultEnglishLang = 'en-IN';

  final Map<String, Uint8List> _memoryCache = {};
  final List<String> _memoryOrder = [];

  String get _apiKey {
    if (_googleTtsKey.trim().isNotEmpty) return _googleTtsKey.trim();
    if (_ttsKey.trim().isNotEmpty) return _ttsKey.trim();
    return _aiKey.trim();
  }

  bool get isConfigured =>
      _accessToken.isNotEmpty ||
      _saJson.isNotEmpty ||
      _saPath.isNotEmpty ||
      tts_io.ttsHasEnvironmentCredentials ||
      _apiKey.isNotEmpty;

  /// Attempt Cloud TTS when credentials are present (no paid opt-in flag).
  bool get isEnabled => isConfigured;

  /// Transient failures worth retrying with backoff.
  static bool isRetryableStatus(int? statusCode) {
    if (statusCode == null) return true; // network / timeout
    return statusCode == 408 ||
        statusCode == 429 ||
        statusCode == 500 ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504;
  }

  /// Auth / quota / permanent failures → fall back to free TTS for the session.
  static bool isFallbackStatus(int? statusCode) {
    if (statusCode == null) return false;
    return statusCode == 401 ||
        statusCode == 402 ||
        statusCode == 403 ||
        statusCode == 404;
  }

  static bool isFallbackException(GoogleCloudTtsException e) {
    if (isFallbackStatus(e.statusCode)) return true;
    final blob = '${e.message} ${e.body ?? ''}'.toLowerCase();
    return blob.contains('quota') ||
        blob.contains('permission') ||
        blob.contains('billing') ||
        blob.contains('api key') ||
        blob.contains('credentials are missing') ||
        blob.contains('authentication failed') ||
        blob.contains('not been used') ||
        blob.contains('disabled');
  }

  /// Picks mr-IN vs en-IN from script detection (overridable via dart-defines).
  ({String languageCode, String voiceName}) voiceFor(String text) {
    final isMarathi = RegExp(r'[\u0900-\u097F]').hasMatch(text);
    final lang = _langOverride.trim().isNotEmpty
        ? _langOverride.trim()
        : (isMarathi ? defaultMarathiLang : defaultEnglishLang);
    final voice = _voiceOverride.trim().isNotEmpty
        ? _voiceOverride.trim()
        : (isMarathi ? defaultMarathiVoice : defaultEnglishVoice);
    return (languageCode: lang, voiceName: voice);
  }

  /// Split long lessons at sentence boundaries for API limits.
  static List<String> chunkForApi(
    String text, {
    int maxChars = maxChunkChars,
  }) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return const [];
    if (cleaned.length <= maxChars) return [cleaned];

    final sentences = cleaned
        .split(RegExp(r'(?<=[।.?!…])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (sentences.isEmpty) {
      final out = <String>[];
      for (var i = 0; i < cleaned.length; i += maxChars) {
        final end = (i + maxChars > cleaned.length) ? cleaned.length : i + maxChars;
        out.add(cleaned.substring(i, end));
      }
      return out;
    }

    final chunks = <String>[];
    final buf = StringBuffer();
    for (final s in sentences) {
      final next = buf.isEmpty ? s : '${buf.toString()} $s';
      if (next.length > maxChars && buf.isNotEmpty) {
        chunks.add(buf.toString().trim());
        buf
          ..clear()
          ..write(s);
        // Hard-split an oversized single sentence.
        while (buf.length > maxChars) {
          chunks.add(buf.toString().substring(0, maxChars));
          final rest = buf.toString().substring(maxChars);
          buf
            ..clear()
            ..write(rest);
        }
      } else {
        buf
          ..clear()
          ..write(next);
      }
    }
    final last = buf.toString().trim();
    if (last.isNotEmpty) chunks.add(last);
    return chunks;
  }

  String cacheKeyFor(
    String text,
    String languageCode,
    String voiceName,
    double speakingRate,
  ) {
    final material =
        '$languageCode|$voiceName|${speakingRate.toStringAsFixed(2)}|ssml|${text.trim()}';
    return sha256.convert(utf8.encode(material)).toString().substring(0, 32);
  }

  void _remember(String key, Uint8List bytes) {
    _memoryCache[key] = bytes;
    _memoryOrder.remove(key);
    _memoryOrder.add(key);
    while (_memoryOrder.length > maxMemoryClips) {
      final evict = _memoryOrder.removeAt(0);
      _memoryCache.remove(evict);
    }
  }

  Future<TtsAudioClip?> readCache(
    String text, {
    double speakingRate = defaultSpeakingRate,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final voice = voiceFor(trimmed);
    final key = cacheKeyFor(
      trimmed,
      voice.languageCode,
      voice.voiceName,
      speakingRate,
    );
    final mem = _memoryCache[key];
    if (mem != null) {
      _memoryOrder.remove(key);
      _memoryOrder.add(key);
      return TtsAudioClip(
        bytes: mem,
        languageCode: voice.languageCode,
        voiceName: voice.voiceName,
        cacheKey: key,
      );
    }
    try {
      final hit = await tts_io.readTtsCacheFile('gctts_$key');
      if (hit != null) {
        final bytes = Uint8List.fromList(hit.bytes);
        _remember(key, bytes);
        return TtsAudioClip(
          bytes: bytes,
          languageCode: voice.languageCode,
          voiceName: voice.voiceName,
          cacheKey: key,
          filePath: hit.path,
        );
      }
    } catch (_) {}
    return null;
  }

  Future<String?> writeCache(String text, Uint8List bytes,
      {double speakingRate = defaultSpeakingRate}) async {
    final trimmed = text.trim();
    final voice = voiceFor(trimmed);
    final key = cacheKeyFor(
      trimmed,
      voice.languageCode,
      voice.voiceName,
      speakingRate,
    );
    _remember(key, bytes);
    try {
      return await tts_io.writeTtsCacheFile('gctts_$key', bytes);
    } catch (_) {
      return null;
    }
  }

  /// Escape text for SSML and wrap with teaching prosody + pronunciation.
  ///
  /// Delegates to [MarathiSsmlConverter] (Module 3) so Cloud TTS and the
  /// video engine share one SSML path.
  static String toTeachingSsml(
    String text, {
    SsmlSegmentKind kind = SsmlSegmentKind.body,
  }) {
    return marathiSsmlConverter.toSsml(text, kind: kind);
  }

  /// Synthesizes [text] to MP3 (one API-sized chunk). Prefer [synthesizeAll]
  /// for long lessons. Retries transient 5xx/429 with exponential backoff.
  Future<TtsAudioClip> synthesize(
    String text, {
    double speakingRate = defaultSpeakingRate,
    SsmlSegmentKind ssmlKind = SsmlSegmentKind.body,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const GoogleCloudTtsException(
        message: 'Cannot synthesize empty text.',
      );
    }
    if (!isConfigured) {
      throw const GoogleCloudTtsException(
        message:
            'Google Cloud TTS credentials are missing.\n'
            'Cloud Text-to-Speech requires a GCP service account '
            '(TTS_SERVICE_ACCOUNT_PATH or TTS_SERVICE_ACCOUNT_JSON), '
            'or GOOGLE_TTS_API_KEY / TTS_API_KEY for key-restricted web use.\n'
            '1) Enable Cloud Text-to-Speech API in Google Cloud Console\n'
            '2) Create a service account + JSON key (or API key with referrer restriction)\n'
            '3) Put the path/key in dart_defines.json\n'
            '4) Restart with --dart-define-from-file=dart_defines.json',
      );
    }

    final rate = speakingRate.clamp(0.5, 1.5);
    final cached = await readCache(trimmed, speakingRate: rate);
    if (cached != null) return cached;

    final voice = voiceFor(trimmed);
    final key = cacheKeyFor(
      trimmed,
      voice.languageCode,
      voice.voiceName,
      rate,
    );

    var response = await _synthesizeWithRetry(
      text: trimmed,
      languageCode: voice.languageCode,
      voiceName: voice.voiceName,
      speakingRate: rate,
      ssmlKind: ssmlKind,
    );

    // Some projects only have Standard voices — retry once if Wavenet is rejected.
    if (response.statusCode == 400 &&
        voice.voiceName.contains('Wavenet') &&
        response.body.toLowerCase().contains('voice')) {
      final fallbackName = voice.voiceName.replaceFirst('Wavenet', 'Standard');
      response = await _synthesizeWithRetry(
        text: trimmed,
        languageCode: voice.languageCode,
        voiceName: fallbackName,
        speakingRate: rate,
        ssmlKind: ssmlKind,
      );
      if (response.statusCode == 200) {
        final standardKey = cacheKeyFor(
          trimmed,
          voice.languageCode,
          fallbackName,
          rate,
        );
        return _clipFromResponse(
          response,
          languageCode: voice.languageCode,
          voiceName: fallbackName,
          cacheKey: standardKey,
          cacheText: trimmed,
          speakingRate: rate,
        );
      }
    }

    if (response.statusCode != 200) {
      throw GoogleCloudTtsException(
        message: _friendlyAuthOrApiMessage(response),
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    return _clipFromResponse(
      response,
      languageCode: voice.languageCode,
      voiceName: voice.voiceName,
      cacheKey: key,
      cacheText: trimmed,
      speakingRate: rate,
    );
  }

  /// Chunks long text and synthesizes each piece (caller plays sequentially).
  Future<List<TtsAudioClip>> synthesizeAll(
    String text, {
    double speakingRate = defaultSpeakingRate,
  }) async {
    final chunks = chunkForApi(text);
    if (chunks.isEmpty) {
      throw const GoogleCloudTtsException(
        message: 'Cannot synthesize empty text.',
      );
    }
    final clips = <TtsAudioClip>[];
    for (final chunk in chunks) {
      clips.add(await synthesize(chunk, speakingRate: speakingRate));
    }
    return clips;
  }

  Future<http.Response> _synthesizeWithRetry({
    required String text,
    required String languageCode,
    required String voiceName,
    required double speakingRate,
    SsmlSegmentKind ssmlKind = SsmlSegmentKind.body,
  }) async {
    final uri = Uri.parse(_endpoint);
    final body = jsonEncode({
      'input': {'ssml': toTeachingSsml(text, kind: ssmlKind)},
      'voice': {
        'languageCode': languageCode,
        'name': voiceName,
      },
      'audioConfig': {
        'audioEncoding': 'MP3',
        'speakingRate': speakingRate,
        'effectsProfileId': ['handset-class-device'],
      },
    });

    GoogleCloudTtsException? lastError;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response = await _postSynthesize(uri, body);
        if (response.statusCode == 200) return response;
        if (!isRetryableStatus(response.statusCode) ||
            attempt == maxRetries - 1) {
          return response;
        }
        lastError = GoogleCloudTtsException(
          message: 'Transient Cloud TTS error, retrying…',
          statusCode: response.statusCode,
          body: response.body,
        );
      } on GoogleCloudTtsException catch (e) {
        if (!isRetryableStatus(e.statusCode) || attempt == maxRetries - 1) {
          rethrow;
        }
        lastError = e;
      } catch (e) {
        if (attempt == maxRetries - 1) {
          throw GoogleCloudTtsException(
            message: 'Network error calling Google Cloud TTS: $e',
          );
        }
        lastError = GoogleCloudTtsException(
          message: 'Network error calling Google Cloud TTS: $e',
        );
      }
      final delayMs = (300 * (1 << attempt)).clamp(300, 4000);
      debugPrint(
        'Google Cloud TTS retry ${attempt + 1}/$maxRetries '
        'after ${delayMs}ms (${lastError.statusCode ?? 'network'})',
      );
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
    throw lastError ??
        const GoogleCloudTtsException(
          message: 'Google Cloud TTS failed after retries.',
        );
  }

  String _friendlyAuthOrApiMessage(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      final prefix = _apiKey.length >= 3 ? _apiKey.substring(0, 3) : _apiKey;
      final usingOnlyApiKey = _accessToken.isEmpty &&
          _saJson.isEmpty &&
          _saPath.isEmpty &&
          !tts_io.ttsHasEnvironmentCredentials;

      if (usingOnlyApiKey) {
        return 'Google Cloud TTS rejected the API key authentication.\n'
            'Prefer a GCP service account (OAuth) via TTS_SERVICE_ACCOUNT_PATH, '
            'or a Cloud-TTS-enabled API key as GOOGLE_TTS_API_KEY '
            '(restrict by HTTP referrer for Flutter web)'
            '${_apiKey.isNotEmpty ? ' (key starts with $prefix…)' : ''}.';
      }
      return 'Google Cloud TTS authentication failed.';
    }
    if (response.statusCode == 429) {
      return 'Google Cloud TTS rate limit exceeded.';
    }
    return 'Google Cloud TTS synthesize failed.';
  }

  Future<http.Response> _postSynthesize(Uri uri, String body) async {
    try {
      final headers = await _buildHeaders();
      final client = _saClient ?? _fallbackClient;
      return await client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 45));
    } on GoogleCloudTtsException {
      rethrow;
    } catch (e) {
      throw GoogleCloudTtsException(
        message: 'Network error calling Google Cloud TTS: $e',
      );
    }
  }

  Future<Map<String, String>> _buildHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
    };

    if (_accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_accessToken';
      return headers;
    }

    final saClient = await _ensureServiceAccountClient();
    if (saClient != null) {
      // AutoRefreshingAuthClient injects Authorization on send().
      return headers;
    }

    if (_apiKey.isNotEmpty) {
      headers['x-goog-api-key'] = _apiKey;
      return headers;
    }

    throw const GoogleCloudTtsException(
      message: 'No usable Google Cloud TTS credentials were found.',
    );
  }

  Future<AutoRefreshingAuthClient?> _ensureServiceAccountClient() async {
    if (_saClient != null) return _saClient;

    final jsonMap = await _loadServiceAccountJson();
    if (jsonMap == null) return null;

    try {
      final credentials = ServiceAccountCredentials.fromJson(jsonMap);
      _saClient = await clientViaServiceAccount(credentials, _scopes);
      return _saClient;
    } catch (e) {
      throw GoogleCloudTtsException(
        message: 'Failed to create Cloud TTS service-account client: $e',
      );
    }
  }

  Future<Map<String, dynamic>?> _loadServiceAccountJson() async {
    if (_saJson.trim().isNotEmpty) {
      try {
        return jsonDecode(_saJson) as Map<String, dynamic>;
      } catch (e) {
        throw GoogleCloudTtsException(
          message: 'TTS_SERVICE_ACCOUNT_JSON is not valid JSON: $e',
        );
      }
    }

    final pathCandidates = <String>[
      if (_saPath.trim().isNotEmpty) _saPath.trim(),
      if (tts_io.ttsEnvironmentCredentialsPath != null)
        tts_io.ttsEnvironmentCredentialsPath!,
    ];

    for (final path in pathCandidates) {
      final contents = await tts_io.readTtsCredentialsFile(path);
      if (contents == null) {
        // Missing file must not block API-key / other auth fallbacks.
        debugPrint('TTS service-account file not found (skipping): $path');
        continue;
      }
      try {
        return jsonDecode(contents) as Map<String, dynamic>;
      } catch (e) {
        throw GoogleCloudTtsException(
          message: 'Could not parse TTS service-account file ($path): $e',
        );
      }
    }
    return null;
  }

  Future<TtsAudioClip> _clipFromResponse(
    http.Response response, {
    required String languageCode,
    required String voiceName,
    required String cacheKey,
    required String cacheText,
    required double speakingRate,
  }) async {
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw GoogleCloudTtsException(
        message: 'Could not parse TTS JSON response: $e',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final b64 = decoded['audioContent'] as String?;
    if (b64 == null || b64.isEmpty) {
      throw GoogleCloudTtsException(
        message: 'TTS response missing audioContent.',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final bytes = Uint8List.fromList(base64Decode(b64));
    if (bytes.isEmpty) {
      throw const GoogleCloudTtsException(
        message: 'TTS returned empty audio bytes.',
      );
    }

    final path = await writeCache(cacheText, bytes, speakingRate: speakingRate);
    return TtsAudioClip(
      bytes: bytes,
      languageCode: languageCode,
      voiceName: voiceName,
      cacheKey: cacheKey,
      filePath: path,
    );
  }

  void dispose() {
    _memoryCache.clear();
    _memoryOrder.clear();
    _saClient?.close();
    _saClient = null;
    _fallbackClient.close();
  }
}

/// Shared instance used by AI Classroom narration.
final GoogleCloudTtsService googleCloudTtsService = GoogleCloudTtsService();
