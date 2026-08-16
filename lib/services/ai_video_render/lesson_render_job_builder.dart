import 'package:mpsc_combine_ai/services/ai_teacher_system/faculty_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subtitle_timing.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/render_models.dart';

/// Landscape 720p educational video defaults (MPSC Combine AI MVP).
const int kEduVideoWidth = 1280;
const int kEduVideoHeight = 720;
const int kEduVideoFps = 30;

/// Minimum / maximum teaching slides for a 3–5 minute classroom lecture.
const int kMinEduSlides = 8;
const int kMaxEduSlides = 12;

/// Builds a stable [AiVideoRenderJob] from a fully prepared [GeneratedLesson].
///
/// Call only after all slides exist — never start MP4 encoding before this.
/// Output is landscape 1280×720 @ 30 FPS, clean educational beats (no avatar).
AiVideoRenderJob buildRenderJobFromLesson(GeneratedLesson lesson) {
  final slides = lesson.slides;
  if (slides.isEmpty) {
    throw StateError(
      'Cannot render video: lesson has no slides. Prepare the full slide deck first.',
    );
  }

  final scenes = <RenderScene>[];
  var sectionMcqBuffer = <GeneratedMcq>[];
  var majorSectionCount = 0;

  for (var i = 0; i < slides.length; i++) {
    final slide = slides[i];
    final narrationSource = _slideNarration(lesson, slide, i);
    final beats = _beatsForSlide(slide, narrationSource);

    scenes.add(
      RenderScene(
        id: 's${i + 1}',
        title: slide.title,
        visualType: slide.resolvedVisualType,
        beats: beats,
        bullets: slide.bullets,
        handwriting: slide.handwriting,
        flowchart: slide.flowchart,
        timeline: slide.timeline,
        tableHeaders: slide.tableHeaders,
        tableRows: slide.tableRows,
        mapRegions: slide.mapRegions,
        mcq: slide.sectionQuestion,
      ),
    );

    // After every major teaching block: emit exactly ONE section MCQ.
    final sq = slide.sectionQuestion;
    if (sq != null) {
      sectionMcqBuffer.add(sq);
    }
    final isMajorClose = slide.sceneType == LessonSceneType.importantPoints ||
        slide.sceneType == LessonSceneType.examples ||
        slide.sceneType == LessonSceneType.diagram ||
        (slide.sceneType == LessonSceneType.mainExplanation &&
            (i + 1 >= slides.length ||
                slides[i + 1].sceneType != LessonSceneType.mainExplanation));

    if (isMajorClose) {
      majorSectionCount++;
      final one = _oneSectionMcq(
        sectionMcqBuffer,
        lesson.mcqs,
        majorSectionCount,
      );
      sectionMcqBuffer = [];
      if (one != null) {
        scenes.addAll(_mcqScenes([one], sectionIndex: majorSectionCount));
      }
    }
  }

  // Ensure at least one classroom MCQ checkpoint if none were attached.
  if (lesson.mcqs.isNotEmpty &&
      !scenes.any((s) => s.mcq != null && s.beats.any((b) => b.isMcq))) {
    scenes.addAll(_mcqScenes([lesson.mcqs.first], sectionIndex: 99));
  }

  // Guarantee a revision summary scene at the end.
  final last = scenes.isEmpty ? null : scenes.last;
  final hasSummary = lesson.slides.any((s) => s.sceneType == LessonSceneType.summary) ||
      (last != null && last.title.contains('सारांश'));
  if (!hasSummary && lesson.summary.trim().isNotEmpty) {
    final text = facultyNarration(lesson.summary);
    scenes.add(
      RenderScene(
        id: 'summary',
        title: 'संपूर्ण पुनरावृत्ती',
        visualType: SlideVisualType.bullets,
        bullets: lesson.notes.isNotEmpty
            ? lesson.notes.take(8).toList()
            : lesson.premium.importantFacts.take(6).toList(),
        beats: [
          RenderNarrationBeat(
            speakText: text,
            duration: _estimateDuration(text),
            boardProgress: 1,
            keywords: const ['पुनरावृत्ती', 'सारांश'],
            subtitleCues: buildSubtitleTimingFromText(text),
          ),
        ],
      ),
    );
  }

  return AiVideoRenderJob(
    topicName: lesson.topicName.trim().isEmpty ? lesson.question : lesson.topicName,
    subjectName: lesson.subjectName,
    scenes: scenes,
    targetWidth: kEduVideoWidth,
    targetHeight: kEduVideoHeight,
    fps: kEduVideoFps,
  );
}

/// Validates that a lesson is ready for voice + video stages.
void assertLessonReadyForVideo(GeneratedLesson lesson) {
  final n = lesson.slides.length;
  if (n < 8) {
    throw StateError(
      'Slide deck incomplete ($n slides). Need a full syllabus lesson before rendering.',
    );
  }
  for (var i = 0; i < lesson.slides.length; i++) {
    final s = lesson.slides[i];
    final narr = s.narration.trim().isNotEmpty
        ? s.narration
        : (i < lesson.script.length ? lesson.script[i] : '');
    if (narr.trim().isEmpty && s.bullets.isEmpty) {
      throw StateError('Slide ${i + 1} ("${s.title}") has no teaching content.');
    }
  }
}

String _slideNarration(GeneratedLesson lesson, GeneratedSlide slide, int index) {
  if (slide.narration.trim().isNotEmpty) return slide.narration.trim();
  if (index < lesson.script.length && lesson.script[index].trim().isNotEmpty) {
    return lesson.script[index].trim();
  }
  if (slide.explanation.trim().isNotEmpty) return slide.explanation.trim();
  if (slide.bullets.isNotEmpty) return slide.bullets.join('। ');
  return slide.title;
}

List<RenderNarrationBeat> _beatsForSlide(GeneratedSlide slide, String narration) {
  final beats = <RenderNarrationBeat>[];
  final expansions = slide.bulletExpansions;
  final keywords = slide.keywords;

  // Prefer per-concept expansions (one concept per spoken beat).
  if (expansions.isNotEmpty) {
    for (var i = 0; i < expansions.length; i++) {
      final text = facultyNarration(expansions[i]);
      if (text.isEmpty) continue;
      final progress = ((i + 1) / expansions.length).clamp(0.15, 1.0);
      beats.add(
        RenderNarrationBeat(
          speakText: text,
          duration: _estimateDuration(text),
          boardProgress: progress,
          keywords: keywords,
          subtitleCues: buildSubtitleTimingFromText(text),
          pointerLabel: i < slide.bullets.length ? slide.bullets[i] : '',
        ),
      );
    }
  }

  if (beats.isEmpty) {
    final sentences = splitTeachingSentences(facultyNarration(narration));
    for (var i = 0; i < sentences.length; i++) {
      final text = sentences[i];
      beats.add(
        RenderNarrationBeat(
          speakText: text,
          duration: _estimateDuration(text),
          boardProgress: ((i + 1) / sentences.length).clamp(0.2, 1.0),
          keywords: keywords,
          subtitleCues: buildSubtitleTimingFromText(text),
          pointerLabel: slide.pointerPath.isNotEmpty
              ? slide.pointerPath[i % slide.pointerPath.length]
              : '',
        ),
      );
    }
  }

  // Weave memory / example / PYQ hints from slide explanation when present.
  final explanation = slide.explanation.trim();
  if (explanation.isNotEmpty) {
    final tip = explanation.length <= 16
        ? explanation
        : explanation.substring(0, 16);
    final already = beats.any((b) => b.speakText.contains(tip));
    final extra = facultyNarration(explanation);
    if (!already &&
        extra.isNotEmpty &&
        extra != facultyNarration(narration)) {
      beats.add(
        RenderNarrationBeat(
          speakText: extra,
          duration: _estimateDuration(extra),
          boardProgress: 1,
          keywords: keywords,
          subtitleCues: buildSubtitleTimingFromText(extra),
        ),
      );
    }
  }

  if (beats.isEmpty) {
    final fallback = facultyNarration(slide.title);
    beats.add(
      RenderNarrationBeat(
        speakText: fallback,
        duration: const Duration(seconds: 4),
        boardProgress: 1,
        keywords: keywords,
        subtitleCues: buildSubtitleTimingFromText(fallback),
      ),
    );
  }
  return beats;
}

GeneratedMcq? _oneSectionMcq(
  List<GeneratedMcq> buffer,
  List<GeneratedMcq> lessonMcqs,
  int sectionIndex,
) {
  if (buffer.isNotEmpty) return buffer.last;
  final idx = sectionIndex - 1;
  if (idx >= 0 && idx < lessonMcqs.length) return lessonMcqs[idx];
  return null;
}

List<RenderScene> _mcqScenes(List<GeneratedMcq> mcqs, {required int sectionIndex}) {
  final out = <RenderScene>[];
  for (var i = 0; i < mcqs.length; i++) {
    final m = mcqs[i];
    final qText = facultyNarration(
      'प्रश्न ${i + 1}. ${m.question} पर्याय ऐका. ${m.options.asMap().entries.map((e) => '${e.key + 1}) ${e.value}').join(' ')}',
    );
    final explain = facultyNarration(
      m.explanation.trim().isNotEmpty
          ? 'योग्य उत्तर: ${m.options[m.correctIndex.clamp(0, m.options.length - 1)]}. ${m.explanation}'
          : 'योग्य उत्तर: ${m.options[m.correctIndex.clamp(0, m.options.length - 1)]}.',
    );
    out.add(
      RenderScene(
        id: 'mcq_${sectionIndex}_$i',
        title: 'सराव MCQ ${i + 1}',
        visualType: SlideVisualType.bullets,
        bullets: m.options,
        mcq: m,
        beats: [
          RenderNarrationBeat(
            speakText: qText,
            duration: _estimateDuration(qText),
            boardProgress: 0.7,
            keywords: const ['MCQ'],
            subtitleCues: buildSubtitleTimingFromText(qText),
            isMcq: true,
          ),
          RenderNarrationBeat(
            speakText: explain,
            duration: _estimateDuration(explain),
            boardProgress: 1,
            keywords: const ['उत्तर'],
            subtitleCues: buildSubtitleTimingFromText(explain),
            isMcqExplain: true,
          ),
        ],
      ),
    );
  }
  return out;
}

Duration _estimateDuration(String text) {
  // Natural Marathi female faculty pace ≈ 11 chars/sec + small breath.
  final chars = text.trim().length;
  final seconds = (chars / 11.0).clamp(2.8, 22.0);
  return Duration(milliseconds: (seconds * 1000).round());
}
