import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/lesson_render_job_builder.dart';

/// Teaching-quality report for a generated classroom lesson (any topic).
class LessonCompletenessReport {
  const LessonCompletenessReport({
    required this.ok,
    required this.slideCount,
    required this.gaps,
    required this.strengths,
    required this.sectionMcqCount,
    required this.visualVarietyCount,
    required this.mainExplanationCount,
  });

  final bool ok;
  final int slideCount;
  final List<String> gaps;
  final List<String> strengths;
  final int sectionMcqCount;
  final int visualVarietyCount;
  final int mainExplanationCount;

  Map<String, dynamic> toMap() => {
        'ok': ok,
        'slideCount': slideCount,
        'sectionMcqCount': sectionMcqCount,
        'visualVarietyCount': visualVarietyCount,
        'mainExplanationCount': mainExplanationCount,
        'gaps': gaps,
        'strengths': strengths,
      };
}

/// Validates full classroom teaching quality — not a short summary video.
class LessonCompleteness {
  const LessonCompleteness();

  static const int minMainExplanationSlides = 3;
  static const int minSectionMcqs = 1;
  static const int maxBulletChars = 56;
  static const int minNarrationChars = 60;

  LessonCompletenessReport analyze(GeneratedLesson lesson) {
    final gaps = <String>[];
    final strengths = <String>[];
    final slides = lesson.slides;
    final n = slides.length;

    if (n < kMinEduSlides) {
      gaps.add('Need $kMinEduSlides–$kMaxEduSlides slides (got $n).');
    } else if (n > kMaxEduSlides) {
      gaps.add('Too many slides ($n); keep ≤ $kMaxEduSlides.');
    } else {
      strengths.add('$n teaching slides in target range.');
    }

    final hasTitle = slides.any((s) => s.sceneType == LessonSceneType.title);
    final hasIntro =
        slides.any((s) => s.sceneType == LessonSceneType.introduction);
    final hasSummary =
        slides.any((s) => s.sceneType == LessonSceneType.summary) ||
            lesson.summary.trim().length >= 40;
    final hasExamples =
        slides.any((s) => s.sceneType == LessonSceneType.examples);
    final hasImportant = slides.any(
      (s) => s.sceneType == LessonSceneType.importantPoints,
    );

    if (!hasTitle) gaps.add('Missing title/hook slide.');
    if (!hasIntro) gaps.add('Missing introduction / syllabus-map slide.');
    if (!hasSummary) gaps.add('Missing revision summary close.');
    if (!hasExamples) gaps.add('Missing examples slide.');
    if (!hasImportant) {
      gaps.add('Missing important facts / PYQ slide.');
    }

    final mainCount = slides
        .where((s) => s.sceneType == LessonSceneType.mainExplanation)
        .length;
    if (mainCount < minMainExplanationSlides) {
      gaps.add(
        'Need ≥$minMainExplanationSlides mainExplanation subtopic slides '
        '(got $mainCount) — lesson looks like a summary, not full teaching.',
      );
    } else {
      strengths.add('$mainCount detailed subtopic slides.');
    }

    final sectionMcqs =
        slides.where((s) => s.sectionQuestion != null).length;
    if (sectionMcqs < minSectionMcqs) {
      gaps.add(
        'Need sectionQuestion MCQ after major sections '
        '(found $sectionMcqs; want ≥$minSectionMcqs).',
      );
    } else {
      strengths.add('$sectionMcqs in-lesson section MCQs.');
    }

    if (lesson.mcqs.length != 5) {
      gaps.add('Top-level mcqs array needs exactly 5 practice questions.');
    }

    final visuals = <SlideVisualType>{};
    for (final s in slides) {
      final v = s.resolvedVisualType;
      if (v == SlideVisualType.flowchart ||
          v == SlideVisualType.timeline ||
          v == SlideVisualType.table ||
          v == SlideVisualType.map ||
          v == SlideVisualType.mindmap ||
          v == SlideVisualType.whiteboard) {
        visuals.add(v);
      }
      if (s.sceneType == LessonSceneType.diagram) {
        visuals.add(SlideVisualType.flowchart);
      }
    }
    if (visuals.length < 2) {
      gaps.add(
        'Need richer visuals (flowchart/timeline/table/map/mindmap) — '
        'found ${visuals.length} types.',
      );
    } else {
      strengths.add('Visual variety: ${visuals.map((e) => e.name).join(', ')}.');
    }

    var thinNarration = 0;
    var longBullets = 0;
    for (final s in slides) {
      if (s.sceneType == LessonSceneType.title ||
          s.sceneType == LessonSceneType.summary) {
        continue;
      }
      if (s.narration.trim().length < minNarrationChars) thinNarration++;
      for (final b in s.bullets) {
        if (b.trim().length > maxBulletChars) longBullets++;
      }
    }
    if (thinNarration > 2) {
      gaps.add(
        '$thinNarration slides have thin narration (<$minNarrationChars chars). '
        'Faculty must teach fully, not summarize.',
      );
    }
    if (longBullets > 4) {
      gaps.add(
        '$longBullets board bullets are too long (>$maxBulletChars chars). '
        'Keep board text minimal; put detail in narration.',
      );
    } else {
      strengths.add('Board text mostly concise.');
    }

    if (lesson.premium.importantFacts.length < 3) {
      gaps.add('premium.importantFacts should highlight ≥3 MPSC facts.');
    } else {
      strengths.add(
        '${lesson.premium.importantFacts.length} highlighted MPSC facts.',
      );
    }

    if (lesson.notes.length < 6) {
      gaps.add('notes revision list should cover the full topic (≥6 bullets).');
    }

    final ok = gaps.isEmpty;
    if (ok) strengths.add('Classroom-quality completeness checks passed.');

    return LessonCompletenessReport(
      ok: ok,
      slideCount: n,
      gaps: gaps,
      strengths: strengths,
      sectionMcqCount: sectionMcqs,
      visualVarietyCount: visuals.length,
      mainExplanationCount: mainCount,
    );
  }

  /// Soft cleanup: shorten oversized board bullets without changing meaning.
  GeneratedLesson sanitizeBoardText(GeneratedLesson lesson) {
    final cleaned = lesson.slides.map((s) {
      final bullets = s.bullets.map(_shortenBullet).toList(growable: false);
      return GeneratedSlide(
        title: s.title,
        bullets: bullets,
        narration: s.narration,
        explanation: s.explanation,
        keywords: s.keywords,
        sceneType: s.sceneType,
        visualType: s.visualType,
        highlightType: s.highlightType,
        highlightLabel: s.highlightLabel,
        transition: s.transition,
        pointerPath: s.pointerPath,
        handwriting: s.handwriting,
        flowchart: s.flowchart,
        timeline: s.timeline,
        tableHeaders: s.tableHeaders,
        tableRows: s.tableRows,
        mapRegions: s.mapRegions,
        drawSteps: s.drawSteps,
        mindMap: s.mindMap,
        graph: s.graph,
        iconLabels: s.iconLabels,
        imageUrl: s.imageUrl,
        bulletExpansions: s.bulletExpansions,
        sectionQuestion: s.sectionQuestion,
        subtitleTiming: s.subtitleTiming,
      );
    }).toList(growable: false);

    return GeneratedLesson(
      id: lesson.id,
      question: lesson.question,
      topicName: lesson.topicName,
      subjectName: lesson.subjectName,
      script: lesson.script,
      slides: cleaned,
      summary: lesson.summary,
      mcqs: lesson.mcqs,
      notes: lesson.notes,
      createdAt: lesson.createdAt,
      chapterId: lesson.chapterId,
      subjectId: lesson.subjectId,
      premium: lesson.premium,
      sourceKind: lesson.sourceKind,
    );
  }

  String _shortenBullet(String raw) {
    final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length <= maxBulletChars) return t;
    // Prefer cut at Marathi danda / comma / space.
    final cut = t.substring(0, maxBulletChars);
    final breakAt = [
      cut.lastIndexOf('।'),
      cut.lastIndexOf(','),
      cut.lastIndexOf(' '),
    ].where((i) => i > 20).fold<int>(-1, (a, b) => a > b ? a : b);
    if (breakAt > 20) return '${cut.substring(0, breakAt).trim()}…';
    return '${cut.trim()}…';
  }

  /// Retry instruction listing concrete gaps for Gemini.
  String retryInstruction(LessonCompletenessReport report) {
    final buf = StringBuffer()
      ..writeln('QUALITY REPAIR REQUIRED — previous draft failed classroom checks:')
      ..writeln(report.gaps.map((g) => '- $g').join('\n'))
      ..writeln()
      ..writeln('Rewrite the FULL lesson JSON (not a summary). Requirements:')
      ..writeln('- 8–12 slides covering the topic as a 3–5 minute classroom lecture')
      ..writeln('- EXACTLY 5 MCQs in the top-level mcqs array')
      ..writeln('- Teach in the detected subject teacher style (not a generic tutor)')
      ..writeln('- Use flowchart / timeline / table / map where relevant')
      ..writeln('- Short board bullets (≤≈12 Marathi words); detail in narration')
      ..writeln('- Natural teacher-style Marathi narration on every teaching slide')
      ..writeln('- End with complete revision summary of ALL key points')
      ..writeln('- Highlight MPSC facts in premium.importantFacts');
    return buf.toString();
  }
}

const LessonCompleteness lessonCompleteness = LessonCompleteness();
