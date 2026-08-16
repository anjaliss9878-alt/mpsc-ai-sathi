import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/classroom_video/classroom_lecture.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Gemini: topic → subject-wise Marathi teaching script + 8–12 slides.
class ClassroomScriptService {
  ClassroomScriptService({
    required this.apiKey,
    this.model = 'gemini-flash-latest',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  Future<ClassroomLecture> generateFromTopic({
    required String topic,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw StateError('Gemini API key is missing');
    }
    final focus = topic.trim();
    if (focus.isEmpty) {
      throw StateError('Please enter a topic');
    }

    final subject = detectMpscTeachingSubject(focus);
    final prompt = _prompt(focus, subject);
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:generateContent',
    );
    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.35,
        'maxOutputTokens': 8192,
      },
    });

    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: body,
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      final snippet = response.body.length > 240
          ? response.body.substring(0, 240)
          : response.body;
      throw StateError(
        'Gemini script failed HTTP ${response.statusCode}: $snippet',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = asMapList(decoded['candidates']);
    if (candidates.isEmpty) {
      throw StateError('Gemini returned no lecture');
    }
    final content = candidates.first['content'];
    final contentMap =
        content is Map ? Map<String, dynamic>.from(content) : <String, dynamic>{};
    final parts = asMapList(contentMap['parts']);
    final text = parts.isNotEmpty ? parts.first['text'] as String? : null;
    if (text == null || text.trim().isEmpty) {
      throw StateError('Gemini returned an empty lecture');
    }

    final map = jsonDecode(stripJsonFences(text));
    if (map is! Map) {
      throw StateError('Gemini lecture was not a JSON object');
    }
    final lecture = ClassroomLecture.fromMap(Map<String, dynamic>.from(map));
    if (lecture.slides.length < 8 || lecture.narration.trim().isEmpty) {
      throw StateError('Lecture was incomplete (need slides and narration)');
    }
    return lecture;
  }

  String _prompt(String topic, MpscTeachingSubject subject) {
    return '''
You ARE the ${subject.displayName} for MPSC COMBINE AI (Combined Group B and C).
${subject.classroomHook}
Teach the student topic: "$topic".
This is a live classroom lecture. One continuous Marathi narration. Synchronized slides.

Return ONE JSON object only (no markdown fences, no commentary):
{
  "title": "short Marathi title",
  "narration": "one continuous Marathi lecture (3 to 5 minutes when spoken)",
  "slides": [
    {
      "heading": "one concept, Marathi",
      "points": ["short board point", "short board point"],
      "spoken": "the exact Marathi sentences spoken while this slide is shown"
    }
  ]
}

RULES:
- 8 to 12 slides. One concept per slide.
- "spoken" texts concatenated MUST equal the full lecture, in order, with no gaps.
- Narration is one continuous natural Marathi classroom lecture.
- No English sentences. No English letter-by-letter spelling.
- NEVER put these characters in narration or spoken: + - / % • * # = @
- NEVER mention page numbers, figure numbers, bullets, or symbols.
- Expand abbreviations in spoken text (GDP → जी डी पी, MPSC → एम पी एस सी, RBI → आर बी आय, % → टक्के).
- Board "points": 2–4 short phrases, not full paragraphs.
- Teach in THIS subject's style only. Do not use a generic tutor voice.

${_videoSubjectBrief(subject)}
''';
  }
}

String _videoSubjectBrief(MpscTeachingSubject subject) {
  switch (subject) {
    case MpscTeachingSubject.polity:
      return '''
POLITY: constitutional Marathi, articles when known, flowcharts and comparison, PYQ traps.
''';
    case MpscTeachingSubject.history:
      return '''
HISTORY: storytelling, chronology, causes and consequences, timeline, memory hooks.
''';
    case MpscTeachingSubject.geography:
      return '''
GEOGRAPHY: location first, maps, rivers/climate/soil diagrams, Maharashtra and India.
''';
    case MpscTeachingSubject.economics:
      return '''
ECONOMICS: daily-life examples, GDP/inflation/budget/RBI in Marathi, graphs, टक्के not %.
''';
    case MpscTeachingSubject.science:
      return '''
SCIENCE: concepts, diagrams, applications, exam-oriented facts. Simple Marathi.
''';
    case MpscTeachingSubject.environment:
      return '''
ENVIRONMENT: ecosystem/food-chain diagrams, conservation, pollution, biodiversity.
''';
  }
}
