import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/services/ai_backend_base.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/gemini_tts_synthesizer.dart';
import 'package:mpsc_combine_ai/services/backend_request_headers.dart';
import 'package:mpsc_combine_ai/utils/student_copy.dart';

class AiTtsException implements Exception {
  const AiTtsException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// One continuous Gemini TTS lecture clip from server `/ai/tts`.
class LessonTtsAudio {
  const LessonTtsAudio({
    required this.bytes,
    required this.mimeType,
    required this.duration,
    this.voiceId = 'Kore',
    this.modelId = kGeminiTtsModel,
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

const String kGeminiTtsModel = 'gemini-3.1-flash-tts-preview';

/// Student AI Teacher voice. Always calls `/ai/tts` with a Firebase ID token.
/// Never ships Gemini or other TTS API keys in the Flutter bundle.
class AiTtsService {
  AiTtsService({
    http.Client? client,
    List<String>? backendBases,
    IdTokenProvider? idToken,
  }) : _client = client ?? http.Client(),
       _backendBases = backendBases,
       _idToken = idToken;

  final http.Client _client;
  final List<String>? _backendBases;
  final IdTokenProvider? _idToken;
  Future<void> _synthesizeGate = Future<void>.value();

  static const String shortMarathiTestScript =
      'नमस्कार विद्यार्थ्यांनो. आज आपण भारतीय राज्यघटनेतील मूलभूत अधिकारांचा अभ्यास करणार आहोत.';

  static final Map<String, LessonTtsAudio> _memoryCache =
      <String, LessonTtsAudio>{};

  List<String> get _bases => _backendBases ?? lessonBackendBases();

  static String cacheKey({
    required String text,
    String voiceId = 'Kore',
    String modelId = kGeminiTtsModel,
  }) {
    final material =
        '${text.trim()}|${voiceId.trim()}|${modelId.trim().isEmpty ? kGeminiTtsModel : modelId.trim()}';
    return sha256.convert(utf8.encode(material)).toString();
  }

  static LessonTtsAudio? cachedAudio(String key) => _memoryCache[key];

  static void storeCachedAudio(String key, LessonTtsAudio audio) {
    if (audio.bytes.isEmpty) return;
    if (_memoryCache.length > 24) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = audio;
  }

  static void clearMemoryCache() => _memoryCache.clear();

  /// Keeps each serverless TTS request to one Gemini audio generation.
  /// Long lectures are joined client-side so one slow provider call does not
  /// make the whole Netlify invocation time out.
  static List<String> chunkForBackend(String text, {int maxChars = 850}) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return const [];
    if (cleaned.length <= maxChars) return [cleaned];
    final sentences = cleaned
        .split(RegExp(r'(?<=[।.?!…])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    final out = <String>[];
    var buffer = '';
    for (final sentence in sentences) {
      if (sentence.length > maxChars) {
        if (buffer.isNotEmpty) {
          out.add(buffer);
          buffer = '';
        }
        for (var start = 0; start < sentence.length; start += maxChars) {
          out.add(
            sentence.substring(
              start,
              (start + maxChars).clamp(0, sentence.length),
            ),
          );
        }
        continue;
      }
      final next = buffer.isEmpty ? sentence : '$buffer $sentence';
      if (next.length > maxChars) {
        out.add(buffer);
        buffer = sentence;
      } else {
        buffer = next;
      }
    }
    if (buffer.isNotEmpty) out.add(buffer);
    if (out.isEmpty) {
      for (var start = 0; start < cleaned.length; start += maxChars) {
        out.add(
          cleaned.substring(start, (start + maxChars).clamp(0, cleaned.length)),
        );
      }
    }
    return out;
  }

  static String safeErrorSnippet(String body, {int max = 220}) {
    var snippet = body.replaceAll(RegExp(r'sk_[A-Za-z0-9]+'), '[redacted]');
    snippet = snippet.replaceAll('\n', ' ').trim();
    if (snippet.length > max) return '${snippet.substring(0, max)}…';
    return snippet;
  }

  Future<LessonTtsAudio> testMarathiGreeting() {
    return synthesizeLesson(
      text: shortMarathiTestScript,
      subject: MpscTeachingSubject.polity,
    );
  }

  Future<LessonTtsAudio> synthesizeLesson({
    required String text,
    required MpscTeachingSubject subject,
    String? voiceId,
    String? modelId,
  }) async {
    final script = text.trim();
    if (script.isEmpty) {
      throw const AiTtsException('Empty lesson script', statusCode: 400);
    }
    final voice = (voiceId ?? 'Kore').trim().isEmpty
        ? 'Kore'
        : (voiceId ?? 'Kore');
    final model = (modelId ?? kGeminiTtsModel).trim().isEmpty
        ? kGeminiTtsModel
        : (modelId ?? kGeminiTtsModel).trim();
    final key = cacheKey(text: script, voiceId: voice, modelId: model);
    final hit = _memoryCache[key];
    if (hit != null && hit.bytes.isNotEmpty) {
      debugPrint('[ai-tts] cache hit chars=${script.length}');
      return hit;
    }

    final previous = _synthesizeGate;
    final released = Completer<void>();
    _synthesizeGate = released.future;
    await previous;
    try {
      final audio = await _synthesizeViaBackend(
        text: script,
        subject: subject,
        voiceId: voice,
        modelId: model,
      );
      storeCachedAudio(key, audio);
      return audio;
    } finally {
      released.complete();
    }
  }

  Future<String> _pickHealthyBase() async {
    final pageHost = kIsWeb ? Uri.base.host : '';
    final localOnly = kIsWeb && isLoopbackHost(pageHost);
    final bases = [
      for (final base in _bases)
        if (!localOnly || isLoopbackAiBackend(base)) base,
    ];
    if (localOnly && bases.isEmpty) {
      debugPrint('[TTS] local worker unavailable');
      throw const AiTtsException(kVoiceFailed, statusCode: 503);
    }
    if (!localOnly && bases.length == 1) return bases.single;
    final found = await firstHealthyAiBackendBase(
      bases: bases,
      waitForLocalWorker: localOnly,
      healthStatus: (origin) async {
        final uri = Uri.parse('$origin/health');
        try {
          final res = await _client
              .get(uri)
              .timeout(const Duration(seconds: 8));
          debugPrint('[TTS] endpoint=$uri status=${res.statusCode}');
          return res.statusCode;
        } catch (e) {
          debugPrint('[TTS] endpoint=$uri error=${e.runtimeType}');
          rethrow;
        }
      },
    );
    if (found != null) return found;
    if (localOnly) {
      debugPrint('[TTS] local worker unavailable');
      throw const AiTtsException(kVoiceFailed, statusCode: 503);
    }
    if (bases.isNotEmpty && !isLoopbackAiBackend(bases.first)) {
      return bases.first;
    }
    debugPrint('[TTS] local worker unavailable');
    throw const AiTtsException(kVoiceFailed, statusCode: 503);
  }

  Future<LessonTtsAudio> _synthesizeViaBackend({
    required String text,
    required MpscTeachingSubject subject,
    required String voiceId,
    required String modelId,
  }) async {
    final base = await _pickHealthyBase();
    if (kReleaseMode || (kIsWeb && !isLoopbackHost(Uri.base.host))) {
      if (isLoopbackAiBackend(base)) {
        debugPrint('[TTS] error=production_blocked_loopback');
        throw const AiTtsException(kVoiceFailed, statusCode: 503);
      }
    }
    if (kIsWeb && isLoopbackHost(Uri.base.host) && !isLoopbackAiBackend(base)) {
      debugPrint('[TTS] local worker unavailable');
      throw const AiTtsException(kVoiceFailed, statusCode: 503);
    }
    final chunks = chunkForBackend(text);
    if (chunks.isEmpty) {
      throw const AiTtsException('Empty lesson script', statusCode: 400);
    }
    debugPrint('[TTS] chunks=${chunks.length}');
    final clips = <LessonTtsAudio>[];
    for (var i = 0; i < chunks.length; i++) {
      clips.add(
        await _requestChunkWithRetry(
          base: base,
          text: chunks[i],
          subject: subject,
          voiceId: voiceId,
          modelId: modelId,
          chunkIndex: i,
          chunkCount: chunks.length,
        ),
      );
    }
    final bytes = GeminiTtsSynthesizer.concatWav(
      clips.map((clip) => clip.bytes).toList(growable: false),
    );
    final measured = GeminiTtsSynthesizer.wavDuration(bytes);
    final summed = clips.fold<Duration>(
      Duration.zero,
      (total, clip) => total + clip.duration,
    );
    final duration = measured > Duration.zero ? measured : summed;
    debugPrint('[TTS] audioBytes=${bytes.length}');
    debugPrint('[TTS] mimeType=audio/wav');
    return LessonTtsAudio(
      bytes: bytes,
      mimeType: 'audio/wav',
      duration: duration > Duration.zero
          ? duration
          : Duration(milliseconds: (text.length / 13 * 1000).round()),
      voiceId: clips.first.voiceId,
      modelId: clips.first.modelId,
    );
  }

  Future<LessonTtsAudio> _requestChunkWithRetry({
    required String base,
    required String text,
    required MpscTeachingSubject subject,
    required String voiceId,
    required String modelId,
    required int chunkIndex,
    required int chunkCount,
  }) async {
    AiTtsException? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _requestChunk(
          base: base,
          text: text,
          subject: subject,
          voiceId: voiceId,
          modelId: modelId,
        );
      } on AiTtsException catch (e) {
        last = e;
        if (!_isTransientStatus(e.statusCode) || attempt == 2) rethrow;
        final delay = Duration(milliseconds: 600 * (1 << attempt));
        debugPrint(
          '[TTS] transient chunk=${chunkIndex + 1}/$chunkCount '
          'status=${e.statusCode} retry=${attempt + 1}',
        );
        await Future<void>.delayed(delay);
      }
    }
    throw last ?? const AiTtsException(kVoiceFailed, statusCode: 503);
  }

  Future<LessonTtsAudio> _requestChunk({
    required String base,
    required String text,
    required MpscTeachingSubject subject,
    required String voiceId,
    required String modelId,
  }) async {
    final uri = Uri.parse(aiTtsEndpoint(base));
    final headers = await backendJsonHeaders(idToken: _idToken);
    debugPrint('[TTS] endpoint=$uri');
    debugPrint('[TTS] hasToken=${headers.containsKey('Authorization')}');
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: headers,
            body: jsonEncode({'text': text, 'subject': subject.id}),
          )
          .timeout(const Duration(seconds: 75));
    } catch (e) {
      debugPrint('[TTS] error=${e.runtimeType}');
      throw const AiTtsException(kVoiceFailed, statusCode: 503);
    }
    debugPrint('[TTS] status=${response.statusCode}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[TTS] error=HTTP ${response.statusCode} '
        '${safeErrorSnippet(response.body)}',
      );
      throw AiTtsException(kVoiceFailed, statusCode: response.statusCode);
    }
    final decoded = _tryJsonMap(response.body);
    if (decoded == null) {
      throw const AiTtsException(kVoiceFailed, statusCode: 502);
    }
    final error = '${decoded['error'] ?? ''}'.trim();
    if (error.isNotEmpty) {
      debugPrint('[TTS] error=${safeErrorSnippet(error)}');
      throw AiTtsException(
        kVoiceFailed,
        statusCode: (decoded['status'] as num?)?.toInt() ?? 502,
      );
    }
    final b64 = '${decoded['audio_base64'] ?? ''}'.trim();
    if (b64.isEmpty) {
      throw const AiTtsException(kVoiceFailed, statusCode: 502);
    }
    Uint8List bytes;
    try {
      bytes = Uint8List.fromList(base64Decode(b64));
    } catch (_) {
      throw const AiTtsException(kVoiceFailed, statusCode: 502);
    }
    final rawMime =
        '${decoded['mime_type'] ?? decoded['mimeType'] ?? 'audio/wav'}';
    bytes = GeminiTtsSynthesizer.ensureWav(bytes, mimeType: rawMime);
    if (bytes.length < 256) {
      throw const AiTtsException(kVoiceFailed, statusCode: 502);
    }
    final ms =
        (decoded['durationMs'] as num?)?.toInt() ??
        (text.length / 13 * 1000).round();
    return LessonTtsAudio(
      bytes: bytes,
      mimeType: 'audio/wav',
      duration: Duration(milliseconds: ms.clamp(800, 12 * 60 * 1000)),
      voiceId: '${decoded['voiceId'] ?? voiceId}',
      modelId: '${decoded['modelId'] ?? modelId}',
    );
  }

  static bool _isTransientStatus(int? status) =>
      status == 429 ||
      status == 500 ||
      status == 502 ||
      status == 503 ||
      status == 504;

  Map<String, dynamic>? _tryJsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }
}

final AiTtsService aiTtsService = AiTtsService();
