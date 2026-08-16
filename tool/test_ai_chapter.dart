// Live AI Teacher chapter checks. Never prints API keys.
//
//   dart run tool/test_ai_chapter.dart

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/services/ai_teacher_system/gemini_rest_client.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

const _exactPrompt =
    "Explain the MPSC topic 'मान्सून' in Marathi. Return a short structured lesson with title, subject, explanation and 5 important exam points.";

Future<void> main() async {
  final defines = jsonDecode(await File('dart_defines.json').readAsString())
      as Map<String, dynamic>;
  final apiKey = '${defines['AI_API_KEY'] ?? ''}'.trim();
  final model = '${defines['AI_MODEL'] ?? 'gemini-2.0-flash'}'.trim();
  final results = <String, String>{};
  final client = http.Client();

  stdout.writeln('=== Topic detection ===');
  final expected = <String, MpscTeachingSubject>{
    'मान्सून': MpscTeachingSubject.geography,
    'गंगा नदी': MpscTeachingSubject.geography,
    'मूलभूत अधिकार': MpscTeachingSubject.polity,
    '1857 चा उठाव': MpscTeachingSubject.history,
    'महागाई': MpscTeachingSubject.economics,
  };
  var detectPass = true;
  for (final e in expected.entries) {
    final got = detectMpscTeachingSubject(e.key);
    final ok = got == e.value;
    detectPass = detectPass && ok;
    stdout.writeln(
      '  ${e.key} -> ${got.nameEn} ${ok ? 'PASS' : 'FAIL (want ${e.value.nameEn})'}',
    );
  }
  results['Topic detection'] = detectPass ? 'PASS' : 'FAIL';

  if (apiKey.isEmpty) {
    results['Gemini API'] = 'FAIL';
    results['Chapter generation'] = 'FAIL';
    _printReport(results);
    exit(1);
  }

  final gemini = GeminiRestClient(
    apiKey: apiKey,
    model: model,
    client: client,
  );

  stdout.writeln('=== Exact Gemini test prompt ===');
  try {
    final text = await gemini.generateText(
      systemPrompt: 'You are an MPSC Marathi teacher. Reply in Marathi.',
      userText: _exactPrompt,
    );
    final monsoon = text.contains('मान्सून') ||
        text.toLowerCase().contains('monsoon');
    stdout.writeln('  chars=${text.length} monsoon=$monsoon');
    stdout.writeln(
      '  preview=${text.length > 220 ? text.substring(0, 220) : text}',
    );
    results['Gemini API'] =
        text.trim().isNotEmpty && monsoon ? 'PASS' : 'FAIL';
  } catch (e) {
    stdout.writeln('  ERROR $e');
    results['Gemini API'] = 'FAIL';
  }

  stdout.writeln('=== Chapter JSON for मान्सून ===');
  try {
    final map = await gemini.generateJson(
      systemPrompt:
          'You are an MPSC Combined Group B/C Marathi teacher. Reply with one JSON object only. Teach the exact student topic. Never substitute संसद/Parliament unless that is the topic.',
      userText: chapterUserPrompt(
        topic: 'मान्सून',
        subject: MpscTeachingSubject.geography,
      ),
      maxOutputTokens: 8192,
    );
    final title = '${map['title'] ?? map['topicName'] ?? ''}';
    final subject = '${map['subject'] ?? map['subjectName'] ?? ''}';
    final intro = '${map['introduction'] ?? ''}';
    final explanation = '${map['explanation'] ?? map['summary'] ?? ''}';
    final notes = asStringList(map['notes']);
    final points = asStringList(map['importantPoints']).isNotEmpty
        ? asStringList(map['importantPoints'])
        : asStringList(map['important_facts']);
    final tricks = asStringList(map['memoryTricks']).isNotEmpty
        ? asStringList(map['memoryTricks'])
        : asStringList(map['memory_tricks']);
    final revision = asStringList(map['revision']).isNotEmpty
        ? asStringList(map['revision'])
        : asStringList(map['revision_points']);
    final mcqs = asMapList(map['mcqs']);
    final pyqs = asMapList(map['pyqs']);
    final slides = asMapList(map['slides']);
    final blob = jsonEncode(map);
    final aboutMonsoon =
        blob.contains('मान्सून') || blob.toLowerCase().contains('monsoon');
    final parliament = blob.contains('संसद') && !aboutMonsoon;

    stdout.writeln('  title=$title');
    stdout.writeln('  subject=$subject');
    stdout.writeln('  sections=${slides.length}');
    stdout.writeln('  notes=${notes.isNotEmpty || explanation.isNotEmpty}');
    stdout.writeln('  tricks=${tricks.length}');
    stdout.writeln('  revision=${revision.isNotEmpty}');
    stdout.writeln('  mcqs=${mcqs.length}');
    stdout.writeln('  pyqs=${pyqs.length}');

    results['Chapter generation'] =
        aboutMonsoon && !parliament && title.trim().isNotEmpty
            ? 'PASS'
            : 'FAIL';
    results['Notes'] = (notes.isNotEmpty ||
            explanation.trim().isNotEmpty ||
            intro.trim().isNotEmpty ||
            points.isNotEmpty)
        ? 'PASS'
        : 'FAIL';
    results['Tricks'] = tricks.isNotEmpty ? 'PASS' : 'FAIL';
    results['Revision'] = revision.isNotEmpty ||
            '${map['quickRevision'] ?? ''}'.trim().isNotEmpty
        ? 'PASS'
        : 'FAIL';
    results['MCQs'] = mcqs.length >= 5 ? 'PASS' : 'FAIL (${mcqs.length})';
    results['PYQs'] = pyqs.length >= 3 ? 'PASS' : 'FAIL (${pyqs.length})';
    results['UI display'] = 'NOT TESTED IN APP (JSON object ready)';
    results['Firestore'] = 'NOT TESTED (no signed-in write in this script)';
  } catch (e) {
    stdout.writeln('  ERROR $e');
    results['Chapter generation'] = 'FAIL';
    results['Notes'] = 'FAIL';
    results['Tricks'] = 'FAIL';
    results['Revision'] = 'FAIL';
    results['MCQs'] = 'FAIL';
    results['PYQs'] = 'FAIL';
  }

  results['Video'] = 'NOT TESTED YET';
  results['ElevenLabs'] = 'NOT TESTED YET';
  _printReport(results);
  client.close();
}

void _printReport(Map<String, String> results) {
  stdout.writeln('');
  stdout.writeln('=== REPORT ===');
  for (final e in results.entries) {
    stdout.writeln('${e.key}: ${e.value}');
  }
}
