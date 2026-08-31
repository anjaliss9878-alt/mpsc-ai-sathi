import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:mpsc_combine_ai/services/ai_backend_base.dart';
import 'package:mpsc_combine_ai/services/backend_request_headers.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_chapter_debug.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/chapter_lesson_loader.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/gemini_rest_client.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lecture_lesson_sanitizer.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/verified_notes_lesson_composer.dart';
import 'package:mpsc_combine_ai/utils/ai_generation_error.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Thrown whenever a full lesson could not be generated.
class LessonGenerationException implements Exception {
  const LessonGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Abstraction over "turn a question / chapter into a full classroom lesson".
abstract class LessonGenerationService {
  Future<GeneratedLesson> generateLesson({
    required String question,
    String? subjectContext,
    MpscTeachingSubject? teachingSubject,
  });

  /// Builds a Video Lesson Engine package grounded in Firebase chapter notes
  /// (and an optional PDF attached as multimodal input).
  Future<GeneratedLesson> generateChapterLesson({
    required ChapterLessonSource source,
  });

  /// Re-generate after classroom-quality gaps were detected.
  Future<GeneratedLesson> regenerateChapterLessonForQuality({
    required ChapterLessonSource source,
    required String qualityRepairInstruction,
  });

  /// Extra spoken Marathi example for "Give Another Example".
  Future<String> generateAnotherExample({
    required String topic,
    String? subjectContext,
    String? priorExampleHint,
  });

  /// Extra MCQs for "Generate More MCQs".
  Future<List<GeneratedMcq>> generateMoreMcqs({
    required String topic,
    String? subjectContext,
    int count = 3,
  });
}

String get kLessonSystemPrompt =>
    lessonSystemPrompt(MpscTeachingSubject.polity);

class GeminiLessonGenerationService implements LessonGenerationService {
  GeminiLessonGenerationService({
    http.Client? client,
    String? apiKey,
    String? model,
    this.useBackend = true,
  })  : _client = client ?? http.Client(),
        _apiKey = (apiKey ?? _envKey).trim(),
        _model = _resolveModel(model);

  final http.Client _client;
  final String _apiKey;
  final String _model;
  final bool useBackend;

  static const String _envKey = String.fromEnvironment('AI_API_KEY');
  static const String _envModel = String.fromEnvironment(
    'AI_MODEL',
    defaultValue: 'gemini-flash-lite-latest',
  );

  String get _workerBase => aiBackendBase();

  static String _resolveModel(String? model) {
    final m = (model ?? _envModel).trim();
    return m.isEmpty ? 'gemini-flash-lite-latest' : m;
  }

  @override
  Future<GeneratedLesson> generateLesson({
    required String question,
    String? subjectContext,
    MpscTeachingSubject? teachingSubject,
  }) async {
    final style = teachingSubject ??
        tryDetectMpscTeachingSubject(question, hint: subjectContext);
    aiChapterLog('service_generate_start', {
      'topic': question,
      'detected_subject': style?.nameEn ?? 'auto',
      'web': kIsWeb,
    });

    final healthy = useBackend ? await _backendHealthy() : false;
    if (healthy) {
      try {
        final lesson = await _generateViaBackend(
          question: question,
          subjectContext: subjectContext,
          teachingSubject: style,
        );
        return _finishGenerated(lesson, question, style, subjectContext);
      } catch (e) {
        aiChapterLog('backend_failed_fallback_direct', {
          'error': classifyAiGenerationFailure(e),
          'web': kIsWeb,
        });
        if (kIsWeb) {
          throw LessonGenerationException(classifyAiGenerationFailure(e));
        }
      }
    } else if (kIsWeb) {
      aiChapterLog('backend_unavailable', {'base': _workerBase});
      throw const LessonGenerationException('network error');
    }

    final userPrompt = chapterUserPrompt(topic: question, subject: style);
    final lesson = await _generate(
      userParts: [
        {'text': userPrompt},
      ],
      question: question,
      subjectFallback: style?.displayName ?? subjectContext,
      teachingSubject: style,
      compact: true,
    );
    return _finishGenerated(lesson, question, style, subjectContext);
  }

  Future<GeneratedLesson> _finishGenerated(
    GeneratedLesson lesson,
    String question,
    MpscTeachingSubject? style,
    String? subjectContext,
  ) async {
    var out = lesson.copyWith(
      sourceKind: LessonSourceKind.aiGenerated,
      subjectName: (style?.displayName ?? lesson.subjectName),
      topicName: lesson.topicName.trim().isEmpty ? question : lesson.topicName,
      question: question,
    );
    if (isPlaceholderLesson(out, topic: question)) {
      aiChapterLog('placeholder_rejected', {'topic': question});
      throw LessonGenerationException(
        'response parsing error: generated lesson did not match the topic ($question)',
      );
    }
    if (out.mcqs.length < 5) {
      out = await _ensureMcqs(out, question, style?.displayName ?? subjectContext);
    }
    if (out.pyqs.length < 3) {
      out = await _ensurePyqs(out, question, style?.displayName ?? subjectContext);
    }
    aiChapterLog('service_generate_done', {
      'title': out.topicName,
      'sections': out.slides.length,
      'notes': out.notes.isNotEmpty,
      'tricks': out.premium.memoryTricks.isNotEmpty,
      'revision': out.premium.quickRevision.trim().isNotEmpty,
      'mcqs': out.mcqs.length,
      'pyqs': out.pyqs.length,
    });
    return out;
  }

  Future<bool> _backendHealthy() async {
    try {
      final response = await _client
          .get(Uri.parse('$_workerBase/health'))
          .timeout(const Duration(seconds: 8));
      aiChapterLog('backend_health', {'status': response.statusCode});
      return response.statusCode == 200;
    } catch (e) {
      aiChapterLog('backend_health', {'error': '$e'});
      return false;
    }
  }

  Future<GeneratedLesson> _generateViaBackend({
    required String question,
    String? subjectContext,
    MpscTeachingSubject? teachingSubject,
  }) async {
    final uri = Uri.parse('$_workerBase/ai/lesson');
    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: await backendJsonHeaders(),
            body: jsonEncode({
              'topic': question,
              'subjectContext': subjectContext ?? '',
              'teachingSubject': teachingSubject?.id ?? '',
            }),
          )
          .timeout(const Duration(seconds: 240));
    } catch (e) {
      aiChapterLog('backend_unreachable', {'error': '$e'});
      throw LessonGenerationException(classifyAiGenerationFailure(e));
    }
    aiChapterLog('backend_lesson_http', {'status': response.statusCode});
    if (response.statusCode != 200) {
      aiChapterLog('backend_lesson_http', {
        'status': response.statusCode,
        'body': response.body.length > 240
            ? response.body.substring(0, 240)
            : response.body,
      });
      throw LessonGenerationException(
        classifyAiGenerationFailure(
          'HTTP ${response.statusCode} ${response.body}',
        ),
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const LessonGenerationException('response parsing error');
    }
    final map = Map<String, dynamic>.from(decoded);
    if ('${map['error'] ?? ''}'.trim().isNotEmpty) {
      debugPrint('[Gemini] backend error: ${map['error']}');
      throw LessonGenerationException(
        classifyAiGenerationFailure(map['error']!),
      );
    }
    final raw = map['lesson'];
    if (raw is! Map) {
      throw const LessonGenerationException('response parsing error');
    }
    return GeneratedLesson.fromMap(Map<String, dynamic>.from(raw), '');
  }

  @override
  Future<String> generateAnotherExample({
    required String topic,
    String? subjectContext,
    String? priorExampleHint,
  }) async {
    final hint = (priorExampleHint ?? '').trim();
    final ctx = (subjectContext ?? '').trim();
    final prompt = StringBuffer()
      ..writeln('Topic: $topic')
      ..writeln(ctx.isEmpty ? '' : 'Subject: $ctx')
      ..writeln(
        'Give ONE new, different MPSC-relevant classroom EXAMPLE in natural spoken Marathi '
        '(3–5 sentences). Female faculty voice. Do NOT repeat this prior example: '
        '${hint.isEmpty ? '(none)' : hint}',
      )
      ..writeln('Respond with ONLY JSON: {"example":"..."}');
    final map = await _generateJsonMap(
      userParts: [
        {'text': prompt.toString()},
      ],
    );
    final example = (map['example'] as String?)?.trim() ?? '';
    if (example.isEmpty) {
      throw const LessonGenerationException(
        'नवीन उदाहरण मिळाले नाही. कृपया पुन्हा प्रयत्न करा.\n'
        '(Could not generate another example. Please retry.)',
      );
    }
    return example;
  }

  @override
  Future<List<GeneratedMcq>> generateMoreMcqs({
    required String topic,
    String? subjectContext,
    int count = 3,
  }) async {
    final n = count.clamp(1, 8);
    final ctx = (subjectContext ?? '').trim();
    final prompt = StringBuffer()
      ..writeln('Topic: $topic')
      ..writeln(ctx.isEmpty ? '' : 'Subject: $ctx')
      ..writeln(
        'Create EXACTLY $n MPSC practice MCQs in Marathi (or bilingual). '
        'Each: question, options[4], correctIndex, explanation, '
        'wrongExplanations for wrong options. '
        'Respond with ONLY JSON: {"mcqs":[...]}',
      );
    final map = await _generateJsonMap(
      userParts: [
        {'text': prompt.toString()},
      ],
    );
    final mcqs = asMapList(map['mcqs']).map(GeneratedMcq.fromMap).toList();
    if (mcqs.isEmpty) {
      throw const LessonGenerationException(
        'अधिक MCQs तयार झाले नाहीत. कृपया पुन्हा प्रयत्न करा.\n'
        '(Could not generate more MCQs. Please retry.)',
      );
    }
    return mcqs;
  }

  Future<List<GeneratedPyq>> generatePyqs({
    required String topic,
    String? subjectContext,
    int count = 10,
  }) async {
    final n = count.clamp(1, 10);
    final ctx = (subjectContext ?? '').trim();
    final prompt = StringBuffer()
      ..writeln('Topic: $topic')
      ..writeln(ctx.isEmpty ? '' : 'Subject: $ctx')
      ..writeln(
        'Create EXACTLY $n MPSC previous-year-STYLE practice questions in Marathi. '
        'Do NOT claim they are official PYQs. Set exam to "PYQ-based practice question". '
        'Leave year empty. Each: question, answer, analysis. '
        'Respond with ONLY JSON: {"pyqs":[...]}',
      );
    final map = await _generateJsonMap(
      userParts: [
        {'text': prompt.toString()},
      ],
    );
    return asMapList(map['pyqs']).map(GeneratedPyq.fromMap).toList();
  }

  Future<GeneratedLesson> _ensureMcqs(
    GeneratedLesson lesson,
    String topic,
    String? subjectContext,
  ) async {
    var mcqs = [...lesson.mcqs];
    var guard = 0;
    while (mcqs.length < 8 && guard < 2) {
      guard++;
      try {
        final extra = await generateMoreMcqs(
          topic: topic,
          subjectContext: subjectContext ?? lesson.subjectName,
          count: (20 - mcqs.length).clamp(1, 8),
        );
        if (extra.isEmpty) break;
        mcqs = [...mcqs, ...extra];
      } catch (e) {
        debugPrint('[Gemini] MCQ top-up failed: $e');
        break;
      }
    }
    return lesson.copyWith(mcqs: mcqs.take(20).toList());
  }

  Future<GeneratedLesson> _ensurePyqs(
    GeneratedLesson lesson,
    String topic,
    String? subjectContext,
  ) async {
    if (lesson.pyqs.length >= 10) {
      return lesson.copyWith(pyqs: lesson.pyqs.take(10).toList());
    }
    try {
      final extra = await generatePyqs(
        topic: topic,
        subjectContext: subjectContext ?? lesson.subjectName,
        count: (10 - lesson.pyqs.length).clamp(1, 10),
      );
      final merged = [...lesson.pyqs, ...extra].take(10).toList();
      return lesson.copyWith(pyqs: merged);
    } catch (e) {
      debugPrint('[Gemini] PYQ top-up failed: $e');
      return lesson;
    }
  }

  @override
  Future<GeneratedLesson> generateChapterLesson({
    required ChapterLessonSource source,
  }) async {
    final pdfPrimary = source.pdfIsPrimary ||
        (source.pdfBytes != null && source.pdfBytes!.isNotEmpty) ||
        source.pdfStructuredBlocks.isNotEmpty;

    final parts = <Map<String, dynamic>>[
      {
        'text': pdfPrimary
            ? 'FULL CLASSROOM VIDEO LESSON — PDF IS THE PRIMARY SOURCE '
                '(not a summary video):\n'
                'Student topic / chapter: ${source.chapter.title}\n'
                'Subject: ${source.subjectTitle}\n'
                'Target exam: MPSC Combined Group B and C\n\n'
                'PRIMARY SOURCE RULE:\n'
                '- The Topic PDF (attached below and/or structured blocks in the '
                'notes) is the syllabus of truth.\n'
                '- Teach from PDF structure: headings → bullets → tables → '
                'timelines → flowcharts → diagrams → charts.\n'
                '- Mirror those visuals in slide visualType payloads '
                '(table / timeline / flowchart / mindmap / graph).\n'
                '- Do NOT flatten the PDF into one paragraph or one bullet list.\n'
                '- Cover 100% of PDF subtopics. Prefer Marathi as in the PDF.\n'
                '- Text notes below are SECONDARY — use only for gaps; PDF wins '
                'on conflict.\n\n'
                'STEP A — Walk the PDF block-by-block / page structure; that list '
                'is your teaching syllabus.\n'
                'STEP B — Produce 8–15 slides (2–5 minute lecture) that teach that list:\n'
                '  Hook → simple definition → concept explanation → each '
                'subtopic/table/diagram →\n'
                '  examples → important MPSC facts → PYQ connection → memory '
                'tricks →\n'
                '  revision summary → MCQs.\n'
                'STEP C — After EVERY major section, attach ONE sectionQuestion '
                'MCQ.\n'
                'STEP D — Board text minimal; narration is full teacher speech.\n\n'
                '${source.notesText}'
            : 'FULL CLASSROOM VIDEO LESSON — dynamic for ANY topic '
                '(no hardcoded template, not a summary video):\n'
                'Student topic / chapter: ${source.chapter.title}\n'
                'Subject: ${source.subjectTitle}\n'
                'Target exam: MPSC Combined Group B and C\n\n'
                'STEP A — Mentally list EVERY subtopic / heading / bullet group in '
                'the verified notes below. That list is your teaching syllabus.\n'
                'STEP B — Produce 8–15 slides (2–5 minute lecture) that teach that list:\n'
                '  Hook → simple definition → concept explanation → each subtopic →\n'
                '  examples → important MPSC facts → PYQ connection → memory tricks →\n'
                '  revision summary → MCQs.\n'
                'STEP C — After EVERY major section, attach ONE sectionQuestion MCQ.\n'
                'STEP D — Use flowchart / timeline / comparison table / map / mindmap '
                'wherever a visual teaches better than bullets.\n'
                'STEP E — Board text minimal; narration is full teacher speech.\n\n'
                'SOURCE RULE: Use ONLY the following verified notes '
                '(and PDF if attached). Do NOT invent facts from model memory.\n\n'
                '${source.notesText}',
      },
    ];
    if (source.pdfBytes != null && source.pdfBytes!.isNotEmpty) {
      // Attach PDF first when it is primary so Gemini grounds on the document.
      if (pdfPrimary) {
        parts.insert(0, {
          'inline_data': {
            'mime_type': 'application/pdf',
            'data': encodePdfBase64(source.pdfBytes!),
          },
        });
        parts.add({
          'text':
              'The attached PDF ("${source.pdfFileName}") is the PRIMARY verified '
              'Topic study material. Preserve Marathi wording. Build slides from '
              'its headings, tables, timelines, flowcharts, diagrams, and charts. '
              'Never invent facts absent from this PDF + structured blocks.',
        });
      } else {
        parts.add({
          'inline_data': {
            'mime_type': 'application/pdf',
            'data': encodePdfBase64(source.pdfBytes!),
          },
        });
        parts.add({
          'text':
              'The attached PDF is verified chapter study material '
              '(${source.pdfFileName}). Extract ALL teachable subtopics from it '
              'and cover them in the lesson. Prefer natural Marathi faculty '
              'narration. Do not invent facts absent from the PDF + notes.',
        });
      }
    }

    try {
      final lesson = await _generate(
        userParts: parts,
        question: source.chapter.title,
        subjectFallback: source.subjectTitle,
      );
      return lesson.copyWith(
        chapterId: source.chapter.id,
        subjectId: source.chapter.subjectId,
        topicName: source.chapter.title,
        subjectName: source.subjectTitle,
        sourceKind: LessonSourceKind.verifiedNotes,
      );
    } on LessonGenerationException catch (e) {
      // Keep the student pipeline alive with a full notes-grounded classroom
      // lesson when Gemini is unauthorized / unavailable.
      debugPrint('Gemini chapter lesson failed; composing from verified notes: $e');
      return verifiedNotesLessonComposer.compose(source);
    }
  }

  @override
  Future<GeneratedLesson> regenerateChapterLessonForQuality({
    required ChapterLessonSource source,
    required String qualityRepairInstruction,
  }) async {
    final enriched = ChapterLessonSource(
      chapter: source.chapter,
      subjectTitle: source.subjectTitle,
      notesText: '${source.notesText}\n\n$qualityRepairInstruction',
      note: source.note,
      pdfBytes: source.pdfBytes,
      pdfFileName: source.pdfFileName,
      pdfStructuredBlocks: source.pdfStructuredBlocks,
      pdfIsPrimary: source.pdfIsPrimary,
    );
    try {
      return await generateChapterLesson(source: enriched);
    } on LessonGenerationException catch (_) {
      return verifiedNotesLessonComposer.compose(source);
    }
  }

  Future<GeneratedLesson> _generate({
    required List<Map<String, dynamic>> userParts,
    required String question,
    String? subjectFallback,
    MpscTeachingSubject? teachingSubject,
    bool compact = false,
  }) async {
    final style = teachingSubject ??
        tryDetectMpscTeachingSubject(question, hint: subjectFallback);
    final lessonMap = await _generateJsonMap(
      userParts: userParts,
      systemPrompt: compact
          ? compactLessonSystemPrompt(style)
          : lessonSystemPrompt(style),
      temperature: 0.35,
      maxOutputTokens: compact ? 8192 : 16384,
    );
    return _parseLessonMap(
      lessonMap,
      question: question,
      subjectFallback: subjectFallback ?? style?.displayName,
    );
  }

  Future<Map<String, dynamic>> _generateJsonMap({
    required List<Map<String, dynamic>> userParts,
    String systemPrompt =
        'You are a Marathi MPSC faculty assistant. Reply with JSON only.',
    double temperature = 0.4,
    int maxOutputTokens = 8192,
  }) async {
    if (_apiKey.isEmpty) {
      throw const LessonGenerationException('Gemini API key missing');
    }
    try {
      return await GeminiRestClient(
        apiKey: _apiKey,
        model: _model,
        client: _client,
      ).generateJsonFromParts(
        systemPrompt: systemPrompt,
        userParts: userParts,
        temperature: temperature,
        maxOutputTokens: maxOutputTokens,
      );
    } on GeminiApiException catch (e) {
      aiChapterLog('gemini_request_failed', {
        'error': e.message,
        'status': e.statusCode,
        'model': e.model,
      });
      throw LessonGenerationException(e.message);
    } catch (e) {
      final classified = classifyAiGenerationFailure(e);
      aiChapterLog('gemini_request_failed', {'error': classified});
      throw LessonGenerationException(classified);
    }
  }

  GeneratedLesson _parseLessonMap(
    Map<String, dynamic> lessonMap, {
    required String question,
    String? subjectFallback,
  }) {
    try {
      final parsed = GeneratedLesson.fromMap(lessonMap, '');
      final hasBody = parsed.slides.isNotEmpty ||
          parsed.notes.isNotEmpty ||
          parsed.summary.trim().isNotEmpty ||
          parsed.premium.introduction.trim().isNotEmpty ||
          parsed.premium.onePageSummary.trim().isNotEmpty;
      if (!hasBody) {
        aiChapterLog('parse_failure', {'reason': 'empty_chapter', 'topic': question});
        throw const LessonGenerationException('response parsing error');
      }
      aiChapterLog('parse_success', {
        'title': parsed.topicName,
        'sections': parsed.slides.length,
        'notes': parsed.notes.isNotEmpty,
        'mcqs': parsed.mcqs.length,
        'pyqs': parsed.pyqs.length,
        'revision': parsed.premium.quickRevision.trim().isNotEmpty,
        'tricks': parsed.premium.memoryTricks.isNotEmpty,
      });
      final topicName = parsed.topicName.trim().isNotEmpty
          ? parsed.topicName
          : question;
      final subjectName = parsed.subjectName.trim().isNotEmpty
          ? parsed.subjectName
          : (subjectFallback ?? 'MPSC Combine');
      return sanitizeLectureLesson(
        parsed.copyWith(
          question: question,
          topicName: topicName,
          subjectName: subjectName,
          sourceKind: LessonSourceKind.aiGenerated,
        ),
      );
    } catch (e) {
      if (e is LessonGenerationException) rethrow;
      aiChapterLog('parse_failure', {'error': '$e', 'topic': question});
      throw LessonGenerationException(
        'response parsing error: ${classifyAiGenerationFailure(e)}',
      );
    }
  }
}

class MockLessonGenerationService implements LessonGenerationService {
  @override
  Future<GeneratedLesson> generateLesson({
    required String question,
    String? subjectContext,
    MpscTeachingSubject? teachingSubject,
  }) async {
    await Future.delayed(const Duration(milliseconds: 900));
    return _mockFor(
      question,
      subjectContext,
      teachingSubject: teachingSubject,
    );
  }

  @override
  Future<GeneratedLesson> generateChapterLesson({
    required ChapterLessonSource source,
  }) async {
    await Future.delayed(const Duration(milliseconds: 1100));
    final base = _mockFor(
      source.chapter.title,
      source.subjectTitle,
      notesHint: source.notesText,
    );
    return base.copyWith(
      chapterId: source.chapter.id,
      subjectId: source.chapter.subjectId,
    );
  }

  @override
  Future<GeneratedLesson> regenerateChapterLessonForQuality({
    required ChapterLessonSource source,
    required String qualityRepairInstruction,
  }) {
    return generateChapterLesson(source: source);
  }

  @override
  Future<String> generateAnotherExample({
    required String topic,
    String? subjectContext,
    String? priorExampleHint,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return 'आणखी एक उदाहरण — "$topic" समजून घेण्यासाठी: '
        'Prelims मध्ये या संकल्पनेचा फरक थेट विचारला जातो. '
        'मुख्य शब्द लक्षात ठेवा आणि संबंधित अपवादही तपासा.';
  }

  @override
  Future<List<GeneratedMcq>> generateMoreMcqs({
    required String topic,
    String? subjectContext,
    int count = 3,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final n = count.clamp(1, 8);
    return [
      for (var i = 1; i <= n; i++)
        GeneratedMcq(
          question: 'अतिरिक्त प्रश्न $i — "$topic" बद्दल योग्य पर्याय?',
          options: const ['पर्याय अ', 'पर्याय ब (योग्य)', 'पर्याय क', 'पर्याय ड'],
          correctIndex: 1,
          explanation: 'पर्याय ब योग्य आहे (अतिरिक्त मॉक MCQ).',
          wrongExplanations: const {
            '0': 'पर्याय अ चुकीचा आहे.',
            '2': 'पर्याय क चुकीचा आहे.',
            '3': 'पर्याय ड चुकीचा आहे.',
          },
        ),
    ];
  }

  GeneratedLesson _mockFor(
    String question,
    String? subjectContext, {
    String? notesHint,
    MpscTeachingSubject? teachingSubject,
  }) {
    final trimmed = question.trim();
    final topic = trimmed.isEmpty ? 'नवीन विषय' : trimmed;
    final style = teachingSubject ??
        detectMpscTeachingSubject(topic, hint: subjectContext);
    final noteLine = (notesHint != null && notesHint.trim().isNotEmpty)
        ? 'ही मॉक लेसन Firebase नोट्स/PDF संदर्भावर आधारित आहे (AI_API_KEY सेट करा खऱ्या Gemini साठी).'
        : 'ही मॉक लेसन आहे — खऱ्या Video Lesson Engine साठी AI_API_KEY सेट करा.';

    return GeneratedLesson(
      question: trimmed,
      topicName: topic,
      subjectName: style.displayName,
      createdAt: DateTime.now(),
      script: [
        'नमस्कार! आज आपण "$topic" शिकणार आहोत — MPSC मध्ये हा विषय महत्त्वाचा आहे.',
        'चला, मूलभूत संकल्पना समजून घेऊया.',
        'आता सविस्तर स्पष्टीकरण ऐका.',
        'एक सोपे उदाहरण पाहू.',
        'ही आकृती प्रक्रिया स्पष्ट करते.',
        'आता PYQ दृष्टीने पाहा — परीक्षा कशी विचारते.',
        'आता तीन सराव प्रश्न सोडवूया.',
        'थोडक्यात पुनरावलोकन असा आहे.',
      ],
      slides: [
        GeneratedSlide(
          title: topic,
          bullets: [noteLine, '८ दृश्ये · आवाज · ग्राफिक्स', 'MPSC महत्त्व'],
          sceneType: LessonSceneType.title,
          visualType: SlideVisualType.icons,
          iconLabels: const ['अभिवादन', 'विषय', 'MPSC'],
          keywords: [topic],
          narration:
              'नमस्कार विद्यार्थी मित्रांनो! आज आपण "$topic" शिकणार आहोत. '
              'MPSC Combine मध्ये हा विषय वारंवार येतो.',
        ),
        GeneratedSlide(
          title: 'मूलभूत संकल्पना',
          bullets: const ['सोपी व्याख्या', 'मुख्य कल्पना', 'का महत्त्वाचे'],
          sceneType: LessonSceneType.introduction,
          visualType: SlideVisualType.whiteboard,
          drawSteps: const [
            DrawStep(kind: 'box', label: 'संकल्पना', x: 0.12, y: 0.15),
            DrawStep(kind: 'text', label: 'व्याख्या', x: 0.12, y: 0.4),
            DrawStep(kind: 'arrow', label: 'MPSC', x: 0.45, y: 0.55),
          ],
          handwriting: const ['बोर्डवर लिहून समजावूया'],
          pointerPath: const ['संकल्पना', 'MPSC'],
          keywords: const ['संकल्पना'],
          transition: 'zoom',
          narration: 'चला, मूलभूत संकल्पना सोप्या मराठीत समजून घेऊया.',
          sectionQuestion: GeneratedMcq(
            question: '"$topic" शिकण्याचा उद्देश काय?',
            options: const ['MPSC तयारी', 'फक्त मनोरंजन', 'खेळ', 'चित्रपट'],
            correctIndex: 0,
            explanation: 'हा धडा MPSC Combine परीक्षेसाठी आहे.',
            wrongExplanations: const {
              '1': 'हे शैक्षणिक धडे आहेत, मनोरंजन नाही.',
              '2': 'खेळाशी संबंध नाही.',
              '3': 'चित्रपट विषयाशी संबंधित नाही.',
            },
          ),
        ),
        GeneratedSlide(
          title: 'सविस्तर स्पष्टीकरण',
          bullets: const ['व्याख्या', 'रचना', 'कार्य'],
          sceneType: LessonSceneType.mainExplanation,
          visualType: SlideVisualType.mindmap,
          mindMap: MindMapData(
            center: topic,
            branches: const [
              MindMapBranch(label: 'व्याख्या', children: ['संकल्पना']),
              MindMapBranch(label: 'रचना', children: ['भाग']),
              MindMapBranch(label: 'कार्य', children: ['उपयोग']),
            ],
          ),
          narration: 'आता सविस्तर स्पष्टीकरण ऐका — मी बोर्ड वाचणार नाही, संकल्पना समजावेन. व्याख्या, रचना आणि कार्य एकत्र बांधून घ्या. परीक्षा या तीन मुद्द्यांवरच विचारते.',
          sectionQuestion: const GeneratedMcq(
            question: 'मुख्य स्पष्टीकरणात काय येते?',
            options: ['व्याख्या व रचना', 'फक्त जोक', 'गाणे', 'जाहिरात'],
            correctIndex: 0,
            explanation: 'मुख्य भागामध्ये व्याख्या, रचना आणि कार्य येते.',
          ),
        ),
        GeneratedSlide(
          title: 'मुख्य घटक',
          bullets: const ['पहिला घटक', 'दुसरा घटक', 'तिसरा घटक'],
          sceneType: LessonSceneType.mainExplanation,
          visualType: SlideVisualType.flowchart,
          flowchart: const [
            FlowNode(id: '1', label: 'घटक १', nextIds: ['2']),
            FlowNode(id: '2', label: 'घटक २', nextIds: ['3']),
            FlowNode(id: '3', label: 'घटक ३', nextIds: []),
          ],
          narration:
              'या विषयाचे मुख्य घटक क्रमाने समजून घेऊया. प्रत्येक घटकाचा अर्थ आणि तो पुढच्या घटकाशी कसा जोडला जातो ते लक्षात ठेवा. एम पी एस सी मध्ये असे घटक थेट विचारले जातात.',
        ),
        GeneratedSlide(
          title: 'का महत्त्वाचे',
          bullets: const ['शासकीय महत्त्व', 'नागरिकांचा संबंध', 'परीक्षा कोन'],
          sceneType: LessonSceneType.mainExplanation,
          visualType: SlideVisualType.table,
          tableHeaders: const ['कारण', 'लक्षात ठेवा'],
          tableRows: const [
            ['शासन', 'रचना व कार्य'],
            ['नागरिक', 'अधिकार व कर्तव्य'],
            ['परीक्षा', 'व्याख्या व फरक'],
          ],
          narration:
              'हा विषय फक्त व्याख्या नाही — तो शासन, नागरिक आणि परीक्षेला का लागतो हे समजून घ्या. फरक आणि उदाहरण एकत्र बांधाल तर उत्तर चुकणार नाही.',
        ),
        GeneratedSlide(
          title: 'उदाहरण',
          bullets: const ['व्यावहारिक उदाहरण', 'परीक्षा-केंद्रित'],
          sceneType: LessonSceneType.examples,
          narration: 'एक सोपे उदाहरण पाहू — परीक्षा कशी विचारते ते समजेल.',
          sectionQuestion: const GeneratedMcq(
            question: 'उदाहरणाचा उद्देश?',
            options: ['संकल्पना स्पष्ट करणे', 'गोंधळ वाढवणे', 'वेळ वाया', 'गाणे शिकवणे'],
            correctIndex: 0,
            explanation: 'उदाहरण संकल्पना स्पष्ट करते.',
          ),
        ),
        GeneratedSlide(
          title: 'आकृती',
          bullets: const ['पायरी १', 'पायरी २', 'पायरी ३'],
          sceneType: LessonSceneType.diagram,
          visualType: SlideVisualType.flowchart,
          highlightType: SlideHighlightType.diagram,
          flowchart: const [
            FlowNode(id: '1', label: 'सुरू', nextIds: ['2']),
            FlowNode(id: '2', label: 'मधला', nextIds: ['3']),
            FlowNode(id: '3', label: 'शेवट', nextIds: []),
          ],
          narration: 'ही आकृती प्रक्रिया स्पष्ट करते — बोर्ड स्वतः लिहीत राहील.',
          sectionQuestion: const GeneratedMcq(
            question: 'फ्लोचार्ट कशासाठी?',
            options: ['प्रक्रिया दाखवणे', 'फक्त रंग', 'गाणे', 'जाहिरात'],
            correctIndex: 0,
            explanation: 'फ्लोचार्ट प्रक्रिया स्पष्ट करतो.',
          ),
        ),
        GeneratedSlide(
          title: 'PYQ स्पष्टीकरण',
          bullets: const [
            'मागील प्रश्न कसे विचारले',
            'सामान्य चुका',
            'परीक्षा युक्ती',
          ],
          sceneType: LessonSceneType.importantPoints,
          visualType: SlideVisualType.table,
          tableHeaders: const ['दृष्टीकोन', 'लक्षात ठेवा'],
          tableRows: const [
            ['PYQ', 'व्याख्या + फरक'],
            ['चूक', 'गोंधळाचे पर्याय'],
            ['युक्ती', 'कीवर्ड बांधा'],
          ],
          keywords: const ['PYQ', 'परीक्षा'],
          narration:
              'आता PYQ दृष्टीने पाहा — मागील प्रश्नपत्रिकांमध्ये हा विषय कसा येतो '
              'आणि विद्यार्थी कुठे चुकतात.',
          sectionQuestion: const GeneratedMcq(
            question: 'PYQ दृश्याचा उद्देश?',
            options: [
              'परीक्षा कशी विचारते समजणे',
              'फक्त गाणे ऐकणे',
              'वेळ वाया घालवणे',
              'चित्र पाहणे',
            ],
            correctIndex: 0,
            explanation: 'PYQ दृश्य परीक्षा पद्धत समजावते.',
          ),
        ),
        GeneratedSlide(
          title: 'सराव MCQ',
          bullets: const ['५ AI MCQs', 'चुकीच्या उत्तरांचे स्पष्टीकरण'],
          sceneType: LessonSceneType.quiz,
          narration: 'आता पाच सराव प्रश्न सोडवूया. प्रत्येक कीवर्ड लक्षात ठेवा.',
        ),
        GeneratedSlide(
          title: 'पुनरावलोकन',
          bullets: ['$topic — थोडक्यात', noteLine, 'मुख्य मुद्दे एकदा फिरवा'],
          sceneType: LessonSceneType.summary,
          narration: 'थोडक्यात पुनरावलोकन — मुख्य कल्पना मनात ठेवा.',
        ),
      ],
      summary: '"$topic" बद्दलचा मॉक सारांश. खऱ्या Gemini धड्यासाठी AI_API_KEY सेट करा.',
      mcqs: [
        for (var i = 1; i <= 5; i++)
          GeneratedMcq(
            question: 'मॉक प्रश्न $i — "$topic" बद्दल योग्य पर्याय कोणता?',
            options: const ['पर्याय अ', 'पर्याय ब (योग्य)', 'पर्याय क', 'पर्याय ड'],
            correctIndex: 1,
            explanation: 'पर्याय ब योग्य आहे (मॉक).',
            wrongExplanations: const {
              '0': 'पर्याय अ चुकीचा आहे कारण तो धड्याशी जुळत नाही.',
              '2': 'पर्याय क चुकीचा आहे.',
              '3': 'पर्याय ड चुकीचा आहे.',
            },
          ),
      ],
      premium: const LessonPremiumExtras(
        pyqInsight: [
          'मागील वर्षी व्याख्या व फरक थेट विचारले जातात.',
          'Statement-based प्रश्नांमध्ये अपवाद लक्षात ठेवा.',
        ],
        examTips: ['कीवर्ड + संख्या एकत्र बांधा.'],
        commonMistakes: ['समान वाटणारे पर्याय घाईने निवडणे.'],
        memoryTricks: ['मुख्य शब्द एका वाक्यात.'],
        importantFacts: [
          'MPSC Combine मध्ये हा विषय वारंवार येतो.',
          'व्याख्या आणि फरक Prelims मध्ये विचारले जातात.',
          'उदाहरणासह संकल्पना लक्षात ठेवा.',
        ],
        onePageSummary: 'मॉक one-page summary.',
        quickRevision: 'व्याख्या · उदाहरण · PYQ · पाच MCQs.',
      ),
      notes: [
        '$topic — मॉक नोंद १',
        '$topic — मॉक नोंद २',
        '$topic — मॉक नोंद ३',
        '$topic — मॉक नोंद ४',
        '$topic — मॉक नोंद ५',
        '$topic — मॉक नोंद ६',
      ],
    );
  }
}

final LessonGenerationService lessonGenerationService =
    GeminiLessonGenerationService();
