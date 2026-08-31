import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/services/ai_teacher_system/gemini_rest_client.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';

/// Live Gemini lesson JSON for the audio-pipeline topic. Never prints keys.
Future<void> main() async {
  final defines = jsonDecode(File('dart_defines.json').readAsStringSync());
  final map = Map<String, dynamic>.from(defines as Map);
  final apiKey = '${map['AI_API_KEY'] ?? ''}'.trim();
  final model = '${map['AI_MODEL'] ?? 'gemini-flash-lite-latest'}'.trim();
  const topic = 'भारतीय राज्यघटनेतील मूलभूत अधिकार';
  final gemini = GeminiRestClient(
    apiKey: apiKey,
    model: model,
    client: http.Client(),
  );
  final json = await gemini.generateJson(
    systemPrompt: compactLessonSystemPrompt(MpscTeachingSubject.polity),
    userText: chapterUserPrompt(topic: topic, subject: MpscTeachingSubject.polity),
    temperature: 0.35,
    maxOutputTokens: 8192,
  );
  final title = '${json['topicName'] ?? json['title'] ?? topic}';
  final slides = json['slides'];
  final script = json['script'] ?? json['teaching_script'];
  final slideCount = slides is List ? slides.length : 0;
  var scriptChars = 0;
  if (script is List) {
    scriptChars = script.map((e) => '$e').join(' ').length;
  } else {
    scriptChars = '$script'.length;
  }
  stdout.writeln('topic=$topic');
  stdout.writeln('title=$title');
  stdout.writeln('slides=$slideCount');
  stdout.writeln('scriptChars=$scriptChars');
  stdout.writeln(slideCount >= 3 && scriptChars > 40 ? 'SCRIPT_SLIDES=PASS' : 'SCRIPT_SLIDES=FAIL');
}
