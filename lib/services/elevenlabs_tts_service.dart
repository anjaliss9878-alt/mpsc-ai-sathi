import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/services/ai_backend_base.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/backend_request_headers.dart';

class ElevenLabsTtsException implements Exception {
  const ElevenLabsTtsException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// One continuous ElevenLabs lecture clip plus optional character timings.
class ElevenLabsLessonAudio {
  const ElevenLabsLessonAudio({
    required this.bytes,
    required this.mimeType,
    required this.duration,
    required this.voiceId,
    this.modelId = '',
    this.characters = const [],
    this.charStartSeconds = const [],
    this.charEndSeconds = const [],
  });

  final Uint8List bytes;
  final String mimeType;
  final Duration duration;
  final String voiceId;
  final String modelId;
  final List<String> characters;
  final List<double> charStartSeconds;
  final List<double> charEndSeconds;

  bool get hasAlignment =>
      characters.isNotEmpty &&
      characters.length == charStartSeconds.length &&
      characters.length == charEndSeconds.length;
}

/// ElevenLabs TTS for AI Classroom — one continuous Marathi file per lesson.
///
/// The API key never ships in the Flutter web bundle. Web always uses the
/// server-side `/ai/tts` backend (`ELEVENLABS_API_KEY` on the worker / Netlify).
class ElevenLabsTtsService {
  ElevenLabsTtsService({http.Client? client, String? apiKey})
      : _client = client ?? http.Client(),
        _apiKey = (apiKey ?? _envKey).trim();

  final http.Client _client;
  final String _apiKey;

  static const String _envKey = String.fromEnvironment('ELEVENLABS_API_KEY');
  static const String _envVoiceId = String.fromEnvironment('ELEVENLABS_VOICE_ID');
  static const String _envModelId = String.fromEnvironment('ELEVENLABS_MODEL_ID');
  static const String _envModel = String.fromEnvironment(
    'ELEVENLABS_MODEL',
    defaultValue: 'eleven_multilingual_v2',
  );

  static const String defaultModelId = 'eleven_multilingual_v2';
  static const String shortMarathiTestScript =
      'नमस्कार विद्यार्थ्यांनो. आज आपण भारतीय राज्यघटनेतील मूलभूत अधिकारांचा अभ्यास करणार आहोत.';

  static final Map<String, ElevenLabsLessonAudio> _memoryCache =
      <String, ElevenLabsLessonAudio>{};

  String get _workerBase => aiBackendBase();

  /// One request covers a 3–5 minute Marathi lecture.
  static const int maxCharsPerRequest = 5000;

  static const String marathiTestLine = shortMarathiTestScript;

  bool get isConfigured => _apiKey.isNotEmpty;

  String get resolvedModelId {
    final id = _envModelId.trim();
    if (id.isNotEmpty) return id;
    final legacy = _envModel.trim();
    if (legacy.isNotEmpty) return legacy;
    return defaultModelId;
  }

  String resolvedVoiceId(MpscTeachingSubject subject, {String? voiceId}) {
    final override = (voiceId ?? '').trim();
    if (override.isNotEmpty) return override;
    if (_envVoiceId.trim().isNotEmpty) return _envVoiceId.trim();
    return subject.elevenLabsVoiceId.trim();
  }

  static String cacheKey({
    required String text,
    required String voiceId,
    required String modelId,
  }) {
    final material =
        '${text.trim()}|${voiceId.trim()}|${modelId.trim().isEmpty ? defaultModelId : modelId.trim()}';
    return sha256.convert(utf8.encode(material)).toString();
  }

  static ElevenLabsLessonAudio? cachedAudio(String key) => _memoryCache[key];

  static void storeCachedAudio(String key, ElevenLabsLessonAudio audio) {
    if (audio.bytes.isEmpty) return;
    if (_memoryCache.length > 24) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = audio;
  }

  static void clearMemoryCache() => _memoryCache.clear();

  static String safeErrorSnippet(String body, {int max = 220}) {
    var snippet = body.replaceAll(RegExp(r'xi-api-key\s*[:=]\s*\S+', caseSensitive: false), '');
    snippet = snippet.replaceAll(RegExp(r'sk_[A-Za-z0-9]+'), '[redacted]');
    snippet = snippet.replaceAll('\n', ' ').trim();
    if (snippet.length > max) return '${snippet.substring(0, max)}…';
    return snippet;
  }

  /// Converts the standard Marathi classroom greeting into one audio file.
  Future<ElevenLabsLessonAudio> testMarathiGreeting() {
    return synthesizeLesson(
      text: shortMarathiTestScript,
      subject: MpscTeachingSubject.polity,
    );
  }

  Future<ElevenLabsLessonAudio> synthesizeLesson({
    required String text,
    required MpscTeachingSubject subject,
    String? voiceId,
    String? modelId,
  }) async {
    final script = text.trim();
    if (script.isEmpty) {
      throw const ElevenLabsTtsException(
        'Empty lesson script',
        statusCode: 400,
      );
    }

    final voice = resolvedVoiceId(subject, voiceId: voiceId);
    if (voice.isEmpty) {
      throw const ElevenLabsTtsException(
        'ElevenLabs voice id is missing',
        statusCode: 400,
      );
    }
    final model = (modelId ?? resolvedModelId).trim().isEmpty
        ? defaultModelId
        : (modelId ?? resolvedModelId).trim();
    final key = cacheKey(text: script, voiceId: voice, modelId: model);
    final hit = _memoryCache[key];
    if (hit != null && hit.bytes.isNotEmpty) {
      debugPrint(
        '[ElevenLabs] cache hit voice=$voice model=$model chars=${script.length}',
      );
      return hit;
    }

    // Never call ElevenLabs from the browser — key must stay server-side.
    final ElevenLabsLessonAudio audio;
    if (kIsWeb) {
      audio = await _synthesizeViaBackend(
        text: script,
        subject: subject,
        voiceId: voice,
        modelId: model,
      );
    } else if (!isConfigured) {
      throw const ElevenLabsTtsException(
        'ElevenLabs API key missing',
        statusCode: 401,
      );
    } else {
      audio = await _synthesizeDirect(
        text: script,
        subject: subject,
        voiceId: voice,
        modelId: model,
      );
    }
    if (audio.bytes.isEmpty) {
      throw const ElevenLabsTtsException(
        'ElevenLabs returned empty audio',
        statusCode: 502,
      );
    }
    storeCachedAudio(key, audio);
    return audio;
  }

  Future<ElevenLabsLessonAudio> _synthesizeDirect({
    required String text,
    required MpscTeachingSubject subject,
    required String voiceId,
    required String modelId,
  }) async {
    final uri = Uri.parse(
      'https://api.elevenlabs.io/v1/text-to-speech/$voiceId/with-timestamps',
    );
    final body = jsonEncode({
      'text': text,
      'model_id': modelId,
      'voice_settings': subject.elevenLabsVoiceSettings,
    });

    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'xi-api-key': _apiKey,
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 240));
    } catch (e) {
      throw ElevenLabsTtsException(
        'ElevenLabs TTS failed (network). ${safeErrorSnippet('$e')}',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ElevenLabsTtsException(
        'ElevenLabs TTS failed (HTTP ${response.statusCode}). '
        '${safeErrorSnippet(response.body)}',
        statusCode: response.statusCode,
      );
    }

    return _parseTimestampResponse(
      response.body,
      script: text,
      voiceId: voiceId,
      modelId: modelId,
      subject: subject,
    );
  }

  Future<ElevenLabsLessonAudio> _synthesizeViaBackend({
    required String text,
    required MpscTeachingSubject subject,
    required String voiceId,
    required String modelId,
  }) async {
    final uri = Uri.parse('$_workerBase/ai/tts');
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: await backendJsonHeaders(),
            body: jsonEncode({
              'text': text,
              'subject': subject.id,
              'voiceId': voiceId,
              'modelId': modelId,
            }),
          )
          .timeout(const Duration(seconds: 240));
    } catch (e) {
      throw ElevenLabsTtsException(
        'ElevenLabs TTS failed (backend unreachable). ${safeErrorSnippet('$e')}',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('[ElevenLabs] backend HTTP ${response.statusCode}');
      final map = _tryJsonMap(response.body);
      final err = '${map?['error'] ?? ''}'.trim();
      throw ElevenLabsTtsException(
        err.isNotEmpty
            ? err
            : 'ElevenLabs TTS failed (HTTP ${response.statusCode}). '
                '${safeErrorSnippet(response.body)}',
        statusCode: response.statusCode,
      );
    }
    final decoded = _tryJsonMap(response.body);
    if (decoded == null) {
      throw const ElevenLabsTtsException(
        'ElevenLabs returned a non-JSON body',
        statusCode: 502,
      );
    }
    if ('${decoded['error'] ?? ''}'.trim().isNotEmpty) {
      throw ElevenLabsTtsException(
        '${decoded['error']}',
        statusCode: (decoded['status'] as num?)?.toInt() ?? 502,
      );
    }
    final b64 = '${decoded['audio_base64'] ?? ''}'.trim();
    if (b64.isEmpty) {
      throw const ElevenLabsTtsException(
        'ElevenLabs returned empty audio',
        statusCode: 502,
      );
    }
    final bytes = Uint8List.fromList(base64Decode(b64));
    if (bytes.isEmpty) {
      throw const ElevenLabsTtsException(
        'ElevenLabs returned empty audio',
        statusCode: 502,
      );
    }
    final ms = (decoded['durationMs'] as num?)?.toInt() ??
        (text.length / 13 * 1000).round();
    return ElevenLabsLessonAudio(
      bytes: bytes,
      mimeType: '${decoded['mimeType'] ?? 'audio/mpeg'}',
      duration: Duration(milliseconds: ms.clamp(800, 12 * 60 * 1000)),
      voiceId: '${decoded['voiceId'] ?? voiceId}',
      modelId: '${decoded['modelId'] ?? modelId}',
    );
  }

  ElevenLabsLessonAudio _parseTimestampResponse(
    String raw, {
    required String script,
    required String voiceId,
    required String modelId,
    required MpscTeachingSubject subject,
  }) {
    final map = jsonDecode(raw);
    if (map is! Map) {
      throw const ElevenLabsTtsException(
        'ElevenLabs returned a non-JSON body',
        statusCode: 502,
      );
    }
    final decoded = Map<String, dynamic>.from(map);
    final b64 = '${decoded['audio_base64'] ?? ''}'.trim();
    if (b64.isEmpty) {
      throw const ElevenLabsTtsException(
        'ElevenLabs returned empty audio',
        statusCode: 502,
      );
    }

    Uint8List bytes;
    try {
      bytes = Uint8List.fromList(base64Decode(b64));
    } catch (_) {
      throw const ElevenLabsTtsException(
        'ElevenLabs audio could not be decoded',
        statusCode: 502,
      );
    }
    if (bytes.length < 800) {
      throw const ElevenLabsTtsException(
        'ElevenLabs audio was too short',
        statusCode: 502,
      );
    }

    final alignment = _readAlignment(decoded['normalized_alignment']) ??
        _readAlignment(decoded['alignment']);
    final chars = alignment?.characters ?? const <String>[];
    final starts = alignment?.starts ?? const <double>[];
    final ends = alignment?.ends ?? const <double>[];

    var duration = Duration.zero;
    if (ends.isNotEmpty) {
      duration = Duration(
        milliseconds: (ends.last * 1000).round().clamp(500, 12 * 60 * 1000),
      );
    }
    if (duration < const Duration(milliseconds: 800)) {
      duration = Duration(
        milliseconds: (script.length / 13 * 1000).round().clamp(800, 600000),
      );
    }

    debugPrint(
      '[ElevenLabs] subject=${subject.id} voice=$voiceId model=$modelId '
      'chars=${script.length} bytes=${bytes.length} '
      'dur=${duration.inMilliseconds}ms align=${chars.length}',
    );

    return ElevenLabsLessonAudio(
      bytes: bytes,
      mimeType: 'audio/mpeg',
      duration: duration,
      voiceId: voiceId,
      modelId: modelId,
      characters: chars,
      charStartSeconds: starts,
      charEndSeconds: ends,
    );
  }

  Map<String, dynamic>? _tryJsonMap(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is Map) return Map<String, dynamic>.from(map);
    } catch (_) {}
    return null;
  }

  _Alignment? _readAlignment(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final chars = (map['characters'] as List?)?.map((e) => '$e').toList() ??
        const <String>[];
    final starts = (map['character_start_times_seconds'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const <double>[];
    final ends = (map['character_end_times_seconds'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const <double>[];
    if (chars.isEmpty ||
        chars.length != starts.length ||
        chars.length != ends.length) {
      return null;
    }
    return _Alignment(characters: chars, starts: starts, ends: ends);
  }
}

class _Alignment {
  const _Alignment({
    required this.characters,
    required this.starts,
    required this.ends,
  });

  final List<String> characters;
  final List<double> starts;
  final List<double> ends;
}

final ElevenLabsTtsService elevenLabsTtsService = ElevenLabsTtsService();
