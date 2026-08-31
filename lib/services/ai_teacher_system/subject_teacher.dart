/// MPSC subject-wise AI Teacher. Detected from the student's topic, then
/// used to pick a distinct classroom voice, visuals, and lesson arc.
enum MpscTeachingSubject {
  polity,
  history,
  geography,
  economics,
  science,
  environment,
}

extension MpscTeachingSubjectX on MpscTeachingSubject {
  String get id {
    switch (this) {
      case MpscTeachingSubject.polity:
        return 'polity';
      case MpscTeachingSubject.history:
        return 'history';
      case MpscTeachingSubject.geography:
        return 'geography';
      case MpscTeachingSubject.economics:
        return 'economics';
      case MpscTeachingSubject.science:
        return 'science';
      case MpscTeachingSubject.environment:
        return 'environment';
    }
  }

  static MpscTeachingSubject? tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'polity':
        return MpscTeachingSubject.polity;
      case 'history':
        return MpscTeachingSubject.history;
      case 'geography':
        return MpscTeachingSubject.geography;
      case 'economics':
        return MpscTeachingSubject.economics;
      case 'science':
        return MpscTeachingSubject.science;
      case 'environment':
        return MpscTeachingSubject.environment;
      default:
        return null;
    }
  }

  String get nameEn {
    switch (this) {
      case MpscTeachingSubject.polity:
        return 'Polity';
      case MpscTeachingSubject.history:
        return 'History';
      case MpscTeachingSubject.geography:
        return 'Geography';
      case MpscTeachingSubject.economics:
        return 'Economics';
      case MpscTeachingSubject.science:
        return 'Science';
      case MpscTeachingSubject.environment:
        return 'Environment';
    }
  }

  String get nameMr {
    switch (this) {
      case MpscTeachingSubject.polity:
        return 'राज्यव्यवस्था';
      case MpscTeachingSubject.history:
        return 'इतिहास';
      case MpscTeachingSubject.geography:
        return 'भूगोल';
      case MpscTeachingSubject.economics:
        return 'अर्थशास्त्र';
      case MpscTeachingSubject.science:
        return 'विज्ञान';
      case MpscTeachingSubject.environment:
        return 'पर्यावरण';
    }
  }

  /// Classroom style for source-grounded RAG answers (never invents articles/dates).
  String get groundedRagStyle {
    switch (this) {
      case MpscTeachingSubject.polity:
        return 'POLITY: Constitution, Articles, institutions, and comparisons. '
            'Cite article numbers only when they appear in retrieved chunks.';
      case MpscTeachingSubject.history:
        return 'HISTORY: Chronology, causes, events, personalities, consequences. '
            'Give dates only when they appear in retrieved chunks.';
      case MpscTeachingSubject.geography:
        return 'GEOGRAPHY: Locations, processes, maps, cause-effect, examples.';
      case MpscTeachingSubject.economics:
        return 'ECONOMICS: Concept → example → impact → exam application.';
      case MpscTeachingSubject.science:
        return 'SCIENCE: Concept → mechanism → example → application.';
      case MpscTeachingSubject.environment:
        return 'ENVIRONMENT: Process → ecosystem → examples → exam relevance.';
    }
  }

  String get teacherTitleMr => '$nameMr शिक्षक';

  String get displayName => '$nameMr · $nameEn Teacher';

  String get classroomHook {
    switch (this) {
      case MpscTeachingSubject.polity:
        return 'आज आपण घटनात्मक भाषेत, कलमे आणि तुलना यांच्यासह शिकणार आहोत.';
      case MpscTeachingSubject.history:
        return 'आज आपण ही गोष्ट कालगणनेने, कारणे आणि परिणामांसह ऐकणार आहोत.';
      case MpscTeachingSubject.geography:
        return 'आज आपण नकाशा, आकृत्या आणि स्थानावरून हा विषय पाहणार आहोत.';
      case MpscTeachingSubject.economics:
        return 'आज आपण सोप्या उदाहरणांनी, आलेखांनी आणि रोजच्या अर्थव्यवस्थेने शिकणार आहोत.';
      case MpscTeachingSubject.science:
        return 'आज आपण संकल्पना, आकृती आणि परीक्षेतील उपयोग यांच्यासह विज्ञान शिकणार आहोत.';
      case MpscTeachingSubject.environment:
        return 'आज आपण परिसंस्था, प्रक्रिया आकृत्या आणि संवर्धन संकल्पनांसह शिकणार आहोत.';
    }
  }

  /// ElevenLabs premade voice — distinct timbre per subject teacher.
  String get elevenLabsVoiceId {
    switch (this) {
      case MpscTeachingSubject.polity:
        return const String.fromEnvironment(
          'ELEVENLABS_VOICE_POLITY',
          defaultValue: 'pNInz6obpgDQGcFmaJgB', // Adam — formal, measured
        );
      case MpscTeachingSubject.history:
        return const String.fromEnvironment(
          'ELEVENLABS_VOICE_HISTORY',
          defaultValue: '2EiwWnXFnvU5JabPnv8n', // Clyde — storytelling
        );
      case MpscTeachingSubject.geography:
        return const String.fromEnvironment(
          'ELEVENLABS_VOICE_GEOGRAPHY',
          defaultValue: 'ThT5KcBeYPX3keUQqHPh', // Dorothy — clear explainer
        );
      case MpscTeachingSubject.economics:
        return const String.fromEnvironment(
          'ELEVENLABS_VOICE_ECONOMICS',
          defaultValue: 'ErXwobaYiN019PkySvjV', // Antoni — practical
        );
      case MpscTeachingSubject.science:
        return const String.fromEnvironment(
          'ELEVENLABS_VOICE_SCIENCE',
          defaultValue: '21m00Tcm4TlvDq8ikWAM', // Rachel — clear explainer
        );
      case MpscTeachingSubject.environment:
        return const String.fromEnvironment(
          'ELEVENLABS_VOICE_ENVIRONMENT',
          defaultValue: 'ThT5KcBeYPX3keUQqHPh', // Dorothy — clear explainer
        );
    }
  }

  /// ElevenLabs voice_settings for this subject's narration tone.
  Map<String, Object> get elevenLabsVoiceSettings {
    switch (this) {
      case MpscTeachingSubject.polity:
        return const {
          'stability': 0.72,
          'similarity_boost': 0.82,
          'style': 0.08,
          'use_speaker_boost': true,
          'speed': 0.90,
        };
      case MpscTeachingSubject.history:
        return const {
          'stability': 0.42,
          'similarity_boost': 0.78,
          'style': 0.48,
          'use_speaker_boost': true,
          'speed': 0.94,
        };
      case MpscTeachingSubject.geography:
        return const {
          'stability': 0.55,
          'similarity_boost': 0.80,
          'style': 0.22,
          'use_speaker_boost': true,
          'speed': 0.96,
        };
      case MpscTeachingSubject.economics:
        return const {
          'stability': 0.50,
          'similarity_boost': 0.75,
          'style': 0.28,
          'use_speaker_boost': true,
          'speed': 1.02,
        };
      case MpscTeachingSubject.science:
        return const {
          'stability': 0.58,
          'similarity_boost': 0.80,
          'style': 0.18,
          'use_speaker_boost': true,
          'speed': 0.97,
        };
      case MpscTeachingSubject.environment:
        return const {
          'stability': 0.56,
          'similarity_boost': 0.80,
          'style': 0.20,
          'use_speaker_boost': true,
          'speed': 0.96,
        };
    }
  }
}

/// Detects Polity / History / Geography / Economics from a free-text topic.
MpscTeachingSubject detectMpscTeachingSubject(
  String topic, {
  String? hint,
}) {
  final text = '${topic.trim()} ${hint ?? ''}'.toLowerCase();
  final compact = text.replaceAll(RegExp(r'\s+'), ' ');

  final scores = <MpscTeachingSubject, int>{
    MpscTeachingSubject.polity: _score(compact, _polityKeys),
    MpscTeachingSubject.history: _score(compact, _historyKeys),
    MpscTeachingSubject.geography: _score(compact, _geographyKeys),
    MpscTeachingSubject.economics: _score(compact, _economicsKeys),
    MpscTeachingSubject.science: _score(compact, _scienceKeys),
    MpscTeachingSubject.environment: _score(compact, _environmentKeys),
  };

  // Explicit subject words in the hint/title win ties.
  if (compact.contains('polity') ||
      compact.contains('राज्यव्यवस्था') ||
      compact.contains('राज्यघटना') ||
      compact.contains('constitution')) {
    scores[MpscTeachingSubject.polity] =
        (scores[MpscTeachingSubject.polity] ?? 0) + 8;
  }
  if (compact.contains('history') || compact.contains('इतिहास')) {
    scores[MpscTeachingSubject.history] =
        (scores[MpscTeachingSubject.history] ?? 0) + 8;
  }
  if (compact.contains('geography') || compact.contains('भूगोल')) {
    scores[MpscTeachingSubject.geography] =
        (scores[MpscTeachingSubject.geography] ?? 0) + 8;
  }
  if (compact.contains('economics') ||
      compact.contains('अर्थशास्त्र') ||
      compact.contains('economy')) {
    scores[MpscTeachingSubject.economics] =
        (scores[MpscTeachingSubject.economics] ?? 0) + 8;
  }
  if (compact.contains('science') ||
      compact.contains('विज्ञान') ||
      compact.contains('भौतिक') ||
      compact.contains('रसायन')) {
    scores[MpscTeachingSubject.science] =
        (scores[MpscTeachingSubject.science] ?? 0) + 8;
  }
  if (compact.contains('environment') ||
      compact.contains('पर्यावरण') ||
      compact.contains('ecology') ||
      compact.contains('ecosystem') ||
      compact.contains('परिसंस्था')) {
    scores[MpscTeachingSubject.environment] =
        (scores[MpscTeachingSubject.environment] ?? 0) + 8;
  }

  var best = MpscTeachingSubject.geography;
  var bestScore = -1;
  for (final e in scores.entries) {
    if (e.value > bestScore) {
      best = e.key;
      bestScore = e.value;
    }
  }
  return best;
}

/// Null when the topic does not clearly match a subject — Gemini must detect it.
MpscTeachingSubject? tryDetectMpscTeachingSubject(
  String topic, {
  String? hint,
}) {
  final text = '${topic.trim()} ${hint ?? ''}'.toLowerCase();
  final compact = text.replaceAll(RegExp(r'\s+'), ' ');
  final scores = <MpscTeachingSubject, int>{
    MpscTeachingSubject.polity: _score(compact, _polityKeys),
    MpscTeachingSubject.history: _score(compact, _historyKeys),
    MpscTeachingSubject.geography: _score(compact, _geographyKeys),
    MpscTeachingSubject.economics: _score(compact, _economicsKeys),
    MpscTeachingSubject.science: _score(compact, _scienceKeys),
    MpscTeachingSubject.environment: _score(compact, _environmentKeys),
  };
  var bestScore = 0;
  MpscTeachingSubject? best;
  for (final e in scores.entries) {
    if (e.value > bestScore) {
      best = e.key;
      bestScore = e.value;
    }
  }
  return bestScore > 0 ? best : null;
}

/// Style block for RAG-grounded Gemini calls.
String ragGroundedTeachingStyle(String query, {String? hint}) {
  final subject = tryDetectMpscTeachingSubject(query, hint: hint);
  return subject?.groundedRagStyle ??
      'Match the teaching style to the retrieved source subject '
          '(Polity / History / Geography / Economics / Science / Environment).';
}

int _score(String text, List<String> keys) {
  var n = 0;
  for (final k in keys) {
    if (text.contains(k)) n++;
  }
  return n;
}

const _polityKeys = <String>[
  'मूलभूत अधिकार',
  'मूलभूत कर्तव्य',
  'राज्यघटना',
  'संविधान',
  'constitution',
  'article',
  'कलम',
  'संसद',
  'sansad',
  'parliament',
  'लोकसभा',
  'राज्यसभा',
  'राष्ट्रपती',
  'president',
  'राज्यपाल',
  'governor',
  'न्यायव्यवस्था',
  'supreme court',
  'उच्च न्यायालय',
  'fundamental right',
  'dpsp',
  'मार्गदर्शक तत्त्व',
  'संघराज्य',
  'federal',
  'निवडणूक',
  'election',
  'पंचायत',
  'महानगरपालिका',
  'आणीबाणी',
  'emergency',
  'नागरिकता',
  'citizenship',
  'प्रस्तावना',
  'preamble',
  'दुरुस्ती',
  'amendment',
  'मंत्रिमंडळ',
  'cabinet',
  'impeach',
  'speaker',
  'cag',
  'याचिका',
  'writ',
  'pil',
  'राज्यपाल',
  'विधानसभा',
  'विधानपरिषद',
  'संसदीय',
  'संघ सूची',
];

const _historyKeys = <String>[
  'इतिहास',
  'history',
  'शिवाजी',
  'छत्रपती',
  'पेशवा',
  'पेशवे',
  'पेशवाई',
  'मराठा',
  'maratha',
  'मुघल',
  'mughal',
  'स्वातंत्र्य',
  'freedom',
  'गांधी',
  'gandhi',
  '१८५७',
  '1857',
  'उठाव',
  'चळवळ',
  'movement',
  'सत्याग्रह',
  'satyagraha',
  'काँग्रेस',
  'congress',
  'साम्राज्य',
  'empire',
  'युद्ध',
  'war',
  'राजवंश',
  'dynasty',
  'प्राचीन',
  'ancient',
  'मध्ययुगीन',
  'medieval',
  'आधुनिक',
  'modern',
  'हडप्पा',
  'harappa',
  'अशोक',
  'ashoka',
  'गुप्त',
  'gupta',
  'निजाम',
  'आदिलशाही',
  'कालरेषा',
  'timeline',
  'क्रांती',
  'revolt',
  'तिलक',
  'फुले',
  'आंबेडकर चळवळ',
];

const _geographyKeys = <String>[
  'भूगोल',
  'geography',
  'नदी',
  'river',
  'गोदावरी',
  'कृष्णा',
  'भीमा',
  'तापी',
  'तापी',
  'नर्मदा',
  'गंगा',
  'यमुना',
  'कावेरी',
  'महानदी',
  'पर्वत',
  'mountain',
  'पठार',
  'plateau',
  'मृदा',
  'महाराष्ट्रातील मृदा',
  'soil',
  'मान्सून',
  'monsoon',
  'हवामान',
  'climate',
  'नकाशा',
  'map',
  'पाऊस',
  'rainfall',
  'वन',
  'forest',
  'खनिज',
  'mineral',
  'किनारपट्टी',
  'coast',
  'सह्याद्री',
  'western ghat',
  'दख्खन',
  'deccan',
  'सिंचन',
  'irrigation',
  'पीक',
  'crop',
  'जलनिस्सारण',
  'drainage',
  'सागर',
  'ocean',
  'खाडी',
  'घाट',
  'महाराष्ट्रातील',
  'महाराष्ट्राचा भूगोल',
  'स्थान',
  'location',
  'भूस्खलन',
  'भूकंप',
];

const _economicsKeys = <String>[
  'अर्थशास्त्र',
  'economics',
  'economy',
  'gdp',
  'जीडीपी',
  'जी डी पी',
  'चलनवाढ',
  'महागाई',
  'inflation',
  'rbi',
  'रिझर्व्ह',
  'रिझर्व बँक',
  'अर्थसंकल्प',
  'budget',
  'कर',
  'tax',
  'gst',
  'जीएसटी',
  'बँक',
  'banking',
  'दारिद्र्य',
  'poverty',
  'बेरोजगारी',
  'unemployment',
  'मौद्रिक',
  'monetary',
  'राजकोषीय',
  'fiscal',
  'राष्ट्रीय उत्पन्न',
  'national income',
  'मागणी',
  'demand',
  'पुरवठा',
  'supply',
  'उदारीकरण',
  'disinvestment',
  'विनिवेश',
  'निती आयोग',
  'niti',
  'पंचवार्षिक',
  'five year',
  'रेपो',
  'repo',
  'व्याजदर',
  'interest rate',
  'चलन',
  'currency',
  'आयात',
  'निर्यात',
  'export',
  'import',
  'महाराष्ट्र अर्थव्यवस्था',
];

const _scienceKeys = <String>[
  'विज्ञान',
  'science',
  'भौतिक',
  'physics',
  'रसायन',
  'chemistry',
  'जीवशास्त्र',
  'biology',
  'प्रकाश',
  'light',
  'गुरुत्व',
  'gravity',
  'पेशी',
  'cell',
  'अणू',
  'atom',
  'ऊर्जा',
  'energy',
  'विद्युत',
  'electric',
  'चुंबक',
  'magnet',
  'आम्ल',
  'acid',
  'क्षार',
  'base',
  'प्रकाशसंश्लेषण',
  'photosynthesis',
  'वनस्पती',
  'प्राणी',
  'dna',
  'डीएनए',
  'न्यूटन',
  'newton',
  'उष्णता',
  'heat',
  'ध्वनी',
  'sound',
  'गति',
  'motion',
  'बल',
  'force',
  'आवर्त सारणी',
  'periodic',
];

const _environmentKeys = <String>[
  'पर्यावरण',
  'environment',
  'ecology',
  'ecosystem',
  'परिसंस्था',
  'जैवविविधता',
  'biodiversity',
  'प्रदूषण',
  'pollution',
  'हरितगृह',
  'greenhouse',
  'ओझोन',
  'ozone',
  'संवर्धन',
  'conservation',
  'वन्यजीव',
  'wildlife',
  'अन्नसाखळी',
  'food chain',
  'जैवमंडल',
  'biosphere',
  'रामसर',
  'ramsar',
  'हवा प्रदूषण',
  'जल प्रदूषण',
  'climate change',
  'हवामान बदल',
];

/// Shared JSON lesson contract + subject-specific classroom persona.
String lessonSystemPrompt(MpscTeachingSubject? subject) {
  final nameEn = subject?.nameEn ?? 'MPSC';
  final forcedSubject = subject == null
      ? 'STEP 1: detect whether the topic is Polity, History, Geography (including Maharashtra Geography), Economics, Environment, or Science. Then teach in that style. Never default to Parliament/संसद unless that is the topic.'
      : 'You are the $nameEn Teacher. Teach only as a $nameEn classroom teacher.';
  final subjectNameRule = subject == null
      ? 'subjectName MUST be the detected subject as "मराठी · English Teacher".'
      : 'topicName is the student topic; subjectName MUST be "${subject.displayName}".';
  return '''
You are an MPSC COMBINE AI teacher (Combined Group B and C).
$forcedSubject
You are NOT a generic tutor. Teach the EXACT student topic. Never substitute a different topic (never teach संसद / Parliament unless that is the topic).

GOAL: A 5–8 minute Marathi classroom lecture with 8–15 educational slides.
Simple Marathi. Teach the concept from basic to advanced. Include MPSC Group B & C relevance.
Never invent facts. Avoid unnecessary English. Do not repeat the same paragraph.

OUTPUT: ONE JSON object only (no Markdown fences, no commentary).

JSON SHAPE (include all keys):
topic, subject, topicName, subjectName, introduction, concepts[], important_facts[],
mpsc_points[], examples[], exam_traps[], memory_tricks[], revision_points[],
teaching_script (full continuous Marathi lecture), script[] (one paragraph per slide),
summary, notes[], slides[], mcqs[], pyqs[],
premium { introduction, mainConcepts[], importantFacts[], examTips[], examples[],
examTraps[], memoryTricks[], commonMistakes[], onePageSummary, quickRevision, factBox }

SLIDE COUNT: 8–15. Every slide MUST be about the student topic — no generic unrelated slides.
If the topic is मान्सून, cover: अर्थ, निर्मिती, प्रकार, नैऋत्य मान्सून, अरबी समुद्र शाखा,
बंगालच्या उपसागराची शाखा, परतीचा मान्सून, पर्जन्य वितरण, महाराष्ट्रावरील परिणाम, MPSC points.
Do not copy those titles for a different topic.

NARRATION: 5–8 minutes spoken (4–6 teaching sentences per slide).
MCQs: include 8–12 high-quality items in this JSON (easy/medium/hard, statement, assertion-reason, match).
  Each: question, options[4], correctIndex, correctAnswer, explanation, difficulty, kind.
PYQs: include 6–10 previous-year-STYLE practice questions.
  Do NOT claim a question is an official PYQ unless the exact exam and year are known.
  If unsure, set exam to "PYQ-based practice question" and leave year empty.

BOARD STYLE:
- "bullets": 2–4 SHORT board points (≤ ~12 Marathi words).
- NEVER put full narration paragraphs on the board.
- Teaching depth lives in "narration".
- "keywords": 3–6 high-yield terms on every slide.
- Use THIS subject's visual templates (map / flowchart / timeline / table / graph).

EVERY slide must include:
title, bullets, narration, keywords, visualType + payload, sceneType, transition "fade".

$subjectNameRule

Memory tricks: only where genuinely helpful. Do not force a trick for every fact.

SPOKEN NARRATION / teaching_script:
- Continuous natural Marathi. No English sentences.
- Never put +, -, /, %, =, *, bullets, markdown, or page numbers in narration.
- Expand abbreviations: GDP → जी डी पी, MPSC → एम पी एस सी, RBI → आर बी आय,
  GST → जी एस टी. Write "टक्के" not %.
- Do NOT read board bullets aloud. Teach in full sentences.

${subject == null ? '' : _subjectBrief(subject)}
''';
}

String _subjectBrief(MpscTeachingSubject subject) {
  switch (subject) {
    case MpscTeachingSubject.polity:
      return '''
POLITY TEACHER — VOICE AND METHOD:
- Constitutional Marathi. Name articles / कलमे when standard and well-known.
- Use amendments, committees, and constitutional examples.
- Prefer flowcharts for process (bill, amendment, emergency, election).
- Prefer comparison tables (Lok Sabha vs Rajya Sabha, articles vs schedules).
- MPSC memory tricks. PYQ-oriented traps.
- Do not invent article numbers. If unsure, teach the principle without a number.
- Signature slides: flowchart + comparison table + PYQ trap.
- Visual templates: flowcharts, article tables, comparison charts.
''';
    case MpscTeachingSubject.history:
      return '''
HISTORY TEACHER — VOICE AND METHOD:
- Storytelling. Chronological. "आधी काय झाले, नंतर काय झाले, त्याचे परिणाम काय".
- Timeline, causes, events, consequences, personalities, exam chronology.
- Prefer timeline visuals. Causes and consequences on separate beats.
- Memory techniques: short Marathi mnemonics, year-hooks, character links.
- Do not dump dates; weave 2–4 key years into the story.
- Signature slides: timeline + causes/effects table + memory trick.
- Visual templates: timelines, event cards, dynasty charts.
''';
    case MpscTeachingSubject.geography:
      return '''
GEOGRAPHY TEACHER — VOICE AND METHOD:
- Location first. Always place the topic on a map (India / Maharashtra).
- Maps, diagrams, river systems, climate, Maharashtra focus, physical geography.
- Visual teaching: mapRegions, flowchart for river course, graph for rainfall/climate.
- Explain "कुठे, का, कसे" — where, why there, how it looks in the exam.
- Signature slides: map + river/climate diagram + location comparison.
- Visual templates: map-based slides, river diagrams, climate charts, Maharashtra maps.
''';
    case MpscTeachingSubject.economics:
      return '''
ECONOMICS TEACHER — VOICE AND METHOD:
- Simple Marathi daily-life examples before theory (बाजार, भाजीपाल्याच्या किमती, पगार).
- Current examples: budget, inflation, GDP, banking.
- Charts and graphs for GDP, inflation, budget, repo.
- Teach RBI, inflation, GDP, budget in spoken Marathi (आर बी आय, चलनवाढ, जी डी पी, अर्थसंकल्प).
- Never say percent signs; say टक्के.
- Signature slides: simple example + bar/line graph + RBI/budget flowchart.
- Visual templates: graphs, budget tables, RBI flowcharts.
''';
    case MpscTeachingSubject.science:
      return '''
SCIENCE TEACHER — VOICE AND METHOD:
- Concepts first, then a simple diagram, then real-life / exam application.
- Exam-oriented facts. Short Marathi. No lab jargon unless needed.
- Prefer flowchart or diagram visuals for processes (photosynthesis, circuit, atom).
- Signature slides: concept definition + diagram + application fact.
- Visual templates: concept diagrams and process flowcharts.
''';
    case MpscTeachingSubject.environment:
      return '''
ENVIRONMENT TEACHER — VOICE AND METHOD:
- Ecosystem / food chain / process diagrams.
- Species–environment relationships and conservation concepts.
- Pollution, biodiversity, climate — Maharashtra and India examples when relevant.
- Signature slides: process diagram + conservation table + exam trap.
- Visual templates: flowcharts, food-chain diagrams, comparison tables.
''';
  }
}

/// Compact JSON contract used by Topic → Gemini → Display (completes reliably).
String compactLessonSystemPrompt(MpscTeachingSubject? subject) {
  final nameEn = subject?.nameEn ?? 'MPSC';
  final persona = subject == null
      ? 'Detect the subject from the topic, then teach in that classroom style. '
          'Never default to Parliament/संसद unless that is the topic.'
      : 'You are the $nameEn Teacher. Teach only as a $nameEn classroom teacher.';
  final subjectNameRule = subject == null
      ? 'subject MUST be the English subject name; subjectName like "मराठी · English Teacher".'
      : 'subject MUST be "${subject.nameEn}". subjectName MUST be "${subject.displayName}".';
  return '''
You are an MPSC Combined Group B and C Marathi teacher.
$persona
Teach the EXACT student topic. Never substitute संसद / Parliament unless that is the topic.
Never invent citations, article numbers, or years. If unsure, teach the principle without a fake source.
Reply with ONE JSON object only (no markdown).
$subjectNameRule
All student-facing text in natural teacher-style Marathi.
${subject == null ? '' : _subjectBrief(subject)}
''';
}

String subjectUserPrompt({
  required String topic,
  MpscTeachingSubject? subject,
}) {
  final detected = subject == null
      ? 'Auto-detect the subject from the topic. Do not assume Polity/Parliament.'
      : 'Detected subject: ${subject.displayName}. Teach only in that style.';
  return '''
SUBJECT-WISE AI TEACHER
$detected
Student topic: $topic
Target exam: MPSC Combined Group B and C

Generate a complete Marathi classroom lesson JSON for THIS topic only.
- 8–15 slides that actually teach "$topic"
- 5–8 minute continuous spoken Marathi teaching_script
- synchronized slide narrations
- subject-specific visuals
- exam notes: introduction, definition, main concepts, important facts, MPSC points, examples, common mistakes, quick revision
- 8–12 MCQs now (more will be requested separately)
- 6–10 PYQ-based practice questions (label exam "PYQ-based practice question" unless year+paper are known)
- useful Marathi memory tricks only where helpful
- No generic teacher script
- No PDF. Teach the topic directly.

${subject == null ? '' : _subjectBrief(subject)}
''';
}

/// Compact chapter JSON used for Topic → Gemini → Display (no video/TTS).
String chapterUserPrompt({
  required String topic,
  MpscTeachingSubject? subject,
}) {
  final subjectLine = subject == null
      ? 'Detect the MPSC subject automatically. '
          'मान्सून / गंगा नदी → Geography; '
          'मूलभूत अधिकार → Polity; '
          '1857 चा उठाव → History; '
          'महागाई → Economics. '
          'Put the English subject name in "subject".'
      : 'Subject MUST be ${subject.nameEn}. subjectName="${subject.displayName}".';
  return '''
Teach this EXACT MPSC Combined Group B & C topic in simple teacher-style Marathi: "$topic"
$subjectLine
Never teach संसद / Parliament / राज्यव्यवस्था unless that is the student topic.
Do not invent citations or unsupported facts.

Return ONLY one JSON object (no markdown) with these keys:
{
  "title": "Marathi title",
  "subject": "Polity",
  "subjectName": "राज्यव्यवस्था · Polity Teacher",
  "topic": "$topic",
  "introduction": "3-5 Marathi sentences",
  "concepts": ["...","...","..."],
  "important_facts": ["...","...","...","..."],
  "mpsc_points": ["...","...","..."],
  "examples": ["...","..."],
  "exam_traps": ["...","..."],
  "teaching_script": "continuous natural Marathi lecture",
  "mcq_seed_topics": ["...","...","..."],
  "memoryTricks": ["...","..."],
  "revision": ["...","...","...","...","..."],
  "notes": ["...","...","...","...","...","..."],
  "mcqs": [{"question":"...","options":["अ","ब","क","ड"],"correctIndex":0,"explanation":"..."}],
  "pyqs": [{"question":"...","answer":"...","analysis":"...","exam":"PYQ-based practice question"}],
  "slides": [{"title":"...","bullets":["...","..."],"narration":"...","keywords":["..."],"sceneType":"introduction","visualType":"bullets"}]
}
Keep JSON complete (do not truncate):
- exactly 5 slides (2-sentence narration each)
- exactly 6 MCQs
- exactly 4 PYQ-style questions
- 3 concepts, 4 important_facts, 3 mpsc_points, 2 examples, 2 exam_traps
- 2 memoryTricks, 5 revision points, 5 short notes
All student-facing text in simple Marathi. JSON only. Do not add extra keys.
''';
}

List<String> dynamicSyllabusPointsFor(
  MpscTeachingSubject subject,
  String topic,
) {
  switch (subject) {
    case MpscTeachingSubject.polity:
      return [
        '$topic — घटनात्मक अर्थ',
        '$topic — संबंधित कलमे / तरतुदी',
        '$topic — रचना व प्रक्रिया (flowchart)',
        '$topic — तुलना: संबंधित संस्था / कलमे',
        '$topic — अधिकार, मर्यादा, अपवाद',
        '$topic — PYQ कोन व सापळे',
        '$topic — महत्त्वाची तथ्ये',
        '$topic — जलद पुनरावृत्ती कीवर्ड',
      ];
    case MpscTeachingSubject.history:
      return [
        '$topic — कथा कशी सुरू झाली',
        '$topic — कालरेषा',
        '$topic — मुख्य कारणे',
        '$topic — महत्त्वाचे प्रसंग',
        '$topic — परिणाम व बदल',
        '$topic — स्मरण युक्ती',
        '$topic — परीक्षा कोन',
        '$topic — जलद पुनरावृत्ती',
      ];
    case MpscTeachingSubject.geography:
      return [
        '$topic — नकाशावर स्थान',
        '$topic — रचना / आकृती',
        '$topic — नदी / हवामान / मृदा संबंध',
        '$topic — महाराष्ट्र व भारत संदर्भ',
        '$topic — तुलना: प्रदेश / घाट / खोरे',
        '$topic — दृश्य तथ्ये',
        '$topic — परीक्षा कोन',
        '$topic — जलद पुनरावृत्ती',
      ];
    case MpscTeachingSubject.economics:
      return [
        '$topic — सोपी व्याख्या व रोजचे उदाहरण',
        '$topic — जी डी पी / चलनवाढ / अर्थसंकल्प संबंध',
        '$topic — आर बी आय व धोरण',
        '$topic — आलेख व आकडेवारी कशी वाचावी',
        '$topic — सरकारी योजना / बजेट कोन',
        '$topic — सामान्य चुका',
        '$topic — परीक्षा तथ्ये',
        '$topic — जलद पुनरावृत्ती',
      ];
    case MpscTeachingSubject.science:
      return [
        '$topic — संकल्पना',
        '$topic — आकृती / प्रक्रिया',
        '$topic — दैनंदिन उपयोग',
        '$topic — नियम / सूत्र सोप्या भाषेत',
        '$topic — परीक्षा तथ्ये',
        '$topic — सामान्य चुका',
        '$topic — स्मरण युक्ती',
        '$topic — जलद पुनरावृत्ती',
      ];
    case MpscTeachingSubject.environment:
      return [
        '$topic — परिसंस्था / व्याख्या',
        '$topic — प्रक्रिया आकृती',
        '$topic — घटक व संबंध',
        '$topic — संवर्धन',
        '$topic — भारत / महाराष्ट्र उदाहरण',
        '$topic — परीक्षा तथ्ये',
        '$topic — सामान्य चुका',
        '$topic — जलद पुनरावृत्ती',
      ];
  }
}
