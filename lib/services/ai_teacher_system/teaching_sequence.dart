import 'package:mpsc_combine_ai/services/ai_teacher_system/faculty_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';

/// One spoken/visual beat in the Smart Faculty teaching sequence.
///
/// Pipeline per concept / lesson:
/// Introduction → Concept → Example → Memory Trick → PYQ → MCQ →
/// Revision → Summary.
enum TeachingBeatKind {
  /// Lesson-level warm open (title scene).
  titleRead,

  /// Smart Faculty: Introduction
  introduction,

  /// Smart Faculty: Concept (faculty explain — never OCR-read bullets)
  concept,

  /// Smart Faculty: Example
  example,

  /// Soft board / diagram animation hook alongside speech
  showAnimation,

  /// Contrast teaching (woven into Example when tables compare ideas)
  comparison,

  /// Smart Faculty: Memory Trick
  memoryTrick,

  /// Smart Faculty: PYQ angle
  pyq,

  /// Smart Faculty: MCQ check question
  mcq,

  /// Smart Faculty: Revision
  revision,

  /// Smart Faculty: Summary
  summary,

  /// Lesson-level close / full quiz offer
  premiumClose,
}

/// Which MPSC premium card to spotlight during a concept beat.
enum PremiumSpotlight {
  none,
  pyq,
  examTip,
  memoryTrick,
  commonMistake,
  aiMcq,
}

/// Fine-grained teaching step — faculty TEACHES, never OCR-reads bullets.
class TeachingBeat {
  const TeachingBeat({
    required this.kind,
    required this.slideIndex,
    required this.speakText,
    this.revealCount = 1,
    this.activeBulletIndex,
    this.keywords = const [],
    this.openQuizAfter = false,
    this.spotlight = PremiumSpotlight.none,
    this.spotlightText = '',
    this.pauseAfter = true,
  });

  final TeachingBeatKind kind;
  final int slideIndex;
  final String speakText;

  /// How many visual elements to reveal on the Teaching Board.
  final int revealCount;

  /// Bullet currently being taught (highlighted), if any.
  final int? activeBulletIndex;
  final List<String> keywords;

  /// When true, Classroom should offer the MCQ quiz after this beat.
  final bool openQuizAfter;

  final PremiumSpotlight spotlight;
  final String spotlightText;

  /// When true, Classroom inserts [kTeachingParagraphPause] after this beat
  /// before starting the next paragraph (honours Play/Pause/Stop sessions).
  final bool pauseAfter;
}

List<String> _splitSentences(String text) {
  final cleaned = text.trim();
  if (cleaned.isEmpty) return const [];
  return cleaned
      .split(RegExp(r'(?<=[।.?!…])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

bool _lessonIsMarathi(GeneratedLesson lesson) {
  final sample = [
    lesson.topicName,
    lesson.summary,
    if (lesson.slides.isNotEmpty) lesson.slides.first.narration,
    if (lesson.slides.isNotEmpty && lesson.slides.first.bullets.isNotEmpty)
      lesson.slides.first.bullets.first,
  ].join(' ');
  return looksLikeMarathi(sample) || sample.trim().isEmpty;
}

String _at(List<String> items, int i, String fallback) {
  if (items.isEmpty) return fallback;
  return items[i % items.length].trim().isEmpty
      ? fallback
      : items[i % items.length].trim();
}

/// Concept explain prose — never returns a raw bullet list as the script.
String _conceptBody(GeneratedSlide slide, {required bool marathi}) {
  final expansions = slide.bulletExpansions
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (expansions.isNotEmpty) {
    return mergeTeachingParagraph(expansions.take(4).toList());
  }
  final n = slide.narration.trim();
  if (n.isNotEmpty) return n;
  if (slide.bullets.isNotEmpty) {
    final ideas = slide.bullets
        .take(3)
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();
    if (ideas.isEmpty) {
      return marathi
          ? 'ही कल्पना समजून घेऊया — अर्थ काय आहे आणि परीक्षा का विचारते.'
          : 'Let us understand this idea — what it means and why exams ask it.';
    }
    // Teach FROM the ideas; do not OCR-read bullets as the script.
    return marathi
        ? mergeTeachingParagraph([
            'समजा — ${ideas.first} याचा अर्थ असा की परीक्षा संकल्पना व फरक स्पष्ट करायला सांगते, फक्त शब्द पाठ करायला नाही.',
            if (ideas.length > 1)
              'त्याचबरोबर ${ideas[1]} हेही लक्षात ठेवा — हे एकमेकांशी जोडलेले आहे.',
          ])
        : mergeTeachingParagraph([
            'Think of it this way: "${ideas.first}" means the exam wants the concept and contrast — not rote wording.',
            if (ideas.length > 1)
              'Alongside that, remember "${ideas[1]}" — these ideas connect.',
          ]);
  }
  return marathi
      ? 'ही कल्पना परीक्षा दृष्टीने महत्त्वाची आहे — समजून घेऊया.'
      : 'This idea matters for the exam — let us understand it.';
}

String _exampleBody(
  GeneratedLesson lesson,
  GeneratedSlide slide,
  int conceptOrdinal, {
  required bool marathi,
}) {
  final expansions = slide.bulletExpansions
      .map((e) => e.trim())
      .where((e) => e.length > 20)
      .toList();
  if (expansions.length >= 2) {
    return expansions[1];
  }
  if (slide.tableRows.isNotEmpty) {
    final row = slide.tableRows.first
        .where((c) => c.trim().isNotEmpty)
        .join(' — ');
    if (row.isNotEmpty) {
      return marathi
          ? 'तक्त्यात हे असे दिसते — $row. Prelims मध्ये असा फरक थेट विचारला जातो.'
          : 'The table shows — $row. Prelims often asks this contrast directly.';
    }
  }
  final tip = lesson.premium.examTips.isNotEmpty
      ? stripFacultyLabelPrefixes(
          _at(lesson.premium.examTips, conceptOrdinal - 1, ''),
        )
      : '';
  if (tip.isNotEmpty) {
    return marathi
        ? 'उदाहरणार्थ, परीक्षेत असे येते — $tip'
        : 'For example, the exam frames it like this — $tip';
  }
  final bullet =
      slide.bullets.isNotEmpty ? slide.bullets.first.trim() : slide.title.trim();
  if (bullet.isEmpty) {
    return marathi
        ? 'उदाहरणार्थ, Prelims मध्ये असे प्रश्न थेट किंवा अप्रत्यक्ष येतात.'
        : 'For example, Prelims often asks this directly or indirectly.';
  }
  return marathi
      ? 'उदाहरणार्थ, परीक्षेत विचारले जाऊ शकते — "$bullet" योग्य आहे का, किंवा याच्याशी संबंधित फरक कोणता.'
      : 'For example, exams may ask whether "$bullet" is correct, or what contrast it implies.';
}

String _memoryTrickBody(
  GeneratedLesson lesson,
  int conceptOrdinal, {
  required bool marathi,
}) {
  final p = lesson.premium;
  final idx = (conceptOrdinal - 1).clamp(0, 99);
  if (p.memoryTricks.isNotEmpty) {
    final t = stripFacultyLabelPrefixes(_at(p.memoryTricks, idx, ''));
    if (t.isNotEmpty) return t;
  }
  if (p.examTips.isNotEmpty) {
    final t = stripFacultyLabelPrefixes(_at(p.examTips, idx, ''));
    if (t.isNotEmpty) {
      return marathi
          ? 'मुख्य शब्द व संख्या एका वाक्यात बांधा — $t'
          : 'Bind the key word and number into one sentence — $t';
    }
  }
  return marathi
      ? 'मुख्य शब्द, संख्या आणि फरक एका छोट्या वाक्यात बांधून ठेवा.'
      : 'Bind the key word, number, and contrast into one short sentence.';
}

String _pyqBody(
  GeneratedLesson lesson,
  int conceptOrdinal, {
  required bool marathi,
}) {
  final p = lesson.premium;
  final idx = (conceptOrdinal - 1).clamp(0, 99);
  final pyq = stripFacultyLabelPrefixes(
    _at(
      p.pyqInsight,
      idx,
      marathi
          ? 'या संकल्पनेवर मागील प्रश्नपत्रिकांमध्ये थेट किंवा अप्रत्यक्ष प्रश्न येतात — व्याख्या व फरक पक्के ठेवा.'
          : 'Previous papers often touch this idea directly or indirectly — lock the definition and contrast.',
    ),
  );
  final mistake = p.commonMistakes.isNotEmpty
      ? stripFacultyLabelPrefixes(_at(p.commonMistakes, idx, ''))
      : '';
  if (mistake.isNotEmpty) {
    return marathi
        ? '$pyq सावधान — विद्यार्थी अनेकदा अशी चूक करतात: $mistake'
        : '$pyq Careful — students often make this mistake: $mistake';
  }
  return pyq;
}

String _mcqBody(
  GeneratedSlide slide,
  GeneratedLesson lesson, {
  required bool marathi,
}) {
  final sq = slide.sectionQuestion;
  if (sq != null) {
    return marathi
        ? '${sq.question} उत्तर मनात ठरवा; नंतर पर्याय निवडून समज तपासा.'
        : '${sq.question} Decide in your mind; then pick an option to verify.';
  }
  if (lesson.mcqs.isNotEmpty) {
    final q = lesson.mcqs.first.question.trim();
    if (q.isNotEmpty) {
      return marathi
          ? '$q हे समज तपासण्यासाठी आहे — उत्तर मनात ठरवा.'
          : '$q Use this to check understanding — decide your answer.';
    }
  }
  return marathi
      ? 'स्वतःला विचारा — या भागातील मुख्य कल्पना एका वाक्यात काय? उत्तर मनात ठरवा.'
      : 'Ask yourself — what is the one-sentence core of this part? Decide now.';
}

String _revisionBody(GeneratedSlide slide, {required bool marathi}) {
  final ideas = <String>[];
  if (slide.bulletExpansions.isNotEmpty) {
    for (final e in slide.bulletExpansions.take(3)) {
      final s = _splitSentences(e.trim());
      if (s.isNotEmpty) {
        ideas.add(s.first);
      } else if (e.trim().isNotEmpty) {
        ideas.add(e.trim());
      }
    }
  }
  if (ideas.isEmpty) {
    for (final b in slide.bullets.take(3)) {
      final t = b.trim();
      if (t.isNotEmpty) ideas.add(t);
    }
  }
  if (ideas.isEmpty) {
    final n = slide.narration.trim();
    if (n.isNotEmpty) {
      final s = _splitSentences(n);
      ideas.add(s.isNotEmpty ? s.first : n);
    }
  }
  if (ideas.isEmpty) {
    return marathi
        ? '${slide.title} ची मुख्य कल्पना मनात एकदा फिरवा.'
        : 'Replay the core idea of ${slide.title} once in your mind.';
  }
  // Spoken revision — faculty recap, not bullet OCR.
  if (marathi) {
    return mergeTeachingParagraph([
      'पहिली कल्पना — ${ideas.first}',
      if (ideas.length > 1) 'दुसरी कल्पना — ${ideas[1]}',
      if (ideas.length > 2) 'तिसरी कल्पना — ${ideas[2]}',
      'ही तीन गोष्टी मनात ठेवा.',
    ]);
  }
  return mergeTeachingParagraph([
    'First idea — ${ideas.first}',
    if (ideas.length > 1) 'Second idea — ${ideas[1]}',
    if (ideas.length > 2) 'Third idea — ${ideas[2]}',
    'Hold these points together.',
  ]);
}

String _summaryBody(
  GeneratedSlide slide,
  GeneratedLesson lesson, {
  required bool marathi,
}) {
  final summary = lesson.summary.trim();
  final local = slide.narration.trim();
  final core = local.isNotEmpty
      ? local
      : (summary.isNotEmpty
          ? summary
          : (marathi
              ? '${slide.title} समजले — व्याख्या, उदाहरण आणि फरक पक्के.'
              : '${slide.title} is clear — definition, example, and contrast locked.'));
  return marathi
      ? mergeTeachingParagraph([
          core,
          'पुढे जाण्यापूर्वी ही संकल्पना एकदा स्वतःच्या शब्दांत सांगा.',
        ])
      : mergeTeachingParagraph([
          core,
          'Before we continue, say this concept once in your own words.',
        ]);
}

String _sceneSpeak(GeneratedSlide slide, {required bool marathi}) {
  final n = slide.narration.trim();
  if (n.isNotEmpty) return n;
  if (slide.bullets.isNotEmpty) {
    return marathi
        ? 'या भागात आपण ${slide.title} समजून घेणार आहोत.'
        : 'In this part we will understand ${slide.title}.';
  }
  return slide.title;
}

void _appendParagraphBeats({
  required List<TeachingBeat> beats,
  required TeachingBeatKind kind,
  required int slideIndex,
  required String paragraph,
  required int revealCount,
  int? activeBulletIndex,
  List<String> keywords = const [],
  bool openQuizAfter = false,
  PremiumSpotlight spotlight = PremiumSpotlight.none,
  String spotlightText = '',
}) {
  // One spoken paragraph per teaching stage — never sentence-by-sentence TTS.
  final text = facultyNarration(paragraph);
  if (text.isEmpty) return;
  beats.add(
    TeachingBeat(
      kind: kind,
      slideIndex: slideIndex,
      speakText: text,
      revealCount: revealCount,
      activeBulletIndex: activeBulletIndex,
      keywords: keywords,
      openQuizAfter: openQuizAfter,
      spotlight: spotlight,
      spotlightText: spotlightText,
      pauseAfter: false,
    ),
  );
}

/// Builds the Smart Faculty teaching sequence from a [GeneratedLesson].
///
/// Pedagogy per concept (exact order):
/// Introduction → Concept → Example → Memory Trick → PYQ → MCQ →
/// Revision → Summary.
/// Speaks **one stage per beat**, never OCR bullet lists.
/// Marathi faculty copy (MPSC Classroom). [en] kept as locale documentation.
String _faculty(String mr, String en) => mr;

List<TeachingBeat> teachingSequenceFor(GeneratedLesson lesson) {
  final slides = lesson.slides;
  // Always teach in Marathi. Detector still used by helper bodies via [marathi].
  const marathi = true;
  // Touch detector so lesson language remains observable in debug builds.
  assert(() {
    _lessonIsMarathi(lesson);
    return true;
  }());

  if (slides.isEmpty) {
    final script = lesson.script;
    if (script.isEmpty) return const [];
    return _smartFacultyPipelineForScript(script, marathi: marathi);
  }

  final beats = <TeachingBeat>[];
  var conceptOrdinal = 0;

  for (var s = 0; s < slides.length; s++) {
    final slide = slides[s];
    final keywords = slide.keywords;

    switch (slide.sceneType) {
      case LessonSceneType.title:
        final topic = lesson.topicName.trim().isEmpty
            ? slide.title
            : lesson.topicName.trim();
        final body = slide.narration.trim().isNotEmpty
            ? slide.narration.trim()
            : _faculty(
                'आज आपण हा महत्त्वाचा विषय सविस्तर समजून घेणार आहोत.',
                'Today we will understand this important topic in depth.',
              );
        _appendParagraphBeats(
          beats: beats,
          kind: TeachingBeatKind.titleRead,
          slideIndex: s,
          paragraph: buildSmartFacultyStageSpeech(
            stage: SmartFacultyStage.introduction,
            bridge: _faculty(
              'नमस्कार विद्यार्थी मित्रांनो.',
              'Hello students.',
            ),
            body: mergeTeachingParagraph([
              _faculty(
                'आज आपण शिकणार आहोत — $topic.',
                'Today we will learn — $topic.',
              ),
              body,
              _faculty(
                'मी स्लाइडवरील मुद्दे ओळीने वाचणार नाही — संकल्पना समजावून, उदाहरणे, स्मरण युक्त्या आणि PYQ दृष्टी देणार आहे.',
                'I will not read slide bullets line by line — I will explain concepts, give examples, memory tricks, and PYQ angles.',
              ),
            ]),
            marathi: marathi,
          ),
          revealCount: 1,
          keywords: keywords,
        );
        break;

      case LessonSceneType.introduction:
      case LessonSceneType.mainExplanation:
      case LessonSceneType.examples:
        conceptOrdinal++;
        _addSmartFacultyConceptBeats(
          beats: beats,
          lesson: lesson,
          slide: slide,
          slideIndex: s,
          conceptOrdinal: conceptOrdinal,
          marathi: marathi,
          emphasizeExample: slide.sceneType == LessonSceneType.examples,
        );
        break;

      case LessonSceneType.importantPoints:
        // Dedicated PYQ scene (Topic→Video Teacher Scene 6).
        conceptOrdinal++;
        _addSmartFacultyPyqSceneBeats(
          beats: beats,
          lesson: lesson,
          slide: slide,
          slideIndex: s,
          conceptOrdinal: conceptOrdinal,
          marathi: marathi,
        );
        break;

      case LessonSceneType.diagram:
        conceptOrdinal++;
        _addSmartFacultyDiagramBeats(
          beats: beats,
          lesson: lesson,
          slide: slide,
          slideIndex: s,
          conceptOrdinal: conceptOrdinal,
          marathi: marathi,
        );
        break;

      case LessonSceneType.summary:
        final summary = lesson.summary.trim().isNotEmpty
            ? lesson.summary.trim()
            : _sceneSpeak(slide, marathi: marathi);
        _appendParagraphBeats(
          beats: beats,
          kind: TeachingBeatKind.revision,
          slideIndex: s,
          paragraph: buildSmartFacultyStageSpeech(
            stage: SmartFacultyStage.revision,
            body: slide.bullets.isNotEmpty
                ? _faculty(
                    'मुख्य कल्पना: ${slide.bullets.take(3).map((b) => b.trim()).where((b) => b.isNotEmpty).join('; ')}.',
                    'Core ideas: ${slide.bullets.take(3).map((b) => b.trim()).where((b) => b.isNotEmpty).join('; ')}.',
                  )
                : summary,
            marathi: marathi,
          ),
          revealCount: slide.bullets.isEmpty ? 1 : slide.bullets.length,
          keywords: keywords,
        );
        _appendParagraphBeats(
          beats: beats,
          kind: TeachingBeatKind.summary,
          slideIndex: s,
          paragraph: buildSmartFacultyStageSpeech(
            stage: SmartFacultyStage.summary,
            body: mergeTeachingParagraph([
              summary,
              _faculty(
                'परीक्षा आधी हा सारांश एकदा स्वतःच्या शब्दांत सांगा.',
                'Before the exam, say this summary once in your own words.',
              ),
            ]),
            marathi: marathi,
          ),
          revealCount: slide.bullets.isEmpty ? 1 : slide.bullets.length,
          keywords: keywords,
        );
        break;

      case LessonSceneType.quiz:
        _appendParagraphBeats(
          beats: beats,
          kind: TeachingBeatKind.mcq,
          slideIndex: s,
          paragraph: buildSmartFacultyStageSpeech(
            stage: SmartFacultyStage.mcq,
            body: _faculty(
              'आता तीन सराव प्रश्न सोडवून समज तपासूया. चुकीच्या पर्यायांचे स्पष्टीकरणही शिकवण सुरू ठेवेल.',
              'Now let us check understanding with three practice questions. Wrong options are explained too — learning continues.',
            ),
            marathi: marathi,
          ),
          revealCount: 1,
          keywords: keywords,
          openQuizAfter: true,
          spotlight: PremiumSpotlight.aiMcq,
          spotlightText: _faculty(
            'AI MCQ सराव तयार आहे.',
            'AI MCQ practice is ready.',
          ),
        );
        break;
    }
  }

  final premium = lesson.premium;
  if (premium.hasContent) {
    final revisionParts = <String>[
      if (premium.quickRevision.trim().isNotEmpty)
        stripFacultyLabelPrefixes(premium.quickRevision.trim()),
      if (premium.importantFacts.isNotEmpty)
        _faculty(
          'महत्त्वाची तथ्ये म्हणजे ${premium.importantFacts.take(3).join('; ')}.',
          'Key facts are ${premium.importantFacts.take(3).join('; ')}.',
        ),
      if (premium.memoryTricks.isNotEmpty)
        stripFacultyLabelPrefixes(premium.memoryTricks.first),
      if (premium.pyqInsight.isNotEmpty)
        stripFacultyLabelPrefixes(premium.pyqInsight.first),
    ];
    if (revisionParts.isNotEmpty) {
      _appendParagraphBeats(
        beats: beats,
        kind: TeachingBeatKind.revision,
        slideIndex: slides.length - 1,
        paragraph: buildSmartFacultyStageSpeech(
          stage: SmartFacultyStage.revision,
          body: mergeTeachingParagraph(revisionParts),
          marathi: marathi,
        ),
        revealCount: 999,
        keywords: const ['PYQ', 'पुनरावलोकन'],
        spotlight: PremiumSpotlight.pyq,
        spotlightText:
            premium.pyqInsight.isNotEmpty ? premium.pyqInsight.first : '',
      );
      _appendParagraphBeats(
        beats: beats,
        kind: TeachingBeatKind.premiumClose,
        slideIndex: slides.length - 1,
        paragraph: buildSmartFacultyStageSpeech(
          stage: SmartFacultyStage.summary,
          body: _faculty(
            'धडा येथे पूर्ण. आता सरावाने समज पक्की करा.',
            'That closes the lesson. Now lock it with practice.',
          ),
          marathi: marathi,
        ),
        revealCount: 999,
        openQuizAfter: lesson.mcqs.isNotEmpty,
        spotlight: PremiumSpotlight.aiMcq,
        spotlightText: _faculty('सराव तयार आहे.', 'Practice is ready.'),
      );
    }
  } else if (lesson.mcqs.isNotEmpty &&
      (beats.isEmpty || !beats.last.openQuizAfter)) {
    beats.add(
      TeachingBeat(
        kind: TeachingBeatKind.premiumClose,
        slideIndex: slides.length - 1,
        speakText: buildSmartFacultyStageSpeech(
          stage: SmartFacultyStage.mcq,
          body: _faculty(
            'आता तीन AI MCQs सोडवून समज तपासूया.',
            'Now let us check understanding with three AI MCQs.',
          ),
          marathi: marathi,
        ),
        revealCount: 999,
        openQuizAfter: true,
        spotlight: PremiumSpotlight.aiMcq,
        pauseAfter: false,
      ),
    );
  }

  return beats;
}

List<TeachingBeat> _smartFacultyPipelineForScript(
  List<String> script, {
  required bool marathi,
}) {
  final beats = <TeachingBeat>[];
  final joined = script.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (joined.isEmpty) return const [];

  final stages = <(TeachingBeatKind, SmartFacultyStage, String)>[
    (
      TeachingBeatKind.introduction,
      SmartFacultyStage.introduction,
      joined.first,
    ),
    (
      TeachingBeatKind.concept,
      SmartFacultyStage.concept,
      joined.length > 1 ? joined[1] : joined.first,
    ),
    (
      TeachingBeatKind.example,
      SmartFacultyStage.example,
      joined.length > 2
          ? joined[2]
          : (marathi
              ? 'उदाहरणार्थ, Prelims मध्ये ही संकल्पना थेट येऊ शकते.'
              : 'For example, Prelims may ask this idea directly.'),
    ),
    (
      TeachingBeatKind.memoryTrick,
      SmartFacultyStage.memoryTrick,
      joined.length > 3
          ? joined[3]
          : (marathi
              ? 'मुख्य शब्द एका छोट्या वाक्यात बांधा.'
              : 'Bind the key word into one short sentence.'),
    ),
    (
      TeachingBeatKind.pyq,
      SmartFacultyStage.pyq,
      joined.length > 4
          ? joined[4]
          : (marathi
              ? 'मागील प्रश्नपत्रिकांमध्ये ही कल्पना वारंवार दिसते.'
              : 'Previous papers return to this idea often.'),
    ),
    (
      TeachingBeatKind.mcq,
      SmartFacultyStage.mcq,
      joined.length > 5
          ? joined[5]
          : (marathi
              ? 'स्वतःला विचारा — मुख्य कल्पना काय?'
              : 'Ask yourself — what is the core idea?'),
    ),
    (
      TeachingBeatKind.revision,
      SmartFacultyStage.revision,
      joined.length > 6
          ? joined[6]
          : mergeTeachingParagraph(joined.take(3).toList()),
    ),
    (
      TeachingBeatKind.summary,
      SmartFacultyStage.summary,
      joined.length > 7 ? joined[7] : joined.last,
    ),
  ];

  for (final entry in stages) {
    _appendParagraphBeats(
      beats: beats,
      kind: entry.$1,
      slideIndex: 0,
      paragraph: buildSmartFacultyStageSpeech(
        stage: entry.$2,
        body: entry.$3,
        marathi: marathi,
      ),
      revealCount: 1,
    );
  }
  return beats;
}

void _addSmartFacultyConceptBeats({
  required List<TeachingBeat> beats,
  required GeneratedLesson lesson,
  required GeneratedSlide slide,
  required int slideIndex,
  required int conceptOrdinal,
  required bool marathi,
  bool emphasizeExample = false,
}) {
  final keywords = slide.keywords;
  final reveal = slide.bullets.isEmpty ? 1 : slide.bullets.length;
  final tipSpotlight = lesson.premium.examTips.isNotEmpty
      ? _at(lesson.premium.examTips, conceptOrdinal - 1, '')
      : '';
  final trickSpotlight = lesson.premium.memoryTricks.isNotEmpty
      ? _at(lesson.premium.memoryTricks, conceptOrdinal - 1, '')
      : '';
  final pyqSpotlight = lesson.premium.pyqInsight.isNotEmpty
      ? _at(lesson.premium.pyqInsight, conceptOrdinal - 1, '')
      : '';

  // 1) Introduction
  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.introduction,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.introduction,
      body: mergeTeachingParagraph([
        marathi
            ? 'आता आपण शिकणार आहोत — ${slide.title}.'
            : 'Now we will learn — ${slide.title}.',
        marathi
            ? 'या भागात संकल्पना, उदाहरण, स्मरण युक्ती, मागील प्रश्न आणि एक छोटा चेक प्रश्न येईल.'
            : 'In this part: concept, example, memory trick, previous-year angle, and a short check question.',
        if (slide.narration.trim().isNotEmpty &&
            slide.sceneType == LessonSceneType.introduction)
          slide.narration.trim(),
      ]),
      marathi: marathi,
    ),
    revealCount: 1,
    keywords: keywords,
  );

  // Soft visual pulse for non-bullet boards.
  if (slide.resolvedVisualType != SlideVisualType.bullets) {
    _appendParagraphBeats(
      beats: beats,
      kind: TeachingBeatKind.showAnimation,
      slideIndex: slideIndex,
      paragraph: marathi
          ? 'आता बोर्डवर ही कल्पना पहा — जसे मी समजावते तसे आकृती सक्रिय होईल.'
          : 'Watch the board — as I explain, the visual will light up.',
      revealCount: 1,
      keywords: keywords,
    );
  }

  // 2) Concept
  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.concept,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.concept,
      body: _conceptBody(slide, marathi: marathi),
      marathi: marathi,
    ),
    revealCount: reveal,
    activeBulletIndex: slide.bullets.isNotEmpty ? 0 : null,
    keywords: keywords,
  );

  // 3) Example (+ optional comparison)
  final exampleText = emphasizeExample
      ? mergeTeachingParagraph([
          _exampleBody(lesson, slide, conceptOrdinal, marathi: marathi),
          if (slide.narration.trim().isNotEmpty) slide.narration.trim(),
        ])
      : _exampleBody(lesson, slide, conceptOrdinal, marathi: marathi);
  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.example,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.example,
      body: exampleText,
      marathi: marathi,
    ),
    revealCount: reveal,
    activeBulletIndex:
        slide.bullets.length > 1 ? 1 : (slide.bullets.isNotEmpty ? 0 : null),
    keywords: keywords,
    spotlight: tipSpotlight.isNotEmpty
        ? PremiumSpotlight.examTip
        : PremiumSpotlight.none,
    spotlightText: tipSpotlight,
  );

  if (slide.tableRows.length >= 2 || slide.bullets.length >= 2) {
    final a = slide.bullets.isNotEmpty ? slide.bullets.first.trim() : '';
    final b = slide.bullets.length > 1 ? slide.bullets[1].trim() : '';
    _appendParagraphBeats(
      beats: beats,
      kind: TeachingBeatKind.comparison,
      slideIndex: slideIndex,
      paragraph: buildSmartFacultyStageSpeech(
        stage: SmartFacultyStage.example,
        bridge: marathi
            ? 'तुलना करून पाहूया — फरक लक्षात आला की गोंधळ टळतो.'
            : 'Let us compare — clarity comes from contrast.',
        body: (a.isNotEmpty && b.isNotEmpty)
            ? (marathi
                ? 'एक बाजू — $a. दुसरी बाजू — $b.'
                : 'One side — $a. Other side — $b.')
            : (slide.tableHeaders.isNotEmpty
                ? (marathi
                    ? 'तक्त्यातील स्तंभ: ${slide.tableHeaders.join(', ')}.'
                    : 'Table columns: ${slide.tableHeaders.join(', ')}.')
                : ''),
        marathi: marathi,
      ),
      revealCount: reveal,
      keywords: keywords,
      spotlight: lesson.premium.commonMistakes.isNotEmpty
          ? PremiumSpotlight.commonMistake
          : PremiumSpotlight.none,
      spotlightText: lesson.premium.commonMistakes.isNotEmpty
          ? _at(lesson.premium.commonMistakes, conceptOrdinal - 1, '')
          : '',
    );
  }

  // 4) Memory Trick
  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.memoryTrick,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.memoryTrick,
      body: _memoryTrickBody(lesson, conceptOrdinal, marathi: marathi),
      marathi: marathi,
    ),
    revealCount: reveal,
    keywords: keywords,
    spotlight: PremiumSpotlight.memoryTrick,
    spotlightText: trickSpotlight,
  );

  // 5) PYQ
  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.pyq,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.pyq,
      body: _pyqBody(lesson, conceptOrdinal, marathi: marathi),
      marathi: marathi,
    ),
    revealCount: reveal,
    keywords: keywords,
    spotlight: PremiumSpotlight.pyq,
    spotlightText: pyqSpotlight,
  );

  // 6) MCQ — Classroom aligns section-question UI with this beat.
  final sq = slide.sectionQuestion;
  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.mcq,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.mcq,
      body: _mcqBody(slide, lesson, marathi: marathi),
      marathi: marathi,
    ),
    revealCount: reveal,
    keywords: keywords,
    spotlight: PremiumSpotlight.aiMcq,
    spotlightText: sq?.question ??
        (marathi ? 'समज तपासणी' : 'Understanding check'),
  );

  // 7) Revision
  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.revision,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.revision,
      body: _revisionBody(slide, marathi: marathi),
      marathi: marathi,
    ),
    revealCount: reveal,
    keywords: keywords,
  );

  // 8) Summary
  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.summary,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.summary,
      body: _summaryBody(slide, lesson, marathi: marathi),
      marathi: marathi,
    ),
    revealCount: reveal,
    keywords: keywords,
  );
}

/// Dedicated PYQ teaching scene (Scene 6 in Topic→Video Teacher).
void _addSmartFacultyPyqSceneBeats({
  required List<TeachingBeat> beats,
  required GeneratedLesson lesson,
  required GeneratedSlide slide,
  required int slideIndex,
  required int conceptOrdinal,
  required bool marathi,
}) {
  final keywords = slide.keywords.isNotEmpty
      ? slide.keywords
      : const ['PYQ', 'परीक्षा'];
  final reveal = slide.bullets.isEmpty ? 2 : slide.bullets.length;
  final pyqText = _pyqBody(lesson, conceptOrdinal, marathi: marathi);
  final board = slide.narration.trim().isNotEmpty
      ? slide.narration.trim()
      : (slide.bullets.isNotEmpty
          ? slide.bullets.take(3).join('; ')
          : pyqText);

  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.introduction,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.introduction,
      body: marathi
          ? 'आता PYQ दृष्टीने पाहा — परीक्षा या विषयाला कशी विचारते.'
          : 'Now the PYQ angle — how exams frame this topic.',
      marathi: marathi,
    ),
    revealCount: 1,
    keywords: keywords,
    spotlight: PremiumSpotlight.pyq,
    spotlightText: pyqText,
  );

  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.pyq,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.pyq,
      body: mergeTeachingParagraph([board, pyqText]),
      marathi: marathi,
    ),
    revealCount: reveal,
    keywords: keywords,
    spotlight: PremiumSpotlight.pyq,
    spotlightText: pyqText,
  );

  if (lesson.premium.commonMistakes.isNotEmpty) {
    final mistake = stripFacultyLabelPrefixes(
      _at(lesson.premium.commonMistakes, conceptOrdinal - 1, ''),
    );
    if (mistake.isNotEmpty) {
      _appendParagraphBeats(
        beats: beats,
        kind: TeachingBeatKind.memoryTrick,
        slideIndex: slideIndex,
        paragraph: buildSmartFacultyStageSpeech(
          stage: SmartFacultyStage.memoryTrick,
          body: marathi
              ? 'सावधान — सामान्य चूक: $mistake'
              : 'Careful — common mistake: $mistake',
          marathi: marathi,
        ),
        revealCount: reveal,
        keywords: keywords,
        spotlight: PremiumSpotlight.commonMistake,
        spotlightText: mistake,
      );
    }
  }

  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.mcq,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.mcq,
      body: _mcqBody(slide, lesson, marathi: marathi),
      marathi: marathi,
    ),
    revealCount: reveal,
    keywords: keywords,
    spotlight: PremiumSpotlight.aiMcq,
  );
}

void _addSmartFacultyDiagramBeats({
  required List<TeachingBeat> beats,
  required GeneratedLesson lesson,
  required GeneratedSlide slide,
  required int slideIndex,
  required int conceptOrdinal,
  required bool marathi,
}) {
  final keywords = slide.keywords;
  final steps = _visualSteps(slide);
  final labels = <String>[];
  for (var i = 1; i <= steps; i++) {
    final label = i <= slide.bullets.length
        ? slide.bullets[i - 1].trim()
        : (i <= slide.flowchart.length
            ? slide.flowchart[i - 1].label
            : (i <= slide.timeline.length
                ? '${slide.timeline[i - 1].year} — ${slide.timeline[i - 1].label}'
                : (i <= slide.mapRegions.length
                    ? slide.mapRegions[i - 1]
                    : '')));
    if (label.isNotEmpty) labels.add(label);
  }

  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.introduction,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.introduction,
      body: mergeTeachingParagraph([
        marathi
            ? 'आता आकृती किंवा प्रवाहपट पाहून ${slide.title} समजून घेऊया.'
            : 'Now let us understand ${slide.title} with a diagram or flow.',
        marathi
            ? 'प्रत्येक टप्पा एक कल्पना आहे — ओळीने वाचन नाही, अर्थ समजावणी.'
            : 'Each step is one idea — explanation, not line-by-line reading.',
      ]),
      marathi: marathi,
    ),
    revealCount: 1,
    keywords: keywords,
  );

  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.concept,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.concept,
      body: _sceneSpeak(slide, marathi: marathi),
      marathi: marathi,
    ),
    revealCount: 1,
    keywords: keywords,
  );

  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.showAnimation,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.example,
      bridge: marathi
          ? 'चला आकृती समजून घेऊया — प्रत्येक टप्पा एक कल्पना आहे.'
          : 'Let us walk the diagram — each step is one idea.',
      body: mergeTeachingParagraph([
        ...labels.map(
          (l) => marathi
              ? 'पुढचा टप्पा म्हणजे $l — हे पाऊल लक्षात ठेवा.'
              : 'Next step means $l — remember this link.',
        ),
      ]),
      marathi: marathi,
    ),
    revealCount: 1,
    keywords: keywords,
  );

  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.memoryTrick,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.memoryTrick,
      body: _memoryTrickBody(lesson, conceptOrdinal, marathi: marathi),
      marathi: marathi,
    ),
    revealCount: steps,
    keywords: keywords,
    spotlight: PremiumSpotlight.memoryTrick,
    spotlightText: lesson.premium.memoryTricks.isNotEmpty
        ? _at(lesson.premium.memoryTricks, conceptOrdinal - 1, '')
        : '',
  );

  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.pyq,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.pyq,
      body: _pyqBody(lesson, conceptOrdinal, marathi: marathi),
      marathi: marathi,
    ),
    revealCount: steps,
    keywords: keywords,
    spotlight: PremiumSpotlight.pyq,
    spotlightText: lesson.premium.pyqInsight.isNotEmpty
        ? _at(lesson.premium.pyqInsight, conceptOrdinal - 1, '')
        : '',
  );

  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.mcq,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.mcq,
      body: _mcqBody(slide, lesson, marathi: marathi),
      marathi: marathi,
    ),
    revealCount: steps,
    keywords: keywords,
    spotlight: PremiumSpotlight.aiMcq,
    spotlightText: slide.sectionQuestion?.question ??
        (marathi ? 'समज तपासणी' : 'Understanding check'),
  );

  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.revision,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.revision,
      body: labels.isNotEmpty
          ? (marathi
              ? 'आकृतीचे टप्पे: ${labels.take(3).join('; ')}.'
              : 'Diagram steps: ${labels.take(3).join('; ')}.')
          : _revisionBody(slide, marathi: marathi),
      marathi: marathi,
    ),
    revealCount: steps,
    keywords: keywords,
  );

  _appendParagraphBeats(
    beats: beats,
    kind: TeachingBeatKind.summary,
    slideIndex: slideIndex,
    paragraph: buildSmartFacultyStageSpeech(
      stage: SmartFacultyStage.summary,
      body: marathi
          ? 'ही रचना परीक्षा प्रश्नात थेट उपयोगी पडते. पहिला टप्पा कोणता — ते मनात ठेवा.'
          : 'This structure maps straight to exam questions. Remember what the first step is.',
      marathi: marathi,
    ),
    revealCount: steps,
    keywords: keywords,
  );
}

/// First beat index that teaches [slideIndex] (for seek / search).
int firstBeatIndexForSlide(List<TeachingBeat> beats, int slideIndex) {
  final i = beats.indexWhere((b) => b.slideIndex == slideIndex);
  return i < 0 ? 0 : i;
}

int _visualSteps(GeneratedSlide slide) {
  if (slide.flowchart.isNotEmpty) return slide.flowchart.length;
  if (slide.timeline.isNotEmpty) return slide.timeline.length;
  if (slide.mapRegions.isNotEmpty) return slide.mapRegions.length;
  if (slide.drawSteps.isNotEmpty) return slide.drawSteps.length;
  if (slide.bullets.isNotEmpty) return slide.bullets.length;
  return 1;
}
