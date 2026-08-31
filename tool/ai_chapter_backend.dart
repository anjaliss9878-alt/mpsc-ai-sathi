// Local Gemini + TTS proxy for the Flutter web AI Teacher (avoids browser CORS).
// Secrets stay in dart_defines.json. Does not import Flutter/Firestore.
// Binds 127.0.0.1:8791.
//
//   dart run tool/ai_chapter_backend.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/services/ai_teacher_system/faculty_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/gemini_rest_client.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/speakable_marathi.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/gemini_tts_synthesizer.dart';

Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ??
      (args.isNotEmpty ? int.tryParse(args.first) : null) ??
      8791;
  final defines = jsonDecode(await File('dart_defines.json').readAsString())
      as Map<String, dynamic>;
  final apiKey = '${defines['AI_API_KEY'] ?? ''}'.trim();
  final model = '${defines['AI_MODEL'] ?? 'gemini-2.0-flash'}'.trim();
  if (apiKey.isEmpty) {
    stderr.writeln('Missing AI_API_KEY in dart_defines.json');
    exit(1);
  }

  final gemini = GeminiRestClient(
    apiKey: apiKey,
    model: model,
    client: http.Client(),
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('AI chapter backend http://127.0.0.1:$port');

  await for (final request in server) {
    _cors(request.response);
    try {
      if (request.method == 'OPTIONS') {
        request.response.statusCode = 204;
        await request.response.close();
        continue;
      }
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/health') {
        request.response
          ..statusCode = 200
          ..write('{"ok":true}');
        await request.response.close();
        continue;
      }
      if (request.method == 'GET' && path == '/ai/test/gemini') {
        await _testGemini(request, gemini);
        continue;
      }
      if (request.method == 'POST' && path == '/ai/lesson') {
        await _lesson(request, gemini);
        continue;
      }
      if (request.method == 'POST' && path == '/ai/tts') {
        await _tts(request, defines);
        continue;
      }
      request.response.statusCode = 404;
      request.response.write('{"error":"not found"}');
      await request.response.close();
    } catch (e, st) {
      stderr.writeln('request failed: $e\n$st');
      try {
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'error': '$e'}));
        await request.response.close();
      } catch (_) {}
    }
  }
}

void _cors(HttpResponse response) {
  response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    ..set('Access-Control-Allow-Headers', 'Content-Type, Authorization')
    ..contentType = ContentType.json;
}

Future<void> _testGemini(HttpRequest request, GeminiRestClient gemini) async {
  const prompt =
      "Explain the MPSC topic 'मान्सून' in Marathi. Return a short structured lesson with title, subject, explanation and 5 important exam points.";
  stdout.writeln('[AI-CHAPTER] gemini_request_started test_prompt');
  try {
    final text = await gemini.generateText(
      systemPrompt: 'You are an MPSC Marathi teacher. Reply in Marathi.',
      userText: prompt,
    );
    stdout.writeln(
      '[AI-CHAPTER] gemini_response_received chars=${text.length}',
    );
    request.response.statusCode = 200;
    request.response.write(jsonEncode({
      'ok': text.trim().isNotEmpty,
      'chars': text.length,
      'preview': text.length > 240 ? text.substring(0, 240) : text,
    }));
  } catch (e) {
    stdout.writeln('[AI-CHAPTER] gemini_failed error=$e');
    request.response.statusCode = 500;
    request.response.write(jsonEncode({'ok': false, 'error': '$e'}));
  }
  await request.response.close();
}

Future<void> _lesson(HttpRequest request, GeminiRestClient gemini) async {
  final body = await utf8.decoder.bind(request).join();
  final map = jsonDecode(body) as Map<String, dynamic>;
  final topic = '${map['topic'] ?? ''}'.trim();
  final subjectContext = '${map['subjectContext'] ?? ''}'.trim();
  final teachingSubject = MpscTeachingSubjectX.tryParse(
    '${map['teachingSubject'] ?? ''}',
  );
  if (topic.isEmpty) {
    request.response.statusCode = 400;
    request.response.write('{"error":"topic required"}');
    await request.response.close();
    return;
  }
  final style = teachingSubject ??
      tryDetectMpscTeachingSubject(topic, hint: subjectContext);
  stdout.writeln(
    '[AI-CHAPTER] topic_received topic=$topic '
    'detected_subject=${style?.nameEn ?? 'auto'}',
  );
  try {
    final lesson = await gemini.generateJson(
      systemPrompt:
          'You are an MPSC Combined Group B/C Marathi teacher. Reply with one JSON object only. Teach the exact student topic. Never substitute संसद/Parliament unless that is the topic.',
      userText: chapterUserPrompt(topic: topic, subject: style),
      temperature: 0.35,
      maxOutputTokens: 8192,
    );
    final title = '${lesson['title'] ?? lesson['topicName'] ?? topic}';
    final notes = lesson['notes'];
    final mcqs = lesson['mcqs'];
    final pyqs = lesson['pyqs'];
    final slides = lesson['slides'];
    final tricks = lesson['memoryTricks'] ?? lesson['memory_tricks'];
    final revision = lesson['revision'] ?? lesson['revision_points'];
    stdout.writeln(
      '[AI-CHAPTER] parse_success title=$title '
      'sections=${slides is List ? slides.length : 0} '
      'notes=${notes is List && notes.isNotEmpty} '
      'mcqs=${mcqs is List ? mcqs.length : 0} '
      'pyqs=${pyqs is List ? pyqs.length : 0} '
      'tricks=${tricks is List && tricks.isNotEmpty} '
      'revision=${revision is List ? revision.isNotEmpty : '$revision'.trim().isNotEmpty}',
    );
    request.response.statusCode = 200;
    request.response.write(jsonEncode({'lesson': lesson}));
  } catch (e, st) {
    stderr.writeln('[AI-CHAPTER] lesson_failed error=$e\n$st');
    request.response.statusCode = 500;
    request.response.write(jsonEncode({'error': '$e'}));
  }
  await request.response.close();
}

Future<void> _tts(
  HttpRequest request,
  Map<String, dynamic> defines,
) async {
  final body = await utf8.decoder.bind(request).join();
  final map = jsonDecode(body) as Map<String, dynamic>;
  final rawText = '${map['text'] ?? ''}'.trim();
  var text = speakableMarathi(stripUnspeakableLessonText(rawText));
  if (text.isEmpty) {
    request.response.statusCode = 400;
    request.response.write(
      jsonEncode({'error': 'Empty lesson script', 'status': 400}),
    );
    await request.response.close();
    return;
  }

  stdout.writeln('[AI-TTS] request chars=${text.length}');
  text = _clipAtSentence(text, 1800);
  try {
    final clip = await _synthesizeSpeech(text: text, map: map, defines: defines);
    if (clip.bytes.isEmpty) {
      throw StateError('TTS returned empty audio');
    }
    stdout.writeln(
      '[AI-TTS] ok mime=${clip.mime} bytes=${clip.bytes.length} '
      'ms=${clip.durationMs}',
    );
    request.response.statusCode = 200;
    request.response.write(
      jsonEncode({
        'audio_base64': base64Encode(clip.bytes),
        'mimeType': clip.mime,
        'durationMs': clip.durationMs,
        'voiceId': clip.voiceId,
        'modelId': clip.modelId,
      }),
    );
  } catch (e, st) {
    stderr.writeln('[AI-TTS] failed error=$e\n$st');
    request.response.statusCode = 502;
    request.response.write(
      jsonEncode({
        'error': '$e',
        'status': 502,
      }),
    );
  }
  await request.response.close();
}

class _TtsClip {
  const _TtsClip({
    required this.bytes,
    required this.mime,
    required this.durationMs,
    required this.voiceId,
    required this.modelId,
  });

  final Uint8List bytes;
  final String mime;
  final int durationMs;
  final String voiceId;
  final String modelId;
}

Future<_TtsClip> _synthesizeSpeech({
  required String text,
  required Map<String, dynamic> map,
  required Map<String, dynamic> defines,
}) async {
  final elevenKey = '${defines['ELEVENLABS_API_KEY'] ?? ''}'.trim();
  if (elevenKey.isNotEmpty) {
    return _elevenLabsSpeech(text: text, map: map, defines: defines, apiKey: elevenKey);
  }

  final geminiKey = '${defines['AI_API_KEY'] ?? ''}'.trim();
  if (geminiKey.isEmpty) {
    throw StateError(
      'Marathi TTS credentials missing. Set AI_API_KEY or ELEVENLABS_API_KEY.',
    );
  }
  return _geminiSpeech(text: text, apiKey: geminiKey);
}

Future<_TtsClip> _elevenLabsSpeech({
  required String text,
  required Map<String, dynamic> map,
  required Map<String, dynamic> defines,
  required String apiKey,
}) async {
  final subject = MpscTeachingSubjectX.tryParse('${map['subject'] ?? ''}') ??
      MpscTeachingSubject.polity;
  final voiceId = '${map['voiceId'] ?? defines['ELEVENLABS_VOICE_ID'] ?? ''}'
          .trim()
          .isNotEmpty
      ? '${map['voiceId'] ?? defines['ELEVENLABS_VOICE_ID'] ?? ''}'.trim()
      : subject.elevenLabsVoiceId;
  final modelId =
      '${map['modelId'] ?? defines['ELEVENLABS_MODEL_ID'] ?? defines['ELEVENLABS_MODEL'] ?? 'eleven_multilingual_v2'}'
          .trim();
  final uri = Uri.parse(
    'https://api.elevenlabs.io/v1/text-to-speech/$voiceId/with-timestamps',
  );
  final res = await http
      .post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'xi-api-key': apiKey,
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'text': text,
          'model_id': modelId.isEmpty ? 'eleven_multilingual_v2' : modelId,
        }),
      )
      .timeout(const Duration(seconds: 180));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw StateError('ElevenLabs TTS failed (HTTP ${res.statusCode})');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) {
    throw StateError('ElevenLabs returned a non-JSON body');
  }
  final b64 = '${decoded['audio_base64'] ?? ''}'.trim();
  if (b64.isEmpty) {
    throw StateError('ElevenLabs returned empty audio');
  }
  final bytes = Uint8List.fromList(base64Decode(b64));
  if (bytes.isEmpty) {
    throw StateError('ElevenLabs returned empty audio');
  }
  final alignment = decoded['normalized_alignment'] ?? decoded['alignment'];
  var durationMs = (text.length / 13 * 1000).round();
  if (alignment is Map) {
    final ends = alignment['character_end_times_seconds'];
    if (ends is List && ends.isNotEmpty) {
      durationMs = ((ends.last as num).toDouble() * 1000).round();
    }
  }
  return _TtsClip(
    bytes: bytes,
    mime: 'audio/mpeg',
    durationMs: durationMs.clamp(800, 12 * 60 * 1000),
    voiceId: voiceId,
    modelId: modelId.isEmpty ? 'eleven_multilingual_v2' : modelId,
  );
}

Future<_TtsClip> _geminiSpeech({
  required String text,
  required String apiKey,
}) async {
  final gemini = GeminiTtsSynthesizer(apiKey: apiKey);
  final chunks = _chunkSpeech(text, 900);
  if (chunks.isEmpty) {
    throw StateError('Empty lesson script');
  }
  stdout.writeln('[AI-TTS] gemini chunks=${chunks.length}');
  final wavs = <Uint8List>[];
  for (final chunk in chunks) {
    final wav = await gemini.synthesizeMarathiFacultyWithRetry(chunk);
    if (wav.length < 256) {
      throw StateError('Gemini TTS returned empty audio');
    }
    wavs.add(wav);
  }
  final bytes = wavs.length == 1 ? wavs.first : GeminiTtsSynthesizer.concatWav(wavs);
  final duration = GeminiTtsSynthesizer.wavDuration(bytes);
  return _TtsClip(
    bytes: bytes,
    mime: 'audio/wav',
    durationMs: duration.inMilliseconds.clamp(800, 12 * 60 * 1000),
    voiceId: 'Kore',
    modelId: 'gemini-tts',
  );
}

String _clipAtSentence(String text, int maxChars) {
  final cleaned = text.trim();
  if (cleaned.length <= maxChars) return cleaned;
  final clipped = _chunkSpeech(cleaned, maxChars).first;
  stdout.writeln('[AI-TTS] clipped_to=${clipped.length}');
  return clipped;
}

List<String> _chunkSpeech(String text, int maxChars) {
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
      final end =
          i + maxChars > cleaned.length ? cleaned.length : i + maxChars;
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
