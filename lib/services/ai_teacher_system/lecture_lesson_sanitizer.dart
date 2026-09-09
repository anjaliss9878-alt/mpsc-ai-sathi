import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/speakable_marathi.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';

/// Makes a generated lesson safe for continuous Marathi faculty TTS.
///
/// Board labels stay short. Spoken fields never contain +, -, /, %, page
/// numbers, or other symbols the voice would read in English.
GeneratedLesson sanitizeLectureLesson(GeneratedLesson lesson) {
  final slides = [
    for (final slide in lesson.slides) _sanitizeSlide(slide),
  ];
  final cleaned = GeneratedLesson(
    id: lesson.id,
    question: lesson.question,
    topicName: lesson.topicName,
    subjectName: lesson.subjectName,
    script: [
      for (final slide in slides)
        slide.narration.trim().isNotEmpty
            ? slide.narration
            : speakableMarathi(slide.title),
    ],
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
  return ensureClassroomVideoScenes(cleaned);
}

/// Turns the generated lesson into ordered video scenes (intro → concepts →
/// example → exam → revision) without calling Gemini again.
GeneratedLesson ensureClassroomVideoScenes(GeneratedLesson lesson) {
  final subject = detectMpscTeachingSubject(
    lesson.topicName,
    hint: lesson.subjectName,
  );
  final slides = classroomVideoScenesFor(lesson, subject: subject);
  return lesson.copyWith(
    slides: slides,
    script: [
      for (final slide in slides)
        slide.narration.trim().isNotEmpty ? slide.narration.trim() : slide.title,
    ],
  );
}

bool hasUsableClassroomVideoScenes(List<GeneratedSlide> slides) {
  if (slides.length < 4) return false;
  return slides.map((s) => s.sceneType).toSet().length >= 2;
}

List<GeneratedSlide> classroomVideoScenesFor(
  GeneratedLesson lesson, {
  MpscTeachingSubject? subject,
}) {
  final style = subject ??
      detectMpscTeachingSubject(lesson.topicName, hint: lesson.subjectName);
  if (hasUsableClassroomVideoScenes(lesson.slides)) {
    return [
      for (final slide in lesson.slides) _decorateVideoSlide(slide, style),
    ];
  }
  return [
    for (final slide in _scenesFromLessonMaterial(lesson, style))
      _decorateVideoSlide(slide, style),
  ];
}

GeneratedSlide _decorateVideoSlide(
  GeneratedSlide slide,
  MpscTeachingSubject subject,
) {
  final narration = slide.narration.trim().isNotEmpty
      ? slide.narration.trim()
      : (slide.bullets.where((b) => b.trim().isNotEmpty).isNotEmpty
          ? slide.bullets.where((b) => b.trim().isNotEmpty).join('. ')
          : slide.title);
  final visual = subjectSlideVisualType(subject: subject, slide: slide);
  if (narration == slide.narration.trim() && visual == slide.visualType) {
    return slide;
  }
  final map = Map<String, dynamic>.from(slide.toMap());
  map['narration'] = narration;
  map['visualType'] = visual.name;
  map['transition'] = 'fade';
  return GeneratedSlide.fromMap(map);
}

GeneratedSlide _scene({
  required String title,
  required List<String> bullets,
  required String narration,
  required LessonSceneType sceneType,
  List<String> keywords = const [],
}) {
  final points = [
    for (final b in bullets)
      if (b.trim().isNotEmpty) b.trim(),
  ].take(4).toList();
  return GeneratedSlide(
    title: title.trim().isEmpty ? 'धडा' : title.trim(),
    bullets: points.isEmpty ? [title] : points,
    sceneType: sceneType,
    keywords: keywords,
    narration: narration.trim(),
    transition: 'fade',
  );
}

  List<GeneratedSlide> _scenesFromLessonMaterial(
  GeneratedLesson lesson,
  MpscTeachingSubject _,
) {
  final topic = lesson.topicName.trim().isEmpty
      ? lesson.question.trim()
      : lesson.topicName.trim();
  final p = lesson.premium;
  final existing = lesson.slides;
  final first = existing.isEmpty ? null : existing.first;
  final scenes = <GeneratedSlide>[];

  void add(GeneratedSlide slide) {
    if (slide.title.trim().isEmpty && slide.narration.trim().isEmpty) return;
    scenes.add(slide);
  }

  add(
    _scene(
      title: topic,
      bullets: first?.bullets ??
          (p.introduction.trim().isEmpty
              ? [topic]
              : [p.introduction.trim()]),
      narration: p.introduction.trim().isNotEmpty
          ? p.introduction.trim()
          : (first?.narration.trim().isNotEmpty == true
              ? first!.narration.trim()
              : 'आज आपण $topic हा विषय समजून घेणार आहोत.'),
      sceneType: LessonSceneType.introduction,
      keywords: first?.keywords ?? [topic],
    ),
  );

  final conceptSlides = existing
      .where(
        (s) =>
            s.sceneType == LessonSceneType.mainExplanation ||
            s.sceneType == LessonSceneType.importantPoints ||
            s.sceneType == LessonSceneType.diagram,
      )
      .toList();
  if (conceptSlides.length >= 2) {
    add(conceptSlides[0]);
    add(conceptSlides[1]);
  } else if (existing.length >= 2) {
    add(existing[1]);
    if (existing.length >= 3) add(existing[2]);
  } else {
    final concepts = p.mainConcepts.where((s) => s.trim().isNotEmpty).toList();
    final bullets = first?.bullets ?? const <String>[];
    if (concepts.length >= 2) {
      add(
        _scene(
          title: concepts.first,
          bullets: concepts.take(3).toList(),
          narration: concepts.take(2).join('. '),
          sceneType: LessonSceneType.mainExplanation,
        ),
      );
      add(
        _scene(
          title: concepts[1],
          bullets: concepts.skip(1).take(3).toList(),
          narration: concepts.skip(1).take(2).join('. '),
          sceneType: LessonSceneType.mainExplanation,
        ),
      );
    } else if (bullets.length >= 4) {
      add(
        _scene(
          title: bullets.first,
          bullets: bullets.take(2).toList(),
          narration: bullets.take(2).join('. '),
          sceneType: LessonSceneType.mainExplanation,
        ),
      );
      add(
        _scene(
          title: bullets[2],
          bullets: bullets.skip(2).take(2).toList(),
          narration: bullets.skip(2).take(2).join('. '),
          sceneType: LessonSceneType.mainExplanation,
        ),
      );
    } else {
      final sentences = _sentences(
        first?.narration.trim().isNotEmpty == true
            ? first!.narration
            : lesson.summary,
      );
      if (sentences.length >= 2) {
        add(
          _scene(
            title: 'संकल्पना १',
            bullets: sentences.take(2).toList(),
            narration: sentences.take(2).join(' '),
            sceneType: LessonSceneType.mainExplanation,
          ),
        );
        add(
          _scene(
            title: 'संकल्पना २',
            bullets: sentences.skip(2).take(2).isEmpty
                ? sentences.take(2).toList()
                : sentences.skip(2).take(2).toList(),
            narration: (sentences.skip(2).take(2).isEmpty
                    ? sentences.take(2)
                    : sentences.skip(2).take(2))
                .join(' '),
            sceneType: LessonSceneType.mainExplanation,
          ),
        );
      }
    }
  }

  final exampleSlide = existing.cast<GeneratedSlide?>().firstWhere(
        (s) => s?.sceneType == LessonSceneType.examples,
        orElse: () => null,
      );
  final exampleText = p.examples.where((s) => s.trim().isNotEmpty).toList();
  add(
    exampleSlide ??
        _scene(
          title: 'उदाहरण',
          bullets: exampleText.isNotEmpty
              ? exampleText.take(3).toList()
              : (first?.bullets.take(2).toList() ?? [topic]),
          narration: exampleText.isNotEmpty
              ? exampleText.first
              : (exampleSlide?.narration ??
                  'या संकल्पनेचे एक सोपे उदाहरण पाहूया.'),
          sceneType: LessonSceneType.examples,
        ),
  );

  final examBits = [
    ...p.pyqInsight,
    ...p.examTips,
    if (p.pyqConnection.trim().isNotEmpty) p.pyqConnection.trim(),
    for (final q in lesson.pyqs.take(2)) q.question,
  ].where((s) => s.trim().isNotEmpty).toList();
  add(
    _scene(
      title: 'परीक्षा / PYQ',
      bullets: examBits.isNotEmpty ? examBits.take(3).toList() : [topic],
      narration: examBits.isNotEmpty
          ? examBits.first
          : 'परीक्षा या मुद्द्यावर संकल्पना आणि फरक विचारते.',
      sceneType: LessonSceneType.importantPoints,
    ),
  );

  final revision = p.quickRevision.trim().isNotEmpty
      ? p.quickRevision.trim()
      : (p.onePageSummary.trim().isNotEmpty
          ? p.onePageSummary.trim()
          : lesson.summary.trim());
  final summarySlide = existing.cast<GeneratedSlide?>().firstWhere(
        (s) => s?.sceneType == LessonSceneType.summary,
        orElse: () => null,
      );
  add(
    summarySlide ??
        _scene(
          title: 'जलद पुनरावृत्ती',
          bullets: revision.isEmpty
              ? [topic]
              : _sentences(revision).take(3).toList(),
          narration: revision.isEmpty
              ? 'आजच्या धड्यातील मुख्य मुद्दे लक्षात ठेवा.'
              : revision,
          sceneType: LessonSceneType.summary,
        ),
  );

  return scenes.take(8).toList();
}

List<String> _sentences(String text) {
  final cleaned = text.trim();
  if (cleaned.isEmpty) return const [];
  return cleaned
      .split(RegExp(r'(?<=[।.?!…])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
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
