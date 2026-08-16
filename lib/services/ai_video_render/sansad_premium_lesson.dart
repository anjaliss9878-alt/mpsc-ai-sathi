import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subtitle_timing.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/render_models.dart';

/// Premium ~2-minute animated teaching video job for topic **संसद**.
///
/// Faculty-style Marathi narration (not OCR reading). Each scene ends with
/// one MCQ + answer explanation before continuing.
AiVideoRenderJob buildSansadPremiumVideoJob() {
  RenderNarrationBeat beat({
    required String text,
    required double seconds,
    required double board,
    List<String> keywords = const [],
    bool mcq = false,
    bool explain = false,
    String pointer = '',
  }) {
    // Scale to a tight ~2:00 premium cut (faculty pace, not rushed).
    final scaled = (seconds * 0.74).clamp(2.5, 12.0);
    return RenderNarrationBeat(
      speakText: text,
      duration: Duration(milliseconds: (scaled * 1000).round()),
      boardProgress: board,
      keywords: keywords,
      subtitleCues: buildSubtitleTimingFromText(text),
      isMcq: mcq,
      isMcqExplain: explain,
      pointerLabel: pointer,
    );
  }

  return AiVideoRenderJob(
    topicName: 'संसद',
    subjectName: 'भारतीय राज्यव्यवस्था',
    fps: 10,
    targetWidth: 1280,
    targetHeight: 720,
    scenes: [
      // Scene 1 — Greeting / why MPSC (~18s)
      RenderScene(
        id: 's1',
        title: 'संसद — ओळख',
        visualType: SlideVisualType.whiteboard,
        handwriting: const [
          'संसद = राष्ट्रपती + लोकसभा + राज्यसभा',
          'MPSC: रचना · अधिकार · फरक',
        ],
        bullets: const [
          'अभिवादन व विषय',
          'MPSC मध्ये वजन',
          'आज काय शिकणार',
        ],
        beats: [
          beat(
            text:
                'नमस्कार विद्यार्थी मित्रांनो. आज आपण संसद हा महत्त्वाचा घटक सोप्या मराठीत समजून घेणार आहोत.',
            seconds: 7,
            board: 0.35,
            keywords: const ['संसद'],
            pointer: 'संसद',
          ),
          beat(
            text:
                'MPSC Combine मध्ये संसदेची रचना, दोन्ही सभागृहे आणि कायदा कसा होतो हे वारंवार विचारले जाते. मी बोर्ड वाचणार नाही — संकल्पना समजावेन.',
            seconds: 8,
            board: 0.75,
            keywords: const ['MPSC', 'सभागृहे'],
          ),
          beat(
            text: 'स्वतःला विचारा — संसदेत किती भाग आहेत? उत्तर मनात ठरवा.',
            seconds: 4,
            board: 1,
            mcq: true,
            keywords: const ['संसद'],
          ),
          beat(
            text:
                'उत्तर — तीन भाग: राष्ट्रपती, लोकसभा आणि राज्यसभा. हे सूत्र परीक्षापर्यंत बांधून ठेवा.',
            seconds: 5,
            board: 1,
            explain: true,
            keywords: const ['राष्ट्रपती', 'लोकसभा', 'राज्यसभा'],
          ),
        ],
        mcq: const GeneratedMcq(
          question: 'भारतीय संसदेत किती भाग आहेत?',
          options: ['दोन', 'तीन', 'चार', 'एक'],
          correctIndex: 1,
          explanation: 'संसद = राष्ट्रपती + लोकसभा + राज्यसभा.',
        ),
      ),

      // Scene 2 — Basic concept (~16s)
      RenderScene(
        id: 's2',
        title: 'मूलभूत संकल्पना',
        visualType: SlideVisualType.mindmap,
        bullets: const ['राष्ट्रपती', 'लोकसभा', 'राज्यसभा'],
        handwriting: const ['केंद्रिय विधिमंडळ', 'द्विसदनीय रचना'],
        beats: [
          beat(
            text:
                'सोप्या भाषेत सांगायचे तर संसद म्हणजे भारताचे केंद्रिय विधिमंडळ — जिथे कायदे तयार होतात आणि सरकार जबाबदार राहते.',
            seconds: 8,
            board: 0.55,
            keywords: const ['विधिमंडळ', 'कायदे'],
          ),
          beat(
            text:
                'आपली रचना द्विसदनीय आहे — लोकसभा आणि राज्यसभा — पण राष्ट्रपती हा संसदेचा अविभाज्य भाग आहे.',
            seconds: 7,
            board: 1,
            keywords: const ['द्विसदनीय', 'राष्ट्रपती'],
          ),
          beat(
            text: 'MCQ — द्विसदनीय म्हणजे काय?',
            seconds: 3.5,
            board: 1,
            mcq: true,
          ),
          beat(
            text:
                'उत्तर — दोन सभागृहे. लोकसभा आणि राज्यसभा. राष्ट्रपती वेगळा घटक आहे, पण संसदेचा भाग आहे.',
            seconds: 5,
            board: 1,
            explain: true,
            keywords: const ['दोन सभागृहे'],
          ),
        ],
        mcq: const GeneratedMcq(
          question: 'द्विसदनीय रचना म्हणजे?',
          options: [
            'एक सभागृह',
            'दोन सभागृहे',
            'तीन सभागृहे',
            'फक्त राष्ट्रपती',
          ],
          correctIndex: 1,
          explanation: 'द्विसदनीय = लोकसभा + राज्यसभा.',
        ),
      ),

      // Scene 3 — Detail Lok Sabha / Rajya Sabha (~18s)
      RenderScene(
        id: 's3',
        title: 'लोकसभा व राज्यसभा',
        visualType: SlideVisualType.table,
        tableHeaders: const ['सभागृह', 'निवड', 'स्वरूप'],
        tableRows: const [
          ['लोकसभा', 'थेट जनता', 'तात्पुरते'],
          ['राज्यसभा', 'अप्रत्यक्ष', 'स्थायी'],
        ],
        bullets: const ['लोकसभा — थेट', 'राज्यसभा — स्थायी'],
        beats: [
          beat(
            text:
                'लोकसभेचे सदस्य थेट जनतेद्वारे निवडले जातात. म्हणून तिला जनतेचे सभागृह म्हणतात — सरकारला इथेच विश्वास दाखवावा लागतो.',
            seconds: 8,
            board: 0.5,
            keywords: const ['लोकसभा', 'थेट'],
            pointer: 'लोकसभा',
          ),
          beat(
            text:
                'राज्यसभा स्थायी सभागृह आहे. सर्व सदस्य एकदम निवृत्त होत नाहीत — ही रचना संघराज्याचे प्रतिनिधित्व मजबूत करते.',
            seconds: 8,
            board: 1,
            keywords: const ['राज्यसभा', 'स्थायी'],
            pointer: 'राज्यसभा',
          ),
          beat(
            text: 'MCQ — कोणते सभागृह स्थायी मानले जाते?',
            seconds: 3.5,
            board: 1,
            mcq: true,
          ),
          beat(
            text: 'उत्तर — राज्यसभा. लोकसभा विसर्जित होऊ शकते; राज्यसभा सतत चालू राहते.',
            seconds: 5,
            board: 1,
            explain: true,
            keywords: const ['राज्यसभा'],
          ),
        ],
        mcq: const GeneratedMcq(
          question: 'स्थायी सभागृह कोणते?',
          options: ['लोकसभा', 'राज्यसभा', 'विधानसभा', 'ग्रामसभा'],
          correctIndex: 1,
          explanation: 'राज्यसभा स्थायी सभागृह आहे.',
        ),
      ),

      // Scene 4 — Example bill (~14s)
      RenderScene(
        id: 's4',
        title: 'उदाहरण — विधेयक',
        visualType: SlideVisualType.flowchart,
        flowchart: const [
          FlowNode(id: '1', label: 'विधेयक मांडणे', nextIds: ['2']),
          FlowNode(id: '2', label: 'दोन्ही सभागृहे', nextIds: ['3']),
          FlowNode(id: '3', label: 'राष्ट्रपतींची संमती', nextIds: []),
        ],
        bullets: const ['मांडणे', 'मंजुरी', 'कायदा'],
        beats: [
          beat(
            text:
                'उदाहरण पाहू. एखादे सामान्य विधेयक कायदा होण्यासाठी दोन्ही सभागृहांची मान्यता लागते, आणि शेवटी राष्ट्रपतींची संमती.',
            seconds: 8,
            board: 0.7,
            keywords: const ['विधेयक', 'संमती'],
          ),
          beat(
            text:
                'अर्थसंकल्पासारखे मनी बिल मात्र प्रथम लोकसभेतच मांडले जाते — हा फरक परीक्षेत आवडीचा प्रश्न आहे.',
            seconds: 7,
            board: 1,
            keywords: const ['मनी बिल', 'लोकसभा'],
          ),
          beat(
            text: 'MCQ — मनी बिल प्रथम कुठे मांडले जाते?',
            seconds: 3.5,
            board: 1,
            mcq: true,
          ),
          beat(
            text: 'उत्तर — लोकसभेत. राज्यसभेत प्रथम मांडता येत नाही.',
            seconds: 4,
            board: 1,
            explain: true,
            keywords: const ['लोकसभा'],
          ),
        ],
        mcq: const GeneratedMcq(
          question: 'मनी बिल प्रथम कुठे मांडले जाते?',
          options: ['राज्यसभा', 'लोकसभा', 'सर्वोच्च न्यायालय', 'केंद्र मंत्रिमंडळ'],
          correctIndex: 1,
          explanation: 'मनी बिल प्रथम लोकसभेत मांडले जाते.',
        ),
      ),

      // Scene 5 — Diagram / process (~12s)
      RenderScene(
        id: 's5',
        title: 'कायदा होण्याचा प्रवाह',
        visualType: SlideVisualType.flowchart,
        flowchart: const [
          FlowNode(id: 'a', label: 'सभागृह A', nextIds: ['b']),
          FlowNode(id: 'b', label: 'सभागृह B', nextIds: ['c']),
          FlowNode(id: 'c', label: 'राष्ट्रपती', nextIds: []),
        ],
        handwriting: const ['प्रक्रिया समजून घ्या', 'फक्त पाठांतर नाही'],
        beats: [
          beat(
            text:
                'आकृती पहा — विधेयक एका सभागृहातून दुसऱ्याकडे जाते. मतभेद झाले तर संयुक्त बैठकही होऊ शकते.',
            seconds: 8,
            board: 0.85,
            keywords: const ['संयुक्त बैठक'],
          ),
          beat(
            text: 'MCQ — मतभेद मिटवण्यासाठी काय होऊ शकते?',
            seconds: 3.5,
            board: 1,
            mcq: true,
          ),
          beat(
            text: 'उत्तर — संयुक्त बैठक. हे लक्षात ठेवा — प्रक्रिया समजणे म्हणजे गुण मिळवणे.',
            seconds: 4.5,
            board: 1,
            explain: true,
            keywords: const ['संयुक्त बैठक'],
          ),
        ],
        mcq: const GeneratedMcq(
          question: 'दोन्ही सभागृहांमध्ये मतभेद झाल्यास?',
          options: [
            'निवडणूक रद्द',
            'संयुक्त बैठक',
            'केवळ राष्ट्रपती निर्णय',
            'काहीच होत नाही',
          ],
          correctIndex: 1,
          explanation: 'मतभेदावर संयुक्त बैठक होऊ शकते.',
        ),
      ),

      // Scene 6 — PYQ (~14s)
      RenderScene(
        id: 's6',
        title: 'PYQ दृष्टी',
        visualType: SlideVisualType.timeline,
        timeline: const [
          TimelineEvent(year: 'रचना', label: '३ भाग'),
          TimelineEvent(year: 'फरक', label: 'स्थायी / तात्पुरते'),
          TimelineEvent(year: 'मनी बिल', label: 'लोकसभा प्रथम'),
        ],
        bullets: const ['रचना विचारतात', 'फरक विचारतात', 'प्रक्रिया विचारतात'],
        beats: [
          beat(
            text:
                'मागील प्रश्नपत्रिकांमध्ये संसदेची व्याख्या, स्थायी सभागृह आणि मनी बिल हे त्रिकूट वारंवार येते.',
            seconds: 8,
            board: 0.7,
            keywords: const ['PYQ', 'मनी बिल'],
          ),
          beat(
            text:
                'सावधान — विद्यार्थी राष्ट्रपतीला संसदेबाहेर समजतात. तो चूक आहे. राष्ट्रपती संसदेचा भाग आहे.',
            seconds: 7,
            board: 1,
            keywords: const ['राष्ट्रपती'],
          ),
          beat(
            text: 'MCQ — राष्ट्रपती संसदेचा भाग आहे का?',
            seconds: 3.5,
            board: 1,
            mcq: true,
          ),
          beat(
            text: 'उत्तर — होय. संसद म्हणजे राष्ट्रपती अधिक दोन्ही सभागृहे.',
            seconds: 4,
            board: 1,
            explain: true,
            keywords: const ['होय'],
          ),
        ],
        mcq: const GeneratedMcq(
          question: 'राष्ट्रपती संसदेचा भाग आहे का?',
          options: ['नाही', 'होय', 'फक्त युद्धकाळात', 'फक्त अर्थसंकल्पावेळी'],
          correctIndex: 1,
          explanation: 'राष्ट्रपती संसदेचा अविभाज्य भाग आहे.',
        ),
      ),

      // Scene 7 — 3 MCQ pack cue (~10s) — one more check then revision
      RenderScene(
        id: 's7',
        title: 'सराव MCQ',
        visualType: SlideVisualType.icons,
        bullets: const ['रचना', 'स्थायी सभागृह', 'मनी बिल'],
        beats: [
          beat(
            text:
                'आता एकत्र सराव — तीन कल्पना पक्क्या: रचना, स्थायी सभागृह, आणि मनी बिल.',
            seconds: 6,
            board: 0.6,
            keywords: const ['सराव'],
          ),
          beat(
            text: 'MCQ — संसदेचे योग्य सूत्र कोणते?',
            seconds: 3.5,
            board: 1,
            mcq: true,
          ),
          beat(
            text:
                'उत्तर — राष्ट्रपती अधिक लोकसभा अधिक राज्यसभा. हे सूत्रच दोन मिनिटांच्या धड्याचा आत्मा आहे.',
            seconds: 5,
            board: 1,
            explain: true,
            keywords: const ['सूत्र'],
          ),
        ],
        mcq: const GeneratedMcq(
          question: 'संसदेचे योग्य सूत्र?',
          options: [
            'फक्त लोकसभा',
            'राष्ट्रपती + लोकसभा + राज्यसभा',
            'फक्त राज्यसभा',
            'विधानसभा + लोकसभा',
          ],
          correctIndex: 1,
          explanation: 'संसद = राष्ट्रपती + लोकसभा + राज्यसभा.',
        ),
      ),

      // Scene 8 — Revision (~12s)
      RenderScene(
        id: 's8',
        title: 'पुनरावलोकन',
        visualType: SlideVisualType.whiteboard,
        handwriting: const [
          'संसद = ३ भाग',
          'राज्यसभा = स्थायी',
          'मनी बिल = लोकसभा प्रथम',
        ],
        bullets: const ['३ भाग', 'स्थायी = राज्यसभा', 'मनी बिल = लोकसभा'],
        beats: [
          beat(
            text:
                'पुनरावलोकन — संसद म्हणजे तीन भाग. राज्यसभा स्थायी. मनी बिल प्रथम लोकसभेत. ही तीन वाक्ये स्वतःच्या शब्दांत सांगा.',
            seconds: 9,
            board: 1,
            keywords: const ['पुनरावलोकन', 'तीन'],
          ),
          beat(
            text:
                'धडा येथे पूर्ण. आता सरावाने समज पक्की करा — यश तुमचेच!',
            seconds: 5,
            board: 1,
            keywords: const ['यश'],
          ),
        ],
      ),
    ],
  );
}

/// Also expose as [GeneratedLesson] for classroom cache compatibility.
GeneratedLesson buildSansadGeneratedLesson() {
  final job = buildSansadPremiumVideoJob();
  return GeneratedLesson(
    question: 'संसद',
    topicName: 'संसद',
    subjectName: 'भारतीय राज्यव्यवस्था',
    createdAt: DateTime.now(),
    script: [
      for (final s in job.scenes)
        s.beats.map((b) => b.speakText).join(' '),
    ],
    slides: [
      for (final s in job.scenes)
        GeneratedSlide(
          title: s.title,
          bullets: s.bullets,
          handwriting: s.handwriting,
          flowchart: s.flowchart,
          timeline: s.timeline,
          tableHeaders: s.tableHeaders,
          tableRows: s.tableRows,
          visualType: s.visualType,
          keywords: s.beats.expand((b) => b.keywords).toSet().toList(),
          narration: s.beats
              .where((b) => !b.isMcq && !b.isMcqExplain)
              .map((b) => b.speakText)
              .join(' '),
          sectionQuestion: s.mcq,
          sceneType: _sceneTypeFor(s.id),
        ),
    ],
    summary:
        'संसद = राष्ट्रपती + लोकसभा + राज्यसभा. राज्यसभा स्थायी. मनी बिल प्रथम लोकसभेत.',
    mcqs: [
      for (final s in job.scenes)
        if (s.mcq != null) s.mcq!,
    ],
    notes: const [
      'संसद = राष्ट्रपती + लोकसभा + राज्यसभा',
      'द्विसदनीय = दोन सभागृहे',
      'राज्यसभा स्थायी सभागृह',
      'मनी बिल प्रथम लोकसभेत',
      'मतभेद → संयुक्त बैठक',
    ],
    premium: const LessonPremiumExtras(
      pyqInsight: [
        'रचना / स्थायी सभागृह / मनी बिल त्रिकूट वारंवार येते.',
      ],
      examTips: ['राष्ट्रपती संसदेचा भाग आहे — हे चुकवू नका.'],
      commonMistakes: ['राष्ट्रपतीला संसदेबाहेर समजणे.'],
      memoryTricks: ['३ भाग — राष्ट्रपती, लोकसभा, राज्यसभा.'],
      importantFacts: ['राज्यसभा स्थायी', 'मनी बिल = लोकसभा प्रथम'],
      onePageSummary:
          'भारतीय संसद राष्ट्रपती, लोकसभा व राज्यसभा यांनी बनते. लोकसभा थेट निवड; राज्यसभा स्थायी. मनी बिल प्रथम लोकसभेत.',
      quickRevision:
          'संसद=३ · राज्यसभा=स्थायी · मनी बिल=लोकसभा प्रथम · मतभेद=संयुक्त बैठक',
    ),
  );
}

LessonSceneType _sceneTypeFor(String id) {
  switch (id) {
    case 's1':
      return LessonSceneType.title;
    case 's2':
      return LessonSceneType.introduction;
    case 's3':
      return LessonSceneType.mainExplanation;
    case 's4':
      return LessonSceneType.examples;
    case 's5':
      return LessonSceneType.diagram;
    case 's6':
      return LessonSceneType.importantPoints;
    case 's7':
      return LessonSceneType.quiz;
    case 's8':
      return LessonSceneType.summary;
    default:
      return LessonSceneType.mainExplanation;
  }
}
