import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/speakable_marathi.dart';

/// Makes a generated lesson safe for continuous Marathi faculty TTS.
///
/// Board labels stay short. Spoken fields never contain +, -, /, %, page
/// numbers, or other symbols the voice would read in English.
GeneratedLesson sanitizeLectureLesson(GeneratedLesson lesson) {
  final slides = [
    for (final slide in lesson.slides) _sanitizeSlide(slide),
  ];
  final script = [
    for (final slide in slides)
      slide.narration.trim().isNotEmpty
          ? slide.narration
          : speakableMarathi(slide.title),
  ];
  return GeneratedLesson(
    id: lesson.id,
    question: lesson.question,
    topicName: lesson.topicName,
    subjectName: lesson.subjectName,
    script: script,
    slides: slides,
    summary: speakableMarathi(lesson.summary),
    mcqs: [
      for (final q in lesson.mcqs)
        GeneratedMcq(
          question: speakableMarathi(q.question),
          options: [for (final o in q.options) cleanBoardText(o)],
          correctIndex: q.correctIndex,
          explanation: speakableMarathi(q.explanation),
          wrongExplanations: {
            for (final e in q.wrongExplanations.entries)
              e.key: speakableMarathi(e.value),
          },
          difficulty: q.difficulty,
          kind: q.kind,
        ),
    ],
    notes: [for (final n in lesson.notes) cleanBoardText(n)],
    createdAt: lesson.createdAt,
    chapterId: lesson.chapterId,
    subjectId: lesson.subjectId,
    premium: LessonPremiumExtras(
      pyqInsight: [for (final s in lesson.premium.pyqInsight) speakableMarathi(s)],
      examTips: [for (final s in lesson.premium.examTips) speakableMarathi(s)],
      commonMistakes: [
        for (final s in lesson.premium.commonMistakes) speakableMarathi(s)
      ],
      memoryTricks: [
        for (final s in lesson.premium.memoryTricks) speakableMarathi(s)
      ],
      importantFacts: [
        for (final s in lesson.premium.importantFacts) cleanBoardText(s)
      ],
      examTraps: [
        for (final s in lesson.premium.examTraps) speakableMarathi(s)
      ],
      onePageSummary: speakableMarathi(lesson.premium.onePageSummary),
      quickRevision: speakableMarathi(lesson.premium.quickRevision),
      introduction: speakableMarathi(lesson.premium.introduction),
      mainConcepts: [
        for (final s in lesson.premium.mainConcepts) cleanBoardText(s)
      ],
      factBox: speakableMarathi(lesson.premium.factBox),
      pyqConnection: speakableMarathi(lesson.premium.pyqConnection),
      examples: [for (final s in lesson.premium.examples) speakableMarathi(s)],
    ),
    sourceKind: lesson.sourceKind,
    pyqs: [
      for (final p in lesson.pyqs)
        GeneratedPyq(
          question: speakableMarathi(p.question),
          year: cleanBoardText(p.year),
          answer: speakableMarathi(p.answer),
          analysis: speakableMarathi(p.analysis),
          trend: speakableMarathi(p.trend),
          exam: cleanBoardText(p.exam),
          whyAsked: speakableMarathi(p.whyAsked),
        ),
    ],
  );
}

GeneratedSlide _sanitizeSlide(GeneratedSlide slide) {
  final map = Map<String, dynamic>.from(slide.toMap());
  map['title'] = cleanBoardText(slide.title);
  map['bullets'] = [for (final b in slide.bullets) cleanBoardText(b)];
  map['keywords'] = [for (final k in slide.keywords) cleanBoardText(k)];
  map['narration'] = speakableMarathi(slide.narration);
  map['explanation'] = speakableMarathi(slide.explanation);
  map['bulletExpansions'] = [
    for (final e in slide.bulletExpansions) speakableMarathi(e),
  ];
  map['handwriting'] = [for (final h in slide.handwriting) cleanBoardText(h)];
  map['transition'] = 'fade';
  return GeneratedSlide.fromMap(map);
}
