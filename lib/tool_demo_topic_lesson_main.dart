import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/chapter_lesson_loader.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_completeness.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_generation_service.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/lesson_render_job_builder.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Teaching-quality demo for ANY topic (no MP4 render optimization).
///
///   flutter run -d windows -t lib/tool_demo_topic_lesson_main.dart \
///     --dart-define-from-file=dart_defines.json \
///     --dart-define=DEMO_TOPIC=मूलभूत हक्क
///
/// Uses verified notes from `test_assets/verified_notes/sample_topics.json`
/// (stand-in for Firestore published notes). Works for every key in that file
/// without code changes — add more topics to the JSON to expand coverage.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const topic = String.fromEnvironment(
    'DEMO_TOPIC',
    defaultValue: 'मूलभूत हक्क',
  );
  debugPrint('[Demo] topic="$topic"');

  final notesPath = File('test_assets/verified_notes/sample_topics.json');
  if (!await notesPath.exists()) {
    stderr.writeln('Missing ${notesPath.path}');
    exit(2);
  }
  final catalog =
      jsonDecode(await notesPath.readAsString()) as Map<String, dynamic>;
  final entry = _resolveTopicEntry(catalog, topic);
  if (entry == null) {
    stderr.writeln(
      'No verified notes for "$topic". Available: ${catalog.keys.join(', ')}',
    );
    exit(3);
  }

  final source = _sourceFromEntry(topic: topic, entry: entry);
  debugPrint(
    '[Demo] verified notes chars=${source.notesText.length} '
    'subject=${source.subjectTitle}',
  );

  final generation = GeminiLessonGenerationService();
  var lesson = await generation.generateChapterLesson(source: source);
  lesson = lessonCompleteness.sanitizeBoardText(lesson);
  var report = lessonCompleteness.analyze(lesson);
  debugPrint('[Demo] first-pass quality=${report.toMap()}');

  if (!report.ok) {
    debugPrint('[Demo] quality repair retry…');
    lesson = await generation.regenerateChapterLessonForQuality(
      source: source,
      qualityRepairInstruction: lessonCompleteness.retryInstruction(report),
    );
    lesson = lessonCompleteness.sanitizeBoardText(lesson);
    report = lessonCompleteness.analyze(lesson);
    debugPrint('[Demo] retry quality=${report.toMap()}');
  }

  // Build render job for structure verification only (no encode).
  final job = buildRenderJobFromLesson(lesson);
  final sectionMcqScenes =
      job.scenes.where((s) => s.beats.any((b) => b.isMcq)).length;

  final outDir = Directory('build/demo_lessons');
  await outDir.create(recursive: true);
  final slug = topic.trim().replaceAll(RegExp(r'\s+'), '_');
  final lessonFile = File('${outDir.path}/${slug}_lesson.json');
  final reportFile = File('${outDir.path}/${slug}_quality_report.json');

  await lessonFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(lesson.toMap()),
  );
  final verification = <String, dynamic>{
    'topic': topic,
    'subject': lesson.subjectName,
    'slideCount': lesson.slides.length,
    'mainExplanationCount': report.mainExplanationCount,
    'sectionMcqOnSlides': report.sectionMcqCount,
    'mcqScenesInJob': sectionMcqScenes,
    'visualVarietyCount': report.visualVarietyCount,
    'topLevelMcqs': lesson.mcqs.length,
    'importantFacts': lesson.premium.importantFacts.length,
    'hasSummary': lesson.slides.any((s) => s.sceneType == LessonSceneType.summary) ||
        lesson.summary.trim().isNotEmpty,
    'quality': report.toMap(),
    'slideOutline': [
      for (final s in lesson.slides)
        {
          'title': s.title,
          'sceneType': s.sceneType.name,
          'visualType': s.resolvedVisualType.name,
          'bullets': s.bullets.length,
          'narrationChars': s.narration.trim().length,
          'hasSectionMcq': s.sectionQuestion != null,
        },
    ],
    'lessonPath': lessonFile.path,
    'verdict': report.ok
        ? 'COMPLETE_CLASSROOM_LESSON'
        : 'NEEDS_REVIEW_RESIDUAL_GAPS',
  };
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(verification),
  );

  debugPrint('[Demo] wrote ${lessonFile.path}');
  debugPrint('[Demo] wrote ${reportFile.path}');
  debugPrint('[Demo] verdict=${verification['verdict']}');
  for (final g in report.gaps) {
    debugPrint('[Demo] gap: $g');
  }
  for (final s in report.strengths) {
    debugPrint('[Demo] strength: $s');
  }

  // Print a short human checklist for teaching quality.
  _printTeachingChecklist(lesson, report, sectionMcqScenes);

  exit(report.ok || lesson.slides.length >= kMinEduSlides ? 0 : 1);
}

Map<String, dynamic>? _resolveTopicEntry(
  Map<String, dynamic> catalog,
  String topic,
) {
  final trimmed = topic.trim();
  if (catalog.containsKey(trimmed)) {
    return Map<String, dynamic>.from(catalog[trimmed] as Map);
  }
  final lower = trimmed.toLowerCase();
  for (final e in catalog.entries) {
    final map = Map<String, dynamic>.from(e.value as Map);
    final en = (map['titleEn'] as String?)?.toLowerCase() ?? '';
    if (e.key.toLowerCase() == lower || en == lower || en.contains(lower)) {
      return map;
    }
  }
  // Fuzzy contains either way.
  for (final e in catalog.entries) {
    if (e.key.contains(trimmed) || trimmed.contains(e.key)) {
      return Map<String, dynamic>.from(e.value as Map);
    }
  }
  return null;
}

ChapterLessonSource _sourceFromEntry({
  required String topic,
  required Map<String, dynamic> entry,
}) {
  final subject = (entry['subject'] as String?) ?? 'MPSC Combine';
  final important = asStringList(entry['importantPoints']);
  final revision = asStringList(entry['revisionSummary']);
  final keywords = asStringList(entry['keywords']);
  final md = (entry['contentMarkdown'] as String?) ?? '';

  final chapter = ChapterItem(
    id: 'demo_${topic.hashCode}',
    subjectId: 'demo_subject',
    title: topic,
    order: 1,
    titleEn: (entry['titleEn'] as String?) ?? '',
    published: true,
    description: 'Verified demo notes for dynamic topic engine',
    tags: keywords,
  );
  final note = NoteItem(
    id: 'demo_note_${topic.hashCode}',
    subjectId: chapter.subjectId,
    chapterId: chapter.id,
    title: topic,
    importantPoints: important,
    revisionSummary: revision,
    contentMarkdown: md,
    keywords: keywords,
    published: true,
  );

  final buffer = StringBuffer()
    ..writeln('Target exam: MPSC Combined Group B and C')
    ..writeln('Student topic input: $topic')
    ..writeln('Matched chapter: ${chapter.title}')
    ..writeln('Matched subject: $subject')
    ..writeln()
    ..writeln('Subject: $subject')
    ..writeln('Chapter: ${chapter.title}')
    ..writeln('Important points:');
  for (final p in important) {
    buffer.writeln('- $p');
  }
  buffer.writeln('Revision summary:');
  for (final p in revision) {
    buffer.writeln('- $p');
  }
  if (md.trim().isNotEmpty) {
    buffer
      ..writeln('Notes markdown:')
      ..writeln(md);
  }
  if (keywords.isNotEmpty) {
    buffer.writeln('Keywords: ${keywords.join(', ')}');
  }

  return ChapterLessonSource(
    chapter: chapter,
    subjectTitle: subject,
    notesText: buffer.toString(),
    note: note,
  );
}

void _printTeachingChecklist(
  GeneratedLesson lesson,
  LessonCompletenessReport report,
  int mcqScenes,
) {
  debugPrint('──────── Teaching quality checklist ────────');
  debugPrint('Slides 8–15: ${lesson.slides.length}');
  debugPrint('Subtopic slides: ${report.mainExplanationCount}');
  debugPrint('Section MCQs: ${report.sectionMcqCount} (job scenes: $mcqScenes)');
  debugPrint('Visual types: ${report.visualVarietyCount}');
  debugPrint('MPSC facts: ${lesson.premium.importantFacts.length}');
  debugPrint(
    'Revision summary: ${lesson.summary.trim().isNotEmpty || lesson.slides.any((s) => s.sceneType == LessonSceneType.summary)}',
  );
  debugPrint('Complete: ${report.ok}');
  debugPrint('────────────────────────────────────────────');
}
