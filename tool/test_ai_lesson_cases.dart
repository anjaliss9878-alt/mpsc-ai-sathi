// Live AI Teacher lesson checks. Never prints API keys.
//
//   dart run tool/test_ai_lesson_cases.dart

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/services/ai_teacher_system/gemini_rest_client.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/utils/ai_generation_error.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

Future<void> main() async {
  final defines = jsonDecode(await File('dart_defines.json').readAsString())
      as Map<String, dynamic>;
  final apiKey = '${defines['AI_API_KEY'] ?? ''}'.trim();
  final model = '${defines['AI_MODEL'] ?? 'gemini-flash-lite-latest'}'.trim();
  final results = <String, String>{};
  final client = http.Client();

  results['Gemini key loaded'] = apiKey.isNotEmpty ? 'PASS' : 'FAIL';
  if (apiKey.isEmpty) {
    results['Gemini connection'] = 'FAIL';
    results['API request'] = 'FAIL';
    results['Response parsing'] = 'FAIL';
    results['राज्यव्यवस्था शिक्षक'] = 'FAIL';
    results['भूगोल शिक्षक'] = 'FAIL';
    results['इतिहास शिक्षक'] = 'FAIL';
    results['AI Lesson generation'] = 'FAIL';
    _print(results);
    exit(1);
  }

  final gemini = GeminiRestClient(
    apiKey: apiKey,
    model: model,
    client: client,
  );

  try {
    final ping = await gemini.generateJson(
      systemPrompt: 'Reply with JSON only.',
      userText: 'Return {"ok":true,"topic":"ping"}',
      maxOutputTokens: 64,
    );
    results['Gemini connection'] = ping['ok'] == true ? 'PASS' : 'FAIL';
    results['API request'] = 'PASS';
  } catch (e) {
    stderr.writeln('Gemini ping failed: ${classifyAiGenerationFailure(e)}');
    results['Gemini connection'] = 'FAIL (${classifyAiGenerationFailure(e)})';
    results['API request'] = 'FAIL';
  }

  final cases = <String, (MpscTeachingSubject, String, List<String>)>{
    'राज्यव्यवस्था शिक्षक': (
      MpscTeachingSubject.polity,
      'संसद',
      ['संसद', 'लोकसभा', 'राज्यसभा'],
    ),
    'भूगोल शिक्षक': (
      MpscTeachingSubject.geography,
      'मान्सून',
      ['मान्सून', 'monsoon', 'नैऋत्य'],
    ),
    'इतिहास शिक्षक': (
      MpscTeachingSubject.history,
      '1857 चा उठाव',
      ['1857', 'उठाव', 'बंड'],
    ),
  };

  var parsePass = results['API request'] == 'PASS';
  var allLessons = true;

  for (final entry in cases.entries) {
    final subject = entry.value.$1;
    final topic = entry.value.$2;
    final needles = entry.value.$3;
    stdout.writeln('Generating ${entry.key} + $topic ...');
    try {
      final map = await gemini.generateJson(
        systemPrompt: compactLessonSystemPrompt(subject),
        userText: chapterUserPrompt(topic: topic, subject: subject),
        maxOutputTokens: 8192,
      );
      final encoded = jsonEncode(map);
      final blob = encoded.toLowerCase();
      final aboutTopic = needles.any(
        (n) => encoded.contains(n) || blob.contains(n.toLowerCase()),
      );
      final title = '${map['title'] ?? map['topicName'] ?? map['topic'] ?? ''}'.trim();
      final intro = '${map['introduction'] ?? ''}'.trim();
      final script =
          '${map['teaching_script'] ?? map['teachingScript'] ?? ''}'.trim();
      final concepts = asStringList(map['concepts']);
      final facts = asStringList(map['important_facts']);
      final mpsc = asStringList(map['mpsc_points']);
      final slides = asMapList(map['slides']);
      final subjectField =
          '${map['subject'] ?? map['subjectName'] ?? ''}'.toLowerCase();
      final styleHit = subjectField.contains(subject.nameEn.toLowerCase()) ||
          subjectField.contains(subject.nameMr);
      final hasBody = intro.isNotEmpty ||
          script.isNotEmpty ||
          slides.isNotEmpty ||
          concepts.isNotEmpty;
      final hasStructure = title.isNotEmpty &&
          (concepts.isNotEmpty || facts.isNotEmpty || mpsc.isNotEmpty);
      final ok = aboutTopic && hasBody && hasStructure;
      results[entry.key] = ok
          ? 'PASS'
          : 'FAIL (topic=$aboutTopic body=$hasBody structure=$hasStructure style=$styleHit)';
      stdout.writeln(
        '  title=$title subject=${map['subject'] ?? map['subjectName']} '
        'slides=${slides.length} concepts=${concepts.length} '
        'facts=${facts.length} script=${script.isNotEmpty}',
      );
      parsePass = parsePass && hasBody && hasStructure;
      allLessons = allLessons && ok;
    } catch (e, st) {
      stderr.writeln('${entry.key} failed: ${classifyAiGenerationFailure(e)}\n$st');
      results[entry.key] = 'FAIL (${classifyAiGenerationFailure(e)})';
      parsePass = false;
      allLessons = false;
    }
  }

  results['Response parsing'] = parsePass ? 'PASS' : 'FAIL';
  results['AI Lesson generation'] = allLessons ? 'PASS' : 'FAIL';
  _print(results);
  client.close();
  if (!allLessons || results['Gemini connection'] != 'PASS') {
    exit(1);
  }
}

void _print(Map<String, String> results) {
  stdout.writeln('\n=== AI Lesson generation report ===');
  for (final e in results.entries) {
    stdout.writeln('${e.key}: ${e.value}');
  }
}
