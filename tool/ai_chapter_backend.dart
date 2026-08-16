// Local Gemini proxy for the Flutter web AI Teacher (avoids browser CORS).
// Does not import Flutter/Firestore. Binds 127.0.0.1:8791.
//
//   dart run tool/ai_chapter_backend.dart

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/services/ai_teacher_system/gemini_rest_client.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';

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
