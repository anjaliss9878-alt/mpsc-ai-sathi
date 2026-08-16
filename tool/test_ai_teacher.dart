// Server-side AI Teacher checks. Reads dart_defines.json (never prints secrets).
//
//   dart run tool/test_ai_teacher.dart

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/services/ai_teacher_system/gemini_rest_client.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

Future<void> main() async {
  final defines = jsonDecode(await File('dart_defines.json').readAsString())
      as Map<String, dynamic>;
  final apiKey = '${defines['AI_API_KEY'] ?? ''}'.trim();
  final model = '${defines['AI_MODEL'] ?? 'gemini-flash-latest'}'.trim();
  final elevenKey = '${defines['ELEVENLABS_API_KEY'] ?? ''}'.trim();

  final results = <String, String>{};
  final client = http.Client();

  try {
    results['Gemini key loaded'] = apiKey.isNotEmpty ? 'PASS' : 'FAIL';
    results['ElevenLabs key loaded'] = elevenKey.isNotEmpty ? 'PASS' : 'FAIL';

    final detected = detectMpscTeachingSubject('मान्सून');
    results['Subject detect मान्सून'] =
        detected == MpscTeachingSubject.geography ? 'PASS' : 'FAIL (${detected.id})';

    if (apiKey.isEmpty) {
      results['Gemini connection'] = 'FAIL';
      results['Notes'] = 'FAIL';
      results['MCQ'] = 'FAIL';
      results['PYQ'] = 'FAIL';
      results['Revision'] = 'FAIL';
      results['Memory Tricks'] = 'FAIL';
      results['AI Video slides'] = 'FAIL';
    } else {
      stdout.writeln('Calling Gemini for मान्सून...');
      final gemini = GeminiRestClient(
        apiKey: apiKey,
        model: model,
        client: client,
      );
      try {
        final map = await gemini.generateJson(
          systemPrompt: lessonSystemPrompt(MpscTeachingSubject.geography),
          userText: subjectUserPrompt(
            topic: 'मान्सून',
            subject: MpscTeachingSubject.geography,
          ),
          maxOutputTokens: 16384,
        );
        final slides = asMapList(map['slides']);
        final mcqs = asMapList(map['mcqs']);
        final pyqs = asMapList(map['pyqs']);
        final notes = asStringList(map['notes']);
        final concepts = asStringList(map['concepts']);
        final tricks = asStringList(map['memory_tricks']).isNotEmpty
            ? asStringList(map['memory_tricks'])
            : asStringList(
                (map['premium'] is Map)
                    ? (map['premium'] as Map)['memoryTricks']
                    : null,
              );
        final revision = '${map['revision_points'] ?? map['summary'] ?? ''}';
        final blob = jsonEncode(map);
        final monsoon =
            blob.contains('मान्सून') || blob.toLowerCase().contains('monsoon');
        final parliament = blob.contains('संसद') && !monsoon;

        results['Gemini connection'] = 'PASS';
        results['Subject in lesson'] =
            '${map['subject'] ?? map['subjectName'] ?? ''}'.contains('भूगोल') ||
                    '${map['subject'] ?? map['subjectName'] ?? ''}'
                        .toLowerCase()
                        .contains('geo')
                ? 'PASS'
                : 'FAIL (${map['subject'] ?? map['subjectName']})';
        results['Marathi script'] =
            '${map['teaching_script'] ?? map['script'] ?? ''}'.trim().isNotEmpty
                ? 'PASS'
                : 'FAIL';
        results['Notes'] = notes.isNotEmpty ||
                concepts.isNotEmpty ||
                '${map['introduction'] ?? ''}'.trim().isNotEmpty
            ? 'PASS'
            : 'FAIL';
        results['MCQ'] =
            mcqs.length >= 8 ? 'PASS (${mcqs.length})' : 'FAIL (${mcqs.length})';
        results['PYQ'] =
            pyqs.length >= 6 ? 'PASS (${pyqs.length})' : 'FAIL (${pyqs.length})';
        results['Revision'] = revision.trim().isNotEmpty ? 'PASS' : 'FAIL';
        results['Memory Tricks'] = tricks.isNotEmpty ? 'PASS' : 'FAIL';
        results['AI Video slides'] =
            slides.length >= 8 && monsoon && !parliament
                ? 'PASS (${slides.length})'
                : 'FAIL (slides=${slides.length} monsoon=$monsoon parliament=$parliament)';
        stdout.writeln(
          'slides=${slides.map((s) => s['title']).join(' | ')}',
        );

        try {
          final doubt = await gemini.generateText(
            systemPrompt:
                'Answer in Marathi about the current topic only. Topic: मान्सून. '
                'If unrelated, refuse.',
            userText: 'नैऋत्य मान्सून महाराष्ट्रात का महत्त्वाचा आहे?',
          );
          results['Ask AI Doubt'] = doubt.trim().isNotEmpty &&
                  (doubt.contains('मान्सून') || doubt.contains('महाराष्ट्र'))
              ? 'PASS'
              : 'FAIL';
        } catch (e) {
          stderr.writeln('Ask AI failed: $e');
          results['Ask AI Doubt'] = 'FAIL';
        }
      } catch (e, st) {
        stderr.writeln('Gemini lesson failed: $e\n$st');
        results['Gemini connection'] = 'FAIL';
        results['Notes'] = 'FAIL';
        results['MCQ'] = 'FAIL';
        results['PYQ'] = 'FAIL';
        results['Revision'] = 'FAIL';
        results['Memory Tricks'] = 'FAIL';
        results['AI Video slides'] = 'FAIL';
      }
    }

    if (elevenKey.isEmpty) {
      results['ElevenLabs connection'] = 'FAIL (key empty)';
    } else {
      try {
        final voice = MpscTeachingSubject.geography.elevenLabsVoiceId;
        final uri = Uri.parse(
          'https://api.elevenlabs.io/v1/text-to-speech/$voice',
        );
        final response = await client
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'xi-api-key': elevenKey,
                'Accept': 'audio/mpeg',
              },
              body: jsonEncode({
                'text':
                    'नमस्कार विद्यार्थ्यांनो, आज आपण मान्सूनचा अभ्यास करणार आहोत.',
                'model_id': '${defines['ELEVENLABS_MODEL'] ?? 'eleven_multilingual_v2'}',
              }),
            )
            .timeout(const Duration(seconds: 60));
        results['ElevenLabs connection'] =
            response.statusCode >= 200 &&
                    response.statusCode < 300 &&
                    response.bodyBytes.length > 800
                ? 'PASS (${response.bodyBytes.length} bytes)'
                : 'FAIL HTTP ${response.statusCode}';
      } catch (e, st) {
        stderr.writeln('ElevenLabs failed: $e\n$st');
        results['ElevenLabs connection'] = 'FAIL';
      }
    }
  } finally {
    client.close();
  }

  stdout.writeln('\n=== AI Teacher test report ===');
  for (final e in results.entries) {
    stdout.writeln('${e.key}: ${e.value}');
  }
}
