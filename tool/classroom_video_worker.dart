// Local classroom video backend.
//
// Topic → Gemini Marathi script → one ElevenLabs audio file → synced slides
// → FFmpeg MP4 → Firebase Storage → Firestore videoUrl.
//
// Usage (from repo root):
//   powershell -ExecutionPolicy Bypass -File tool\run_classroom_video_backend.ps1
//
// Binds 127.0.0.1:8791. POSTs {jobId, idToken, topic}.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/models/chat_message.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/gemini_rest_client.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lecture_lesson_sanitizer.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/speakable_marathi.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/classroom_video/classroom_lecture.dart';
import 'package:mpsc_combine_ai/services/classroom_video/classroom_video_script.dart';
import 'package:mpsc_combine_ai/services/elevenlabs_tts_service.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

const _projectId = 'mpsc-3f4ef';
const _bucket = 'mpsc-3f4ef.firebasestorage.app';
const _firestoreBase =
    'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/ai_lessons';
const _storageBase =
    'https://firebasestorage.googleapis.com/v0/b/$_bucket/o';

Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ??
      (args.isNotEmpty ? int.tryParse(args.first) : null) ??
      8791;
  final defines = await _loadDefines();
  final apiKey = '${defines['AI_API_KEY'] ?? ''}'.trim();
  final model = '${defines['AI_MODEL'] ?? 'gemini-flash-lite-latest'}'.trim();
  if (apiKey.isEmpty) {
    stderr.writeln('Missing AI_API_KEY in dart_defines.json');
    exit(1);
  }

  final engine = _VideoEngine(defines: defines, apiKey: apiKey, model: model);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Classroom video backend http://127.0.0.1:$port');
  stdout.writeln('Waiting for Generate Video jobs…');

  await for (final request in server) {
    unawaited(_handle(request, engine));
  }
}

Future<void> _handle(HttpRequest request, _VideoEngine engine) async {
  _cors(request.response);
  try {
    if (request.method == 'OPTIONS') {
      request.response.statusCode = 204;
      await request.response.close();
      return;
    }
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/health') {
      request.response
        ..statusCode = 200
        ..write('{"ok":true}');
      await request.response.close();
      return;
    }
    if (request.method == 'POST' && path == '/ai/lesson') {
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
      try {
        final lesson = await engine.generateLesson(
          topic: topic,
          subjectContext: subjectContext,
          teachingSubject: teachingSubject,
        );
        request.response.statusCode = 200;
        request.response.write(jsonEncode({'lesson': lesson.toMap()}));
      } catch (e, st) {
        stderr.writeln('ai/lesson failed: $e\n$st');
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'error': '$e'}));
      }
      await request.response.close();
      return;
    }
    if (request.method == 'POST' && path == '/ai/doubt') {
      final body = await utf8.decoder.bind(request).join();
      final map = jsonDecode(body) as Map<String, dynamic>;
      try {
        final reply = await engine.answerDoubt(map);
        request.response.statusCode = 200;
        request.response.write(jsonEncode({'reply': reply}));
      } catch (e, st) {
        stderr.writeln('ai/doubt failed: $e\n$st');
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'error': '$e'}));
      }
      await request.response.close();
      return;
    }
    if (request.method == 'POST' && path == '/ai/tts') {
      final body = await utf8.decoder.bind(request).join();
      final map = jsonDecode(body) as Map<String, dynamic>;
      try {
        final audio = await engine.ttsOnly(map);
        request.response.statusCode = 200;
        request.response.write(jsonEncode(audio));
      } catch (e, st) {
        stderr.writeln('ai/tts failed: $e\n$st');
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'error': '$e'}));
      }
      await request.response.close();
      return;
    }
    if (request.method == 'GET' && path == '/ai/test/gemini') {
      try {
        const prompt =
            "Explain the MPSC topic 'मान्सून' in Marathi. Return a short structured lesson with title, subject, explanation and 5 important exam points.";
        stdout.writeln('[AI-CHAPTER] gemini_request_started test_prompt');
        final gemini = GeminiRestClient(
          apiKey: engine.apiKey,
          model: engine.model,
          client: http.Client(),
        );
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
      } catch (e, st) {
        stderr.writeln('ai/test/gemini failed: $e\n$st');
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'ok': false, 'error': '$e'}));
      }
      await request.response.close();
      return;
    }
    if (request.method == 'GET' && path == '/ai/test/elevenlabs') {
      try {
        final result = await engine.testElevenLabs();
        request.response.statusCode = 200;
        request.response.write(jsonEncode(result));
      } catch (e, st) {
        stderr.writeln('ai/test/elevenlabs failed: $e\n$st');
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'ok': false, 'error': '$e'}));
      }
      await request.response.close();
      return;
    }
    if (request.method == 'POST' && path == '/generate') {
      final body = await utf8.decoder.bind(request).join();
      final map = jsonDecode(body) as Map<String, dynamic>;
      final jobId = '${map['jobId'] ?? ''}'.trim();
      final idToken = '${map['idToken'] ?? ''}'.trim();
      final topic = '${map['topic'] ?? ''}'.trim();
      if (jobId.isEmpty || idToken.isEmpty) {
        request.response.statusCode = 400;
        request.response.write('{"error":"jobId and idToken required"}');
        await request.response.close();
        return;
      }
      request.response.statusCode = 202;
      request.response.write('{"accepted":true}');
      await request.response.close();
      unawaited(engine.run(
        jobId: jobId,
        idToken: idToken,
        topic: topic,
      ));
      return;
    }
    request.response.statusCode = 404;
    await request.response.close();
  } catch (e) {
    stderr.writeln('request error: $e');
    try {
      request.response.statusCode = 500;
      await request.response.close();
    } catch (_) {}
  }
}

void _cors(HttpResponse response) {
  response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    ..set('Access-Control-Allow-Headers', 'Content-Type, Authorization')
    ..set('Content-Type', 'application/json; charset=utf-8');
}

class _VideoEngine {
  _VideoEngine({
    required this.defines,
    required this.apiKey,
    required this.model,
  });

  final Map<String, dynamic> defines;
  final String apiKey;
  final String model;
  final http.Client _http = http.Client();
  final Set<String> _busy = <String>{};

  Future<GeneratedLesson> generateLesson({
    required String topic,
    String subjectContext = '',
    MpscTeachingSubject? teachingSubject,
  }) async {
    final style = teachingSubject ??
        tryDetectMpscTeachingSubject(topic, hint: subjectContext);
    final gemini = GeminiRestClient(
      apiKey: apiKey,
      model: model,
      client: _http,
    );
    final map = await gemini.generateJson(
      systemPrompt: compactLessonSystemPrompt(style),
      userText: chapterUserPrompt(topic: topic, subject: style),
      temperature: 0.35,
      maxOutputTokens: 8192,
    );
    stdout.writeln('[AI-CHAPTER] gemini_response_received topic=$topic');
    var lesson = sanitizeLectureLesson(
      GeneratedLesson.fromMap({
        ...map,
        'question': topic,
        'topicName': '${map['topicName'] ?? map['title'] ?? map['topic'] ?? topic}',
        'subjectName':
            '${map['subjectName'] ?? map['subject'] ?? style?.displayName ?? ''}',
      }, ''),
    );
    stdout.writeln(
      '[AI-CHAPTER] parse_success title=${lesson.topicName} '
      'sections=${lesson.slides.length} notes=${lesson.notes.isNotEmpty} '
      'mcqs=${lesson.mcqs.length} pyqs=${lesson.pyqs.length} '
      'revision=${lesson.premium.quickRevision.trim().isNotEmpty} '
      'tricks=${lesson.premium.memoryTricks.isNotEmpty}',
    );
    if (lesson.mcqs.length < 5) {
      try {
        final extra = await gemini.generateJson(
          systemPrompt: 'Reply with JSON only.',
          userText:
              'Topic: $topic. Create ${(20 - lesson.mcqs.length).clamp(1, 10)} '
              'MPSC MCQs in Marathi. JSON: {"mcqs":[{question,options,correctIndex,explanation,difficulty,kind}]}',
        );
        final more = asMapList(extra['mcqs']).map(GeneratedMcq.fromMap);
        lesson = lesson.copyWith(
          mcqs: [...lesson.mcqs, ...more].take(20).toList(),
        );
      } catch (e) {
        stderr.writeln('mcq top-up skipped: $e');
      }
    }
    if (lesson.pyqs.length < 3) {
      try {
        final extra = await gemini.generateJson(
          systemPrompt: 'Reply with JSON only.',
          userText:
              'Topic: $topic. Create ${(10 - lesson.pyqs.length).clamp(1, 10)} '
              'PYQ-based practice questions in Marathi. Set exam to '
              '"PYQ-based practice question". JSON: {"pyqs":[{question,answer,analysis,exam}]}',
        );
        final more = asMapList(extra['pyqs']).map(GeneratedPyq.fromMap);
        lesson = lesson.copyWith(
          pyqs: [...lesson.pyqs, ...more].take(10).toList(),
        );
      } catch (e) {
        stderr.writeln('pyq top-up skipped: $e');
      }
    }
    return lesson;
  }

  Future<String> answerDoubt(Map<String, dynamic> map) {
    final service = GeminiAiTeacherService(client: _http, apiKey: apiKey);
    final history = <ChatMessage>[];
    final rawHistory = map['history'];
    if (rawHistory is List) {
      for (final item in rawHistory) {
        if (item is! Map) continue;
        final role = '${item['role'] ?? ''}';
        final content = '${item['content'] ?? ''}';
        if (content.trim().isEmpty) continue;
        history.add(
          ChatMessage(
            role: role == 'user' ? ChatRole.user : ChatRole.assistant,
            content: content,
            timestamp: DateTime.now(),
          ),
        );
      }
    }
    return service.sendMessage(
      history: history,
      userMessage: '${map['message'] ?? ''}',
      extraContext: '${map['extraContext'] ?? ''}',
    );
  }

  Future<Map<String, dynamic>> ttsOnly(Map<String, dynamic> map) async {
    final text = speakableMarathi('${map['text'] ?? ''}'.trim());
    final subject = MpscTeachingSubjectX.tryParse('${map['subject'] ?? ''}') ??
        detectMpscTeachingSubject(text);
    final clip = await _synthesize(text, topic: subject.id);
    return {
      'audio_base64': base64Encode(clip.bytes),
      'mimeType': clip.mime,
      'durationMs': clip.duration.inMilliseconds,
      'voiceId': subject.elevenLabsVoiceId,
    };
  }

  Future<Map<String, dynamic>> testElevenLabs() async {
    final key = '${defines['ELEVENLABS_API_KEY'] ?? ''}'.trim();
    if (key.isEmpty) {
      throw StateError(
        'ElevenLabs API key missing. Set ELEVENLABS_API_KEY in dart_defines.json.',
      );
    }
    final clip = await ElevenLabsTtsService(client: _http, apiKey: key)
        .testMarathiGreeting();
    return {
      'ok': true,
      'bytes': clip.bytes.length,
      'durationMs': clip.duration.inMilliseconds,
      'voiceId': clip.voiceId,
    };
  }

  Future<void> run({
    required String jobId,
    required String idToken,
    String topic = '',
  }) async {
    if (!_busy.add(jobId)) {
      stdout.writeln('skip $jobId (already running)');
      return;
    }
    stdout.writeln('job $jobId started');
    try {
      await _progress(
        jobId,
        idToken,
        stage: 'preparing',
        progress: 8,
        message: 'Understanding the topic',
      );
      final job = await _getJob(jobId, idToken);
      final resolvedTopic = topic.trim().isNotEmpty
          ? topic.trim()
          : (job['topic']?.toString() ?? '').trim();
      if (resolvedTopic.isEmpty) {
        throw StateError('Please enter a topic');
      }

      await _progress(
        jobId,
        idToken,
        stage: 'preparing',
        progress: 18,
        message: 'Writing a Marathi teaching script',
      );
      final script = ClassroomScriptService(apiKey: apiKey, model: model);
      final lecture = await script.generateFromTopic(topic: resolvedTopic);

      await _progress(
        jobId,
        idToken,
        stage: 'generating_voice',
        progress: 36,
        message: 'Generating continuous Marathi narration',
      );
      final audio = await _synthesize(
        lecture.narration,
        topic: resolvedTopic,
      );

      await _progress(
        jobId,
        idToken,
        stage: 'creating_scenes',
        progress: 55,
        message: 'Building classroom slides',
      );
      final work = await Directory.systemTemp.createTemp('mpsc_classroom_');
      final durations = lecture.slideDurations(audio.duration);
      final slides = <({String path, double seconds})>[];
      for (var i = 0; i < lecture.slides.length; i++) {
        final png = File('${work.path}${Platform.pathSeparator}slide_$i.png');
        await _renderSlidePng(
          outFile: png,
          topic: lecture.title.isEmpty ? resolvedTopic : lecture.title,
          slide: lecture.slides[i],
          index: i,
          total: lecture.slides.length,
        );
        final seconds = durations[i].inMilliseconds / 1000.0;
        slides.add((path: png.path, seconds: seconds < 0.4 ? 0.4 : seconds));
      }

      await _progress(
        jobId,
        idToken,
        stage: 'rendering_video',
        progress: 72,
        message: 'Rendering the lecture video',
      );
      final ext = audio.mime.contains('mpeg') ? 'mp3' : 'wav';
      final audioPath = '${work.path}${Platform.pathSeparator}narration.$ext';
      await File(audioPath).writeAsBytes(audio.bytes, flush: true);
      final outPath = '${work.path}${Platform.pathSeparator}lecture.mp4';
      await _encodeMp4(
        workDir: work.path,
        slides: slides,
        audioPath: audioPath,
        outputPath: outPath,
      );

      await _progress(
        jobId,
        idToken,
        stage: 'uploading',
        progress: 90,
        message: 'Saving the video',
      );
      final videoBytes = await File(outPath).readAsBytes();
      if (videoBytes.length < 8000) {
        throw StateError('Rendered video was empty');
      }
      final videoPath = 'videos/ai_lessons/$jobId.mp4';
      await _uploadStorage(
        path: videoPath,
        bytes: videoBytes,
        contentType: 'video/mp4',
        idToken: idToken,
      );
      final audioStorage = 'audio/$jobId.$ext';
      await _uploadStorage(
        path: audioStorage,
        bytes: audio.bytes,
        contentType: audio.mime,
        idToken: idToken,
      );

      await _patch(jobId, idToken, {
        'status': 'ready',
        'stage': 'ready',
        'progress': 100,
        'etaSeconds': 0,
        'audioUrl': audioStorage,
        'videoUrl': videoPath,
        'duration': audio.duration.inMilliseconds / 1000.0,
        'playbackMode': 'video',
        'friendlyMessage': 'Ready to watch',
        'errorMessage': '',
        'script': [lecture.narration],
      });
      stdout.writeln('job $jobId ready ${videoBytes.length} bytes');
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    } catch (e, st) {
      stderr.writeln('job $jobId failed: $e\n$st');
      try {
        await _patch(jobId, idToken, {
          'status': 'failed',
          'progress': 0,
          'friendlyMessage': 'Video could not be prepared. Please try again.',
          'errorMessage': '$e'.length > 400 ? '$e'.substring(0, 400) : '$e',
        });
      } catch (_) {}
    } finally {
      _busy.remove(jobId);
    }
  }

  Future<void> _progress(
    String jobId,
    String idToken, {
    required String stage,
    required int progress,
    required String message,
  }) {
    return _patch(jobId, idToken, {
      'status': 'generating',
      'stage': stage,
      'progress': progress,
      'friendlyMessage': message,
      'errorMessage': '',
    });
  }

  Future<_Audio> _synthesize(String narration, {required String topic}) async {
    final text = speakableMarathi(narration.trim());
    if (text.isEmpty) throw StateError('Empty narration');
    final key = '${defines['ELEVENLABS_API_KEY'] ?? ''}'.trim();
    if (key.isEmpty) {
      throw StateError(
        'ElevenLabs API key missing. Set ELEVENLABS_API_KEY in dart_defines.json.',
      );
    }
    final eleven = ElevenLabsTtsService(client: _http, apiKey: key);
    final subject = detectMpscTeachingSubject(topic);
    stdout.writeln(
      'ElevenLabs one-file TTS subject=${subject.id} chars=${text.length}',
    );
    final clip = await eleven.synthesizeLesson(text: text, subject: subject);
    return _Audio(
      bytes: clip.bytes,
      mime: clip.mimeType,
      duration: clip.duration,
    );
  }

  Future<void> _renderSlidePng({
    required File outFile,
    required String topic,
    required ClassroomSlide slide,
    required int index,
    required int total,
  }) async {
    final ffmpeg = _ffmpeg();
    final font = _marathiFont();
    final dir = outFile.parent.path;
    final headingFile = File('$dir${Platform.pathSeparator}h_$index.txt');
    final bodyFile = File('$dir${Platform.pathSeparator}b_$index.txt');
    final brandFile = File('$dir${Platform.pathSeparator}brand_$index.txt');
    await brandFile.writeAsString(
      'MPSC COMBINE AI  |  ${_oneLine(topic, 42)}',
      encoding: utf8,
    );
    await headingFile.writeAsString(
      _wrap(_oneLine(slide.heading, 80), 28),
      encoding: utf8,
    );
    final body = StringBuffer();
    for (final point in slide.points.take(4)) {
      body.writeln('• ${_wrap(_oneLine(point, 90), 36)}');
      body.writeln();
    }
    await bodyFile.writeAsString(body.toString().trim(), encoding: utf8);

    String ff(String path) => File(path).absolute.path.replaceAll(r'\', '/');
    String ffFilterPath(String path) {
      final p = ff(path).replaceAll(r'\', r'\\').replaceAll(':', r'\:');
      return "'$p'";
    }

    final vf = [
      'drawbox=x=0:y=0:w=1280:h=72:color=0x0A1F44:t=fill',
      'drawbox=x=0:y=72:w=1280:h=8:color=0xFF9933:t=fill',
      "drawtext=fontfile=${ffFilterPath(font)}:textfile=${ffFilterPath(brandFile.path)}:fontcolor=white:fontsize=26:x=36:y=22",
      "drawtext=fontfile=${ffFilterPath(font)}:textfile=${ffFilterPath(headingFile.path)}:fontcolor=0x0A1F44:fontsize=40:x=64:y=120:line_spacing=12",
      "drawtext=fontfile=${ffFilterPath(font)}:textfile=${ffFilterPath(bodyFile.path)}:fontcolor=0x1A3568:fontsize=30:x=72:y=250:line_spacing=10",
      "drawtext=fontfile=${ffFilterPath(font)}:text='${index + 1} / $total':fontcolor=0xFF6B2B:fontsize=22:x=w-text_w-40:y=h-48",
    ].join(',');

    final result = await Process.run(ffmpeg, [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'color=c=0xFFFFFF:s=1280x720:d=0.12',
      '-vf',
      vf,
      '-frames:v',
      '1',
      ff(outFile.path),
    ]);
    if (result.exitCode != 0 || !outFile.existsSync() || outFile.lengthSync() < 800) {
      stderr.writeln(result.stderr);
      throw StateError('Could not render slide ${index + 1}');
    }
  }

  Future<void> _encodeMp4({
    required String workDir,
    required List<({String path, double seconds})> slides,
    required String audioPath,
    required String outputPath,
  }) async {
    final ffmpeg = _ffmpeg();
    final listPath = '$workDir${Platform.pathSeparator}slides_concat.txt';
    final sink = File(listPath).openWrite();
    for (final s in slides) {
      final abs = File(s.path).absolute.path.replaceAll(r'\', '/');
      final escaped = abs.replaceAll("'", r"'\''");
      sink.writeln("file '$escaped'");
      sink.writeln('duration ${s.seconds.toStringAsFixed(3)}');
    }
    final last = File(slides.last.path).absolute.path.replaceAll(r'\', '/');
    sink.writeln("file '${last.replaceAll("'", r"'\''")}'");
    await sink.close();

    String ff(String path) => File(path).absolute.path.replaceAll(r'\', '/');
    final args = <String>[
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      ff(listPath),
      '-i',
      ff(audioPath),
      '-vf',
      'fps=30,format=yuv420p',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '22',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-shortest',
      '-movflags',
      '+faststart',
      ff(outputPath),
    ];
    stdout.writeln('FFmpeg ${args.join(' ')}');
    final proc = await Process.start(ffmpeg, args, workingDirectory: workDir);
    final err = StringBuffer();
    proc.stderr.transform(const SystemEncoding().decoder).listen(err.write);
    final code = await proc.exitCode;
    if (code != 0) {
      throw StateError('FFmpeg failed: ${err.toString().trim()}');
    }
  }

  String _ffmpeg() {
    final local = File('${Directory.current.path}${Platform.pathSeparator}.tools'
        '${Platform.pathSeparator}ffmpeg${Platform.pathSeparator}ffmpeg.exe');
    if (local.existsSync()) return local.path;
    return 'ffmpeg';
  }

  String _marathiFont() {
    const candidates = [
      r'C:\Windows\Fonts\Nirmala.ttf',
      r'C:\Windows\Fonts\nirmala.ttf',
      r'C:\Windows\Fonts\NirmalaUI.ttf',
      r'C:\Windows\Fonts\mangal.ttf',
      r'C:\Windows\Fonts\Mangal.ttf',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    throw StateError('No Marathi font found (install Nirmala UI)');
  }

  Future<Map<String, String>> _getJob(String id, String token) async {
    final res = await _http
        .get(
          Uri.parse('$_firestoreBase/$id'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw StateError('Could not load job');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final fields = map['fields'];
    if (fields is! Map) throw StateError('Job document was empty');
    return {
      'pdfPath': _fsString(fields['pdfPath']),
      'topic': _fsString(fields['topic']),
      'uid': _fsString(fields['uid']),
    };
  }

  Future<void> _patch(
    String id,
    String token,
    Map<String, dynamic> data,
  ) async {
    final fields = <String, dynamic>{};
    for (final e in data.entries) {
      fields[e.key] = _fsEncode(e.value);
    }
    final mask = data.keys
        .map((k) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent(k)}')
        .join('&');
    final res = await _http
        .patch(
          Uri.parse('$_firestoreBase/$id?$mask'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'fields': fields}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw StateError('Could not update job (${res.statusCode})');
    }
  }

  Future<void> _uploadStorage({
    required String path,
    required Uint8List bytes,
    required String contentType,
    required String idToken,
  }) async {
    final uri = Uri.parse(
      '$_storageBase?name=${Uri.encodeComponent(path)}',
    );
    final res = await _http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': contentType,
          },
          body: bytes,
        )
        .timeout(const Duration(minutes: 3));
    if (res.statusCode >= 300) {
      throw StateError('Could not upload $path (${res.statusCode})');
    }
  }
}

class _Audio {
  const _Audio({
    required this.bytes,
    required this.mime,
    required this.duration,
  });
  final Uint8List bytes;
  final String mime;
  final Duration duration;
}

Object _fsEncode(Object? value) {
  if (value is int) return {'integerValue': '$value'};
  if (value is double) return {'doubleValue': value};
  if (value is bool) return {'booleanValue': value};
  if (value is List) {
    return {
      'arrayValue': {
        'values': [for (final e in value) _fsEncode(e)],
      },
    };
  }
  return {'stringValue': '$value'};
}

String _fsString(dynamic field) {
  if (field is Map && field['stringValue'] != null) {
    return '${field['stringValue']}';
  }
  return '';
}

String _oneLine(String text, int max) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max).trim()}…';
}

String _wrap(String text, int width) {
  if (text.length <= width) return text;
  final words = text.split(' ');
  final lines = <String>[];
  final buf = StringBuffer();
  for (final w in words) {
    final next = buf.isEmpty ? w : '${buf.toString()} $w';
    if (next.length > width && buf.isNotEmpty) {
      lines.add(buf.toString());
      buf
        ..clear()
        ..write(w);
    } else {
      buf
        ..clear()
        ..write(next);
    }
  }
  if (buf.isNotEmpty) lines.add(buf.toString());
  return lines.take(4).join('\n');
}

Future<Map<String, dynamic>> _loadDefines() async {
  final file = File('dart_defines.json');
  if (!file.existsSync()) return {};
  final map = jsonDecode(file.readAsStringSync());
  if (map is Map<String, dynamic>) return map;
  if (map is Map) return Map<String, dynamic>.from(map);
  return {};
}
