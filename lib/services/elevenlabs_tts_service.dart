import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/services/ai_backend_base.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';

class ElevenLabsTtsException implements Exception {
  const ElevenLabsTtsException(this.message);

  final String message;

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
    this.characters = const [],
    this.charStartSeconds = const [],
    this.charEndSeconds = const [],
  });

  final Uint8List bytes;
  final String mimeType;
  final Duration duration;
  final String voiceId;
  final List<String> characters;
  final List<double> charStartSeconds;
  final List<double> charEndSeconds;

  bool get hasAlignment =>
      characters.isNotEmpty &&
      characters.length == charStartSeconds.length &&
      characters.length == charEndSeconds.length;
}

/// ElevenLabs TTS for AI Classroom — one continuous Marathi file per lesson.
class ElevenLabsTtsService {
  ElevenLabsTtsService({http.Client? client, String? apiKey})
      : _client = client ?? http.Client(),
        _apiKey = (apiKey ?? _envKey).trim();

  final http.Client _client;
  final String _apiKey;

  static const String _envKey = String.fromEnvironment('ELEVENLABS_API_KEY');
  static const String _model = String.fromEnvironment(
    'ELEVENLABS_MODEL',
    defaultValue: 'eleven_multilingual_v2',
  );

  String get _workerBase => aiBackendBase();

  /// One request covers a 3–5 minute Marathi lecture.
  static const int maxCharsPerRequest = 5000;

  static const String marathiTestLine =
      'नमस्कार विद्यार्थ्यांनो, आज आपण मान्सूनचा अभ्यास करणार आहोत.';

  bool get isConfigured => _apiKey.isNotEmpty;

  /// Converts the standard Marathi classroom greeting into one audio file.
  Future<ElevenLabsLessonAudio> testMarathiGreeting() {
    return synthesizeLesson(
      text: marathiTestLine,
      subject: MpscTeachingSubject.geography,
    );
  }

  Future<ElevenLabsLessonAudio> synthesizeLesson({
    required String text,
    required MpscTeachingSubject subject,
  }) async {
    final script = text.trim();
    if (script.isEmpty) {
      throw const ElevenLabsTtsException('Empty lecture script');
    }
    if (!isConfigured) {
      return _synthesizeViaBackend(text: script, subject: subject);
    }

    final voiceId = subject.elevenLabsVoiceId.trim();
    if (voiceId.isEmpty) {
      throw const ElevenLabsTtsException('ElevenLabs voice id is missing');
    }

    final uri = Uri.parse(
      'https://api.elevenlabs.io/v1/text-to-speech/$voiceId/with-timestamps',
    );
    final body = jsonEncode({
      'text': script,
      'model_id': _model.trim().isEmpty ? 'eleven_multilingual_v2' : _model.trim(),
      'voice_settings': subject.elevenLabsVoiceSettings,
    });

    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'xi-api-key': _apiKey,
            'Accept': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final snippet = response.body.length > 280
          ? '${response.body.substring(0, 280)}…'
          : response.body;
      throw ElevenLabsTtsException(
        'ElevenLabs TTS failed (HTTP ${response.statusCode}). $snippet',
      );
    }

    final map = jsonDecode(response.body);
    if (map is! Map) {
      throw const ElevenLabsTtsException('ElevenLabs returned a non-JSON body');
    }
    final decoded = Map<String, dynamic>.from(map);
    final b64 = '${decoded['audio_base64'] ?? ''}'.trim();
    if (b64.isEmpty) {
      throw const ElevenLabsTtsException('ElevenLabs returned empty audio');
    }

    Uint8List bytes;
    try {
      bytes = Uint8List.fromList(base64Decode(b64));
    } catch (_) {
      throw const ElevenLabsTtsException('ElevenLabs audio could not be decoded');
    }
    if (bytes.length < 800) {
      throw const ElevenLabsTtsException('ElevenLabs audio was too short');
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
    if (duration < const Duration(seconds: 2)) {
      duration = Duration(
        milliseconds: (script.length / 13 * 1000).round().clamp(2000, 600000),
      );
    }

    debugPrint(
      '[ElevenLabs] subject=${subject.id} voice=$voiceId '
      'chars=${script.length} bytes=${bytes.length} '
      'dur=${duration.inMilliseconds}ms align=${chars.length}',
    );

    return ElevenLabsLessonAudio(
      bytes: bytes,
      mimeType: 'audio/mpeg',
      duration: duration,
      voiceId: voiceId,
      characters: chars,
      charStartSeconds: starts,
      charEndSeconds: ends,
    );
  }

  Future<ElevenLabsLessonAudio> _synthesizeViaBackend({
    required String text,
    required MpscTeachingSubject subject,
  }) async {
    final uri = Uri.parse('$_workerBase/ai/tts');
    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'text': text,
            'subject': subject.id,
          }),
        )
        .timeout(const Duration(seconds: 120));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('[ElevenLabs] backend HTTP ${response.statusCode} ${response.body}');
      throw const ElevenLabsTtsException(
        'ElevenLabs TTS failed',
      );
    }
    final map = jsonDecode(response.body);
    if (map is! Map) {
      throw const ElevenLabsTtsException('ElevenLabs returned a non-JSON body');
    }
    final decoded = Map<String, dynamic>.from(map);
    if ('${decoded['error'] ?? ''}'.trim().isNotEmpty) {
      throw ElevenLabsTtsException('${decoded['error']}');
    }
    final b64 = '${decoded['audio_base64'] ?? ''}'.trim();
    if (b64.isEmpty) {
      throw const ElevenLabsTtsException('ElevenLabs returned empty audio');
    }
    final bytes = Uint8List.fromList(base64Decode(b64));
    final ms = (decoded['durationMs'] as num?)?.toInt() ?? (text.length / 13 * 1000).round();
    return ElevenLabsLessonAudio(
      bytes: bytes,
      mimeType: '${decoded['mimeType'] ?? 'audio/mpeg'}',
      duration: Duration(milliseconds: ms.clamp(2000, 12 * 60 * 1000)),
      voiceId: '${decoded['voiceId'] ?? subject.elevenLabsVoiceId}',
    );
  }

  _Alignment? _readAlignment(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final chars = (map['characters'] as List?)
            ?.map((e) => '$e')
            .toList() ??
        const <String>[];
    final starts = (map['character_start_times_seconds'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const <double>[];
    final ends = (map['character_end_times_seconds'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const <double>[];
    if (chars.isEmpty || chars.length != starts.length || chars.length != ends.length) {
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
