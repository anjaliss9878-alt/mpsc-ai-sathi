import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/chapter_lesson_loader.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_completeness.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/verified_notes_lesson_composer.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/lesson_render_job_builder.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

void main() {
  test('composer builds full classroom lesson from verified notes for any catalog topic',
      () async {
    final catalog = jsonDecode(
      await File('test_assets/verified_notes/sample_topics.json').readAsString(),
    ) as Map<String, dynamic>;

    for (final topic in catalog.keys) {
      final entry = Map<String, dynamic>.from(catalog[topic] as Map);
      final source = _source(topic, entry);
      final lesson = verifiedNotesLessonComposer.compose(source);
      final report = lessonCompleteness.analyze(
        lessonCompleteness.sanitizeBoardText(lesson),
      );
      final job = buildRenderJobFromLesson(lesson);

      expect(lesson.slides.length, inInclusiveRange(kMinEduSlides, kMaxEduSlides));
      expect(report.mainExplanationCount, greaterThanOrEqualTo(3));
      expect(
        lesson.slides.any((s) => s.sceneType == LessonSceneType.summary),
        isTrue,
      );
      expect(report.sectionMcqCount, greaterThanOrEqualTo(1));
      expect(job.scenes.any((s) => s.beats.any((b) => b.isMcq)), isTrue);
      // Accuracy: composed notes list stays grounded in verified points.
      final firstPoint = asStringList(entry['importantPoints']).first;
      expect(
        lesson.notes.any((n) => firstPoint.contains(n.replaceAll('…', '')) ||
            n.contains(firstPoint.substring(0, firstPoint.length < 10 ? firstPoint.length : 10))),
        isTrue,
      );
      expect(report.ok || report.gaps.length <= 2, isTrue, reason: report.gaps.join(' | '));
    }
  });
}

ChapterLessonSource _source(String topic, Map<String, dynamic> entry) {
  final important = asStringList(entry['importantPoints']);
  final revision = asStringList(entry['revisionSummary']);
  final keywords = asStringList(entry['keywords']);
  final md = (entry['contentMarkdown'] as String?) ?? '';
  final chapter = ChapterItem(
    id: 'c',
    subjectId: 's',
    title: topic,
    order: 1,
    published: true,
  );
  final note = NoteItem(
    id: 'n',
    subjectId: 's',
    chapterId: 'c',
    importantPoints: important,
    revisionSummary: revision,
    contentMarkdown: md,
    keywords: keywords,
    published: true,
  );
  final buf = StringBuffer()
    ..writeln('Subject: ${entry['subject']}')
    ..writeln('Chapter: $topic')
    ..writeln('Important points:');
  for (final p in important) {
    buf.writeln('- $p');
  }
  return ChapterLessonSource(
    chapter: chapter,
    subjectTitle: (entry['subject'] as String?) ?? 'MPSC',
    notesText: buf.toString(),
    note: note,
  );
}
