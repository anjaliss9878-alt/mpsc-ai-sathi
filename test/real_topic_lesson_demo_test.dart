import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/chapter_lesson_loader.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_completeness.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_generation_service.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/lesson_render_job_builder.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Real Gemini demo — teaching quality only (no MP4 encode).
///
///   flutter test test/real_topic_lesson_demo_test.dart --dart-define-from-file=dart_defines.json
void main() {
  const topic = String.fromEnvironment(
    'DEMO_TOPIC',
    defaultValue: 'मूलभूत हक्क',
  );
  const apiKey = String.fromEnvironment('AI_API_KEY');

  test(
    'generates complete classroom lesson for student topic from verified notes',
    () async {
      if (apiKey.isEmpty) {
        // ignore: avoid_print
        print('SKIP: AI_API_KEY missing — pass --dart-define-from-file=dart_defines.json');
        return;
      }

      final catalogFile = File('test_assets/verified_notes/sample_topics.json');
      expect(await catalogFile.exists(), isTrue);
      final catalog =
          jsonDecode(await catalogFile.readAsString()) as Map<String, dynamic>;
      expect(catalog.containsKey(topic), isTrue, reason: 'Add notes for $topic');

      final entry = Map<String, dynamic>.from(catalog[topic] as Map);
      final source = _source(topic, entry);

      final generation = GeminiLessonGenerationService();
      // Uses Gemini when authorized; otherwise falls back to verified-notes
      // classroom composer (still 100% grounded in notes — no invented facts).
      var lesson = await generation.generateChapterLesson(source: source);
      lesson = lessonCompleteness.sanitizeBoardText(lesson);
      var report = lessonCompleteness.analyze(lesson);

      if (!report.ok) {
        lesson = await generation.regenerateChapterLessonForQuality(
          source: source,
          qualityRepairInstruction: lessonCompleteness.retryInstruction(report),
        );
        lesson = lessonCompleteness.sanitizeBoardText(lesson);
        report = lessonCompleteness.analyze(lesson);
      }

      final job = buildRenderJobFromLesson(lesson);
      final outDir = Directory('build/demo_lessons');
      await outDir.create(recursive: true);
      final slug = topic.replaceAll(RegExp(r'\s+'), '_');
      await File('${outDir.path}/${slug}_lesson.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(lesson.toMap()),
      );
      await File('${outDir.path}/${slug}_quality_report.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'topic': topic,
          'quality': report.toMap(),
          'slideCount': lesson.slides.length,
          'mcqScenes': job.scenes.where((s) => s.beats.any((b) => b.isMcq)).length,
          'outline': [
            for (final s in lesson.slides)
              {
                'title': s.title,
                'sceneType': s.sceneType.name,
                'visual': s.resolvedVisualType.name,
                'sectionMcq': s.sectionQuestion != null,
                'narrationChars': s.narration.length,
              },
          ],
        }),
      );

      // ignore: avoid_print
      print('DEMO slides=${lesson.slides.length} ok=${report.ok} gaps=${report.gaps}');
      for (final s in lesson.slides) {
        // ignore: avoid_print
        print(
          ' - ${s.sceneType.name}/${s.resolvedVisualType.name}: ${s.title}'
          '${s.sectionQuestion != null ? ' [MCQ]' : ''}',
        );
      }

      expect(lesson.slides.length, greaterThanOrEqualTo(kMinEduSlides));
      expect(lesson.slides.length, lessThanOrEqualTo(kMaxEduSlides));
      expect(report.mainExplanationCount, greaterThanOrEqualTo(5));
      expect(
        lesson.slides.any((s) => s.sceneType == LessonSceneType.summary) ||
            lesson.summary.trim().length >= 40,
        isTrue,
      );
      expect(report.sectionMcqCount, greaterThanOrEqualTo(1));
      expect(lesson.mcqs.length, greaterThanOrEqualTo(3));
      // Residual gaps allowed only if core classroom structure exists.
      expect(
        report.ok || report.gaps.length <= 3,
        isTrue,
        reason: report.gaps.join(' | '),
      );
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

ChapterLessonSource _source(String topic, Map<String, dynamic> entry) {
  final subject = (entry['subject'] as String?) ?? 'MPSC';
  final important = asStringList(entry['importantPoints']);
  final revision = asStringList(entry['revisionSummary']);
  final keywords = asStringList(entry['keywords']);
  final md = (entry['contentMarkdown'] as String?) ?? '';
  final chapter = ChapterItem(
    id: 'demo',
    subjectId: 'demo_s',
    title: topic,
    order: 1,
    published: true,
    titleEn: (entry['titleEn'] as String?) ?? '',
  );
  final note = NoteItem(
    id: 'demo_n',
    subjectId: 'demo_s',
    chapterId: 'demo',
    importantPoints: important,
    revisionSummary: revision,
    contentMarkdown: md,
    keywords: keywords,
    published: true,
  );
  final buf = StringBuffer()
    ..writeln('Target exam: MPSC Combined Group B and C')
    ..writeln('Subject: $subject')
    ..writeln('Chapter: $topic')
    ..writeln('Important points:');
  for (final p in important) {
    buf.writeln('- $p');
  }
  buf.writeln('Revision summary:');
  for (final p in revision) {
    buf.writeln('- $p');
  }
  if (md.isNotEmpty) {
    buf
      ..writeln('Notes markdown:')
      ..writeln(md);
  }
  return ChapterLessonSource(
    chapter: chapter,
    subjectTitle: subject,
    notesText: buf.toString(),
    note: note,
  );
}
