import 'package:mpsc_combine_ai/models/pdf_content_block.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/chapter_lesson_loader.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lecture_lesson_sanitizer.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/speakable_marathi.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/lesson_render_job_builder.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Builds a full classroom lesson by structuring verified notes only.
///
/// Used when Gemini is unavailable, and as a grounding scaffold. It never
/// invents statutes/dates — every teaching bullet comes from the notes text.
/// When PDF structured blocks exist, slides mirror those types (tables,
/// timelines, flowcharts, charts) instead of flattening to paragraphs.
class VerifiedNotesLessonComposer {
  const VerifiedNotesLessonComposer();

  /// Dynamic AI lesson when Firestore notes are missing (any topic).
  ///
  /// Builds a complete 8–15 slide classroom lecture from the topic title so the
  /// student pipeline never blocks. Labeled [LessonSourceKind.aiGenerated].
  GeneratedLesson composeDynamicTopic({
    required String topic,
    String subject = 'MPSC Combine',
    MpscTeachingSubject? teachingSubject,
  }) {
    final trimmed = topic.trim().isEmpty ? 'MPSC विषय' : topic.trim();
    final style = teachingSubject ??
        detectMpscTeachingSubject(trimmed, hint: subject);
    final points = dynamicSyllabusPointsFor(style, trimmed);
    return sanitizeLectureLesson(
      _composeFromPoints(
        topic: trimmed,
        subject: style.displayName,
        points: points,
        chapterId: '',
        subjectId: '',
        sourceKind: LessonSourceKind.aiGenerated,
      ),
    );
  }

  GeneratedLesson compose(ChapterLessonSource source) {
    final topic = source.chapter.title.trim().isEmpty
        ? 'MPSC विषय'
        : source.chapter.title.trim();
    final subject = source.subjectTitle.trim().isEmpty
        ? 'MPSC Combine'
        : source.subjectTitle.trim();

    final blocks = source.pdfStructuredBlocks.isNotEmpty
        ? source.pdfStructuredBlocks
        : (source.note?.pdfStructuredBlocks ?? const <PdfContentBlock>[]);
    if (blocks.isNotEmpty) {
      return sanitizeLectureLesson(
        _composeFromPdfBlocks(
          topic: topic,
          subject: subject,
          blocks: blocks,
          chapterId: source.chapter.id,
          subjectId: source.chapter.subjectId,
        ),
      );
    }

    final points = _extractPoints(source);
    if (points.isEmpty) {
      // Still never block — fall back to dynamic AI syllabus for this topic.
      return composeDynamicTopic(topic: topic, subject: subject);
    }
    return sanitizeLectureLesson(
      _composeFromPoints(
        topic: topic,
        subject: subject,
        points: points,
        chapterId: source.chapter.id,
        subjectId: source.chapter.subjectId,
        sourceKind: LessonSourceKind.verifiedNotes,
      ),
    );
  }

  GeneratedLesson _composeFromPdfBlocks({
    required String topic,
    required String subject,
    required List<PdfContentBlock> blocks,
    required String chapterId,
    required String subjectId,
  }) {
    final slides = <GeneratedSlide>[
      GeneratedSlide(
        title: 'आजचा विषय: $topic',
        bullets: [
          subject,
          'PDF Notes आधारित धडा',
          'MPSC Combine Group B/C',
        ],
        sceneType: LessonSceneType.title,
        visualType: SlideVisualType.icons,
        iconLabels: const ['PDF', 'विषय', 'परीक्षा'],
        keywords: [topic, 'PDF'],
        narration:
            'नमस्कार विद्यार्थी मित्रांनो. आज आपण "$topic" हा विषय Topic PDF '
            'नोट्सवरून पूर्ण वर्गाच्या पद्धतीने शिकणार आहोत. '
            'टेबल, आकृत्या आणि मुद्दे जसे PDF मध्ये आहेत तसेच समजावून सांगणार आहोत.',
        bulletExpansions: [
          'विषय $subject अंतर्गत येतो.',
          'PDF ही प्राथमिक स्रोत आहे — रचना जशी आहे तशी ठेवली आहे.',
          'MPSC Combine पूर्व व मुख्य परीक्षेसाठी उपयुक्त.',
        ],
      ),
    ];

    final headingTitles = blocks
        .where((b) => b.type == PdfBlockType.heading)
        .map((b) => b.title.trim().isNotEmpty ? b.title.trim() : b.text.trim())
        .where((t) => t.isNotEmpty)
        .take(6)
        .toList();
    slides.add(
      GeneratedSlide(
        title: 'आज काय शिकणार?',
        bullets: headingTitles.isEmpty
            ? blocks.take(4).map(_blockBoardTitle).toList()
            : headingTitles.take(4).toList(),
        sceneType: LessonSceneType.introduction,
        visualType: SlideVisualType.mindmap,
        mindMap: MindMapData(
          center: topic,
          branches: [
            for (final t in (headingTitles.isEmpty
                ? blocks.take(6).map(_blockBoardTitle)
                : headingTitles))
              MindMapBranch(label: _shortBoard(t), children: const []),
          ],
        ),
        keywords: const ['PDF', 'अभ्यासक्रम'],
        narration:
            'PDF मधील रचना पाहूया. प्रत्येक शीर्षक, तक्ता आणि आकृती क्रमाने शिकू.',
        bulletExpansions: [
          for (final b in (headingTitles.isEmpty
              ? blocks.take(4).map(_blockBoardTitle)
              : headingTitles.take(4)))
            'या भागात आपण "$b" शिकू.',
        ],
      ),
    );

    final teachBlocks = blocks
        .where((b) => b.type != PdfBlockType.heading || _blockHasBody(b))
        .take(14)
        .toList();
    for (var i = 0; i < teachBlocks.length; i++) {
      slides.add(_slideFromPdfBlock(teachBlocks[i], index: i));
    }

    final pointPool = blocks
        .expand(_blockPoints)
        .map((e) => e.trim())
        .where((e) => e.length > 4)
        .toList();
    if (pointPool.isEmpty) pointPool.add(topic);

    slides.add(
      GeneratedSlide(
        title: 'महत्त्वाची MPSC तथ्ये',
        bullets: pointPool.take(4).map(_shortBoard).toList(),
        sceneType: LessonSceneType.importantPoints,
        visualType: SlideVisualType.table,
        tableHeaders: const ['मुद्दा', 'स्रोत'],
        tableRows: [
          for (final p in pointPool.take(4)) [_shortBoard(p, max: 22), 'PDF'],
        ],
        keywords: const ['महत्त्वाची तथ्ये', 'PDF'],
        narration:
            'ही महत्त्वाची तथ्ये Topic PDF मधून घेतली आहेत. '
            '${pointPool.take(3).map(_teacherLine).join(' ')}',
        bulletExpansions: [
          for (final p in pointPool.take(4)) _teacherLine(p),
        ],
      ),
    );

    slides.add(
      GeneratedSlide(
        title: 'सराव MCQ संच',
        bullets: const ['प्रश्न वाचा', 'पर्याय तपासा', 'स्पष्टीकरण ऐका'],
        sceneType: LessonSceneType.quiz,
        visualType: SlideVisualType.icons,
        iconLabels: const ['MCQ', 'उत्तर', 'स्पष्टीकरण'],
        keywords: const ['सराव'],
        narration:
            'आता PDF वर आधारित थोडा सराव करूया. प्रश्न वाचा आणि स्पष्टीकरणाने संकल्पना पक्की करा.',
      ),
    );

    final revision = pointPool.take(8).map(_shortBoard).toList();
    slides.add(
      GeneratedSlide(
        title: 'संपूर्ण पुनरावृत्ती',
        bullets: revision,
        sceneType: LessonSceneType.summary,
        visualType: SlideVisualType.bullets,
        keywords: const ['पुनरावृत्ती', 'PDF'],
        narration:
            'थोडक्यात PDF मधील मुख्य मुद्दे: ${pointPool.take(6).map(_teacherLine).join(' ')}',
        bulletExpansions: [for (final b in revision) _teacherLine(b)],
      ),
    );

    while (slides.length < kMinEduSlides) {
      final b = teachBlocks.isEmpty
          ? null
          : teachBlocks[slides.length % teachBlocks.length];
      slides.insert(
        slides.length - 3,
        b == null
            ? _teachSlide(
                title: 'अधिक स्पष्टीकरण',
                point: pointPool[slides.length % pointPool.length],
                sceneType: LessonSceneType.mainExplanation,
                visualType: SlideVisualType.bullets,
                lead: 'PDF मधील मुद्द्याचे आणखी एक कोन पाहूया.',
              )
            : _slideFromPdfBlock(b, index: slides.length),
      );
    }
    while (slides.length > kMaxEduSlides) {
      slides.removeAt(3);
    }

    final mcqs = <GeneratedMcq>[
      for (var i = 0; i < pointPool.length && i < 5; i++)
        _mcqFromPoint(pointPool[i], index: i + 1),
    ];
    while (mcqs.length < 5) {
      mcqs.add(_mcqFromPoint(pointPool.first, index: mcqs.length + 1));
    }

    return GeneratedLesson(
      question: topic,
      topicName: topic,
      subjectName: subject,
      script: slides
          .map((s) => s.narration.trim().isNotEmpty ? s.narration : s.title)
          .toList(),
      slides: slides,
      summary:
          'PDF आधारित पुनरावृत्ती — $topic: ${pointPool.take(8).map(_shortBoard).join('; ')}.',
      mcqs: mcqs,
      notes: pointPool.take(12).map(_shortBoard).toList(),
      createdAt: DateTime.now(),
      chapterId: chapterId,
      subjectId: subjectId,
      sourceKind: LessonSourceKind.verifiedNotes,
      premium: LessonPremiumExtras(
        importantFacts: pointPool.take(6).map(_shortBoard).toList(),
        examTips: const [
          'PDF मधील तक्ते व आकृत्या जशाच्या तशा लक्षात ठेवा.',
        ],
        memoryTricks: const [
          'प्रत्येक PDF शीर्षकामागे एक छोटा "का" जोडा.',
        ],
        pyqInsight: const [
          'PDF तक्त्यांमधील फरक Prelims मध्ये वारंवार विचारले जातात.',
        ],
        commonMistakes: const [
          'PDF रचना सपाट परिच्छेदात रूपांतरित करणे.',
        ],
        onePageSummary: pointPool.take(5).map(_shortBoard).join(' · '),
        quickRevision: pointPool.take(10).map(_shortBoard).join('\n'),
      ),
    );
  }

  GeneratedSlide _slideFromPdfBlock(PdfContentBlock block, {required int index}) {
    final title = _blockBoardTitle(block);
    final isSectionClose = (index + 1) % 3 == 0;
    final sectionQ = isSectionClose
        ? _mcqFromPoint(
            block.bullets.isNotEmpty
                ? block.bullets.first
                : (block.text.isNotEmpty ? block.text : title),
            index: index + 1,
          )
        : null;

    switch (block.type) {
      case PdfBlockType.table:
        final headers = block.tableHeaders.isNotEmpty
            ? block.tableHeaders
            : const ['स्तंभ १', 'स्तंभ २'];
        final rows = block.tableRows.isNotEmpty
            ? block.tableRows
            : [
                for (final b in block.bullets.take(3)) [b, 'PDF'],
              ];
        return GeneratedSlide(
          title: title,
          bullets: [
            for (final h in headers.take(3)) _shortBoard(h, max: 16),
            if (headers.isEmpty) _shortBoard(title),
          ].take(4).toList(),
          sceneType: LessonSceneType.mainExplanation,
          visualType: SlideVisualType.table,
          tableHeaders: headers,
          tableRows: rows,
          keywords: _keywordsFrom(title),
          narration:
              'PDF मधील तक्ता पाहूया. ${_teacherLine(title)} '
              'तुलना स्पष्ट समजून घ्या — परीक्षेत फरक विचारले जातात.',
          bulletExpansions: [
            for (final h in headers.take(4)) _teacherLine(h),
          ],
          sectionQuestion: sectionQ,
        );
      case PdfBlockType.timeline:
        final events = block.timeline.isNotEmpty
            ? [
                for (final e in block.timeline)
                  TimelineEvent(
                    year: (e['year'] ?? '').trim().isEmpty
                        ? '—'
                        : (e['year'] ?? '').trim(),
                    label: (e['label'] ?? '').trim(),
                  ),
              ]
            : [
                for (final b in block.bullets.take(4))
                  TimelineEvent(year: 'मुख्य', label: _shortBoard(b, max: 28)),
              ];
        return GeneratedSlide(
          title: title,
          bullets: events.take(4).map((e) => _shortBoard(e.label)).toList(),
          sceneType: LessonSceneType.mainExplanation,
          visualType: SlideVisualType.timeline,
          timeline: events,
          keywords: _keywordsFrom(title),
          narration:
              'कालक्रम PDF प्रमाणे समजून घेऊया. ${_teacherLine(title)}',
          bulletExpansions: [
            for (final e in events.take(4)) _teacherLine(e.label),
          ],
          sectionQuestion: sectionQ,
        );
      case PdfBlockType.flowchart:
        final nodes = block.flowchart.isNotEmpty
            ? [
                for (final n in block.flowchart)
                  FlowNode(
                    id: (n['id'] ?? '').toString().isEmpty
                        ? 'n'
                        : (n['id'] ?? '').toString(),
                    label: (n['label'] ?? '').toString(),
                    nextIds: asStringList(n['nextIds']),
                  ),
              ]
            : [
                for (var i = 0; i < block.bullets.length && i < 5; i++)
                  FlowNode(
                    id: '${i + 1}',
                    label: _shortBoard(block.bullets[i], max: 18),
                    nextIds: i < block.bullets.length - 1 && i < 4
                        ? ['${i + 2}']
                        : const [],
                  ),
              ];
        return GeneratedSlide(
          title: title,
          bullets: nodes.take(4).map((n) => _shortBoard(n.label)).toList(),
          sceneType: LessonSceneType.mainExplanation,
          visualType: SlideVisualType.flowchart,
          flowchart: nodes,
          highlightType: SlideHighlightType.diagram,
          highlightLabel: title,
          keywords: _keywordsFrom(title),
          narration:
              'प्रक्रिया PDF मधील फ्लोचार्टप्रमाणे पाहूया. ${_teacherLine(title)}',
          bulletExpansions: [
            for (final n in nodes.take(4)) _teacherLine(n.label),
          ],
          sectionQuestion: sectionQ,
        );
      case PdfBlockType.chart:
        return GeneratedSlide(
          title: title,
          bullets: block.chartLabels.isNotEmpty
              ? block.chartLabels.take(4).map(_shortBoard).toList()
              : block.bullets.take(4).map(_shortBoard).toList(),
          sceneType: LessonSceneType.mainExplanation,
          visualType: SlideVisualType.graph,
          graph: GraphData(
            type: 'bar',
            labels: block.chartLabels.isNotEmpty
                ? block.chartLabels
                : block.bullets.take(4).toList(),
            values: block.chartValues.isNotEmpty
                ? block.chartValues
                : List.filled(
                    (block.chartLabels.isNotEmpty
                            ? block.chartLabels
                            : block.bullets.take(4))
                        .length,
                    1,
                  ),
          ),
          keywords: _keywordsFrom(title),
          narration:
              'PDF मधील तक्ता/चार्ट पाहूया. ${_teacherLine(title)}',
          sectionQuestion: sectionQ,
        );
      case PdfBlockType.diagram:
        return GeneratedSlide(
          title: title,
          bullets: block.bullets.isNotEmpty
              ? block.bullets.take(4).map(_shortBoard).toList()
              : [
                  _shortBoard(
                    block.caption.isNotEmpty ? block.caption : block.text,
                  ),
                ],
          sceneType: LessonSceneType.mainExplanation,
          visualType: SlideVisualType.mindmap,
          mindMap: MindMapData(
            center: _shortBoard(title, max: 18),
            branches: [
              for (final b in (block.bullets.isNotEmpty
                  ? block.bullets.take(5)
                  : [block.caption, block.text].where((e) => e.trim().isNotEmpty)))
                MindMapBranch(label: _shortBoard(b), children: const []),
            ],
          ),
          highlightType: SlideHighlightType.diagram,
          highlightLabel: block.caption.isNotEmpty ? block.caption : title,
          keywords: _keywordsFrom(title),
          narration:
              'आकृती PDF प्रमाणे समजून घेऊया. ${_teacherLine(title)}',
          sectionQuestion: sectionQ,
        );
      case PdfBlockType.bullets:
      case PdfBlockType.paragraph:
      case PdfBlockType.heading:
      case PdfBlockType.other:
        final points = _blockPoints(block).toList();
        return _teachSlide(
          title: title,
          point: points.isNotEmpty ? points.first : title,
          sceneType: LessonSceneType.mainExplanation,
          visualType: SlideVisualType.bullets,
          extraBoard: points.skip(1).take(2).map(_shortBoard).toList(),
          sectionQuestion: sectionQ,
          lead: 'PDF मधील हा भाग सविस्तर शिकूया.',
        );
    }
  }

  bool _blockHasBody(PdfContentBlock b) =>
      b.text.trim().isNotEmpty ||
      b.bullets.isNotEmpty ||
      b.tableRows.isNotEmpty ||
      b.timeline.isNotEmpty ||
      b.flowchart.isNotEmpty ||
      b.chartLabels.isNotEmpty;

  String _blockBoardTitle(PdfContentBlock b) {
    if (b.title.trim().isNotEmpty) return _shortBoard(b.title);
    if (b.text.trim().isNotEmpty) return _shortBoard(b.text);
    if (b.bullets.isNotEmpty) return _shortBoard(b.bullets.first);
    if (b.caption.trim().isNotEmpty) return _shortBoard(b.caption);
    return pdfBlockTypeToString(b.type);
  }

  Iterable<String> _blockPoints(PdfContentBlock b) sync* {
    if (b.title.trim().length > 4) yield b.title.trim();
    if (b.text.trim().length > 4) yield b.text.trim();
    yield* b.bullets.where((e) => e.trim().length > 4);
    for (final row in b.tableRows) {
      final joined = row.where((c) => c.trim().isNotEmpty).join(' — ');
      if (joined.length > 4) yield joined;
    }
    for (final e in b.timeline) {
      final label = (e['label'] ?? '').trim();
      if (label.length > 4) yield label;
    }
    for (final n in b.flowchart) {
      final label = (n['label'] ?? '').toString().trim();
      if (label.length > 4) yield label;
    }
  }

  GeneratedLesson _composeFromPoints({
    required String topic,
    required String subject,
    required List<String> points,
    required String chapterId,
    required String subjectId,
    required LessonSourceKind sourceKind,
  }) {

    final slides = <GeneratedSlide>[];
    slides.add(
      GeneratedSlide(
        title: 'आजचा विषय: $topic',
        bullets: [
          subject,
          'MPSC Combine Group B/C',
          'पूर्ण वर्गाचा धडा',
        ],
        sceneType: LessonSceneType.title,
        visualType: SlideVisualType.icons,
        iconLabels: const ['अभिवादन', 'विषय', 'परीक्षा'],
        keywords: [topic, 'MPSC'],
        narration:
            'नमस्कार विद्यार्थी मित्रांनो. आज आपण "$topic" हा विषय पूर्ण वर्गाच्या पद्धतीने शिकणार आहोत. '
            'हा धडा थोडक्या सारांशापुरता नाही — प्रत्येक महत्त्वाचा मुद्दा समजावून सांगणार आहोत. '
            'MPSC Combined Group B आणि C मध्ये हा घटक परीक्षेला उपयुक्त आहे.',
        bulletExpansions: [
          'विषय $subject अंतर्गत येतो.',
          'आपले लक्ष्य MPSC Combine पूर्व व मुख्य परीक्षा आहे.',
          'आज पूर्ण संकल्पना, उदाहरणे आणि सराव करूया.',
        ],
      ),
    );

    final syllabusBullets = points.take(4).map(_shortBoard).toList();
    slides.add(
      GeneratedSlide(
        title: 'आज काय शिकणार?',
        bullets: syllabusBullets.isEmpty
            ? ['व्याख्या', 'उपघटक', 'उदाहरणे', 'पुनरावृत्ती']
            : syllabusBullets,
        sceneType: LessonSceneType.introduction,
        visualType: SlideVisualType.mindmap,
        mindMap: MindMapData(
          center: topic,
          branches: [
            for (final p in points.take(6))
              MindMapBranch(label: _shortBoard(p), children: const []),
          ],
        ),
        keywords: const ['अभ्यासक्रम', 'नकाशा'],
        narration: sourceKind == LessonSourceKind.verifiedNotes
            ? 'चला आजच्या अभ्यासाचा नकाशा पाहूया. नोट्समधील सर्व मुख्य मुद्दे आपण क्रमाने शिकणार आहोत. '
                'प्रत्येक उपघटकाची व्याख्या, अर्थ आणि परीक्षा कोन समजून घेऊया. '
                'शेवटी महत्त्वाची तथ्ये, सराव प्रश्न आणि संपूर्ण पुनरावृत्ती असेल.'
            : 'चला आजच्या अभ्यासाचा नकाशा पाहूया. या विषयातील सर्व मुख्य उपघटक आपण क्रमाने शिकणार आहोत. '
                'प्रत्येक उपघटकाची व्याख्या, अर्थ आणि परीक्षा कोन समजून घेऊया. '
                'शेवटी महत्त्वाची तथ्ये, सराव प्रश्न आणि संपूर्ण पुनरावृत्ती असेल.',
        bulletExpansions: [
          for (final b in (syllabusBullets.isEmpty
              ? ['व्याख्या', 'उपघटक', 'उदाहरणे', 'पुनरावृत्ती']
              : syllabusBullets))
            'या भागात आपण "$b" शिकू.',
        ],
      ),
    );

    // Definition slide from first point.
    slides.add(
      _teachSlide(
        title: 'सोपी व्याख्या',
        point: points.first,
        sceneType: LessonSceneType.mainExplanation,
        visualType: SlideVisualType.whiteboard,
        extraBoard: ['समजावून घ्या', 'लक्षात ठेवा'],
        lead:
            'आधी सोपी व्याख्या समजून घेऊया. गुंतागुंत नंतर येईल, आधी मुळ अर्थ स्वच्छ करूया.',
      ),
    );

    // One slide per remaining teaching point (cap to keep 8–15 total).
    final bodyPoints = points.length == 1 ? points : points.skip(1).toList();
    final maxBody = 6; // leave room for examples/facts/quiz/summary within 8–15
    final teachPoints = bodyPoints.take(maxBody).toList();
    for (var i = 0; i < teachPoints.length; i++) {
      final point = teachPoints[i];
      final visual = _visualFor(point, i);
      final isSectionClose = (i + 1) % 3 == 0 || i == teachPoints.length - 1;
      slides.add(
        _teachSlide(
          title: 'उपघटक ${i + 1}',
          point: point,
          sceneType: i == teachPoints.length - 1 && teachPoints.length > 4
              ? LessonSceneType.mainExplanation
              : LessonSceneType.mainExplanation,
          visualType: visual,
          sectionQuestion: isSectionClose
              ? _mcqFromPoint(point, index: i + 1)
              : null,
          lead: 'आता पुढचा महत्त्वाचा मुद्दा सविस्तर शिकूया.',
        ),
      );
    }

    // Ensure minimum mainExplanation count by splitting if needed — already one per point.

    final examplePoint =
        points.length > 2 ? points[points.length ~/ 2] : points.first;
    slides.add(
      GeneratedSlide(
        title: 'उदाहरणाने समजून घेऊया',
        bullets: [
          _shortBoard(examplePoint),
          'परीक्षा शैलीत विचार',
          'चुकीचे गृहीतक टाळा',
        ],
        sceneType: LessonSceneType.examples,
        visualType: SlideVisualType.bullets,
        keywords: const ['उदाहरण', 'MPSC'],
        narration:
            'एक सोपे, परीक्षेला उपयुक्त उदाहरण पाहूया. ${_teacherLine(examplePoint)} '
            'असे मुद्दे Prelims मध्ये थेट किंवा वक्तव्य-कारण स्वरूपात विचारले जातात. '
            'म्हणून फक्त पाठांतर नको — अर्थ समजून घ्या.',
        bulletExpansions: [
          _teacherLine(examplePoint),
          'प्रश्न कसा विचारला जाईल हे मनात ठेवा.',
          'समान वाटणारे पर्याय गोंधळ करू शकतात — फरक ओळखा.',
        ],
        sectionQuestion: _mcqFromPoint(examplePoint, index: 90),
      ),
    );

    final factPoints = points.take(4).map(_shortBoard).toList();
    slides.add(
      GeneratedSlide(
        title: 'महत्त्वाची MPSC तथ्ये',
        bullets: factPoints,
        sceneType: LessonSceneType.importantPoints,
        visualType: SlideVisualType.table,
        tableHeaders: const ['मुद्दा', 'लक्षात ठेवा'],
        tableRows: [
          for (final p in points.take(4))
            [_shortBoard(p, max: 22), 'उच्च उत्पन्न'],
        ],
        keywords: const ['महत्त्वाची तथ्ये', 'PYQ'],
        narration:
            'ही महत्त्वाची तथ्ये परीक्षा दृष्टीने हाय-यील्ड आहेत. '
            '${points.take(3).map(_teacherLine).join(' ')} '
            'PYQ मध्ये असे मुद्दे वारंवार फिरतात — फरक आणि कलम/संज्ञा स्वच्छ लक्षात ठेवा.',
        bulletExpansions: [
          for (final p in factPoints) _teacherLine(p),
        ],
        explanation: 'स्मरण युक्ती: प्रत्येक तथ्यामागचे "का" एका वाक्यात जोडा.',
      ),
    );

    slides.add(
      GeneratedSlide(
        title: 'सराव MCQ संच',
        bullets: const ['प्रश्न वाचा', 'पर्याय तपासा', 'स्पष्टीकरण ऐका'],
        sceneType: LessonSceneType.quiz,
        visualType: SlideVisualType.icons,
        iconLabels: const ['MCQ', 'उत्तर', 'स्पष्टीकरण'],
        keywords: const ['सराव'],
        narration:
            'आता थोडा सराव करूया. प्रश्न वाचा, उत्तर मनात ठरवा, आणि मग स्पष्टीकरणाने संकल्पना पक्की करा. '
            'चुकीचे पर्याय का चुकीचे आहेत हे समजणेही शिकणे आहे.',
      ),
    );

    final revisionBullets = points.take(8).map(_shortBoard).toList();
    slides.add(
      GeneratedSlide(
        title: 'संपूर्ण पुनरावृत्ती',
        bullets: revisionBullets,
        sceneType: LessonSceneType.summary,
        visualType: SlideVisualType.bullets,
        keywords: const ['पुनरावृत्ती', 'सारांश'],
        narration:
            'थोडक्यात संपूर्ण धडा परत पाहूया. ${points.take(6).map(_teacherLine).join(' ')} '
            'उद्याच्या अभ्यासात हे मुद्दे पुन्हा एकदा लिहून बघा — मगच ते दीर्घकाळ लक्षात राहतील.',
        bulletExpansions: [
          for (final b in revisionBullets) _teacherLine(b),
        ],
      ),
    );

    // Pad to minimum 8 slides if the draft was thin.
    while (slides.length < kMinEduSlides) {
      final p = points[slides.length % points.length];
      slides.insert(
        slides.length - 3,
        _teachSlide(
          title: 'अधिक स्पष्टीकरण',
          point: p,
          sceneType: LessonSceneType.mainExplanation,
          visualType: SlideVisualType.bullets,
          lead: 'या मुद्द्याचे आणखी एक कोन समजून घेऊया — नव्याने तथ्य न घेता.',
        ),
      );
    }

    while (slides.length > kMaxEduSlides) {
      // Remove from middle teaching slides, keep arc ends.
      slides.removeAt(3);
    }

    final mcqs = <GeneratedMcq>[
      for (var i = 0; i < points.length && i < 5; i++)
        _mcqFromPoint(points[i], index: i + 1),
    ];
    while (mcqs.length < 5) {
      mcqs.add(_mcqFromPoint(points.first, index: mcqs.length + 1));
    }

    final script = slides
        .map((s) => s.narration.trim().isNotEmpty ? s.narration : s.title)
        .toList();

    return GeneratedLesson(
      question: topic,
      topicName: topic,
      subjectName: subject,
      script: script,
      slides: slides,
      summary:
          'संपूर्ण पुनरावृत्ती — $topic: ${points.take(8).map(_shortBoard).join('; ')}. '
          'MPSC Combine साठी हे मुद्दे पुन्हा अभ्यासा.',
      mcqs: mcqs,
      notes: points.take(12).map(_shortBoard).toList(),
      createdAt: DateTime.now(),
      chapterId: chapterId,
      subjectId: subjectId,
      sourceKind: sourceKind,
      premium: LessonPremiumExtras(
        importantFacts: points.take(6).map(_shortBoard).toList(),
        examTips: const [
          'कलम/संज्ञा अचूक लक्षात ठेवा.',
          'समान संकल्पनांमधील फरक तक्ता करा.',
        ],
        memoryTricks: const [
          'प्रत्येक मुद्द्यामागे एक छोटा "का" जोडा.',
        ],
        pyqInsight: const [
          'Prelims मध्ये थेट वस्तुनिष्ठ तथ्य व फरक विचारले जातात.',
        ],
        commonMistakes: const [
          'सारांश वाचून उपघटक वगळणे.',
        ],
        onePageSummary: points.take(5).map(_shortBoard).join(' · '),
        quickRevision: points.take(10).map(_shortBoard).join('\n'),
      ),
    );
  }

  List<String> _extractPoints(ChapterLessonSource source) {
    final out = <String>[];
    final note = source.note;
    if (note != null) {
      out.addAll(note.importantPoints.map((e) => e.trim()).where((e) => e.length > 8));
      out.addAll(note.revisionSummary.map((e) => e.trim()).where((e) => e.length > 8));
    }
    // Parse markdown headings / bullets from notesText.
    for (final line in source.notesText.split('\n')) {
      final t = line.trim();
      if (t.startsWith('- ') || t.startsWith('* ')) {
        final p = t.substring(2).trim();
        if (p.length > 8) out.add(p);
      } else if (RegExp(r'^#{1,3}\s+').hasMatch(t)) {
        final p = t.replaceFirst(RegExp(r'^#{1,3}\s+'), '').trim();
        if (p.length > 2 && p.length < 80) out.add(p);
      }
    }
    // Deduplicate while preserving order.
    final seen = <String>{};
    final unique = <String>[];
    for (final p in out) {
      final key = p.toLowerCase();
      if (seen.add(key)) unique.add(p);
    }
    return unique;
  }

  GeneratedSlide _teachSlide({
    required String title,
    required String point,
    required LessonSceneType sceneType,
    required SlideVisualType visualType,
    String lead = '',
    List<String> extraBoard = const [],
    GeneratedMcq? sectionQuestion,
  }) {
    final board = <String>[
      _shortBoard(point),
      ...extraBoard,
      'MPSC फोकस',
    ].take(4).toList();
    final narration = StringBuffer()
      ..write(lead.isEmpty ? 'चला हा मुद्दा समजून घेऊया. ' : '$lead ')
      ..write(_teacherLine(point))
      ..write(' ')
      ..write('याचा अर्थ वर्गात असा समजावून घ्या की तो तुम्ही दुसऱ्याला सांगू शकाल. ')
      ..write('परीक्षा दृष्टीने हा मुद्दा लक्षात ठेवणे फायद्याचे आहे.');

    return GeneratedSlide(
      title: title,
      bullets: board,
      sceneType: sceneType,
      visualType: visualType,
      flowchart: visualType == SlideVisualType.flowchart
          ? [
              const FlowNode(id: '1', label: 'संकल्पना', nextIds: ['2']),
              FlowNode(id: '2', label: _shortBoard(point, max: 18), nextIds: const ['3']),
              const FlowNode(id: '3', label: 'परीक्षा कोन'),
            ]
          : const [],
      timeline: visualType == SlideVisualType.timeline
          ? [
              TimelineEvent(year: 'मुख्य', label: _shortBoard(point, max: 28)),
              const TimelineEvent(year: 'परीक्षा', label: 'Prelims फोकस'),
            ]
          : const [],
      tableHeaders:
          visualType == SlideVisualType.table ? const ['मुद्दा', 'नोट'] : const [],
      tableRows: visualType == SlideVisualType.table
          ? [
              [_shortBoard(point, max: 24), 'Verified'],
            ]
          : const [],
      mapRegions: visualType == SlideVisualType.map
          ? [_shortBoard(point, max: 20), 'भारत']
          : const [],
      keywords: _keywordsFrom(point),
      narration: narration.toString(),
      bulletExpansions: [
        for (final b in board) _teacherLine(b == 'MPSC फोकस' ? point : b),
      ],
      sectionQuestion: sectionQuestion,
      explanation: 'स्मरण: ${_shortBoard(point, max: 40)}',
    );
  }

  SlideVisualType _visualFor(String point, int index) {
    final p = point.toLowerCase();
    if (p.contains('तुलना') || p.contains('|') || p.contains('विरुद्ध')) {
      return SlideVisualType.table;
    }
    if (p.contains('वर्ष') ||
        p.contains('इ.स') ||
        p.contains('दुरुस्ती') ||
        RegExp(r'\d{3,4}').hasMatch(p)) {
      return SlideVisualType.timeline;
    }
    if (p.contains('प्रक्रिया') ||
        p.contains('पायरी') ||
        p.contains('→') ||
        p.contains('रिट')) {
      return SlideVisualType.flowchart;
    }
    if (p.contains('राज्य') ||
        p.contains('प्रदेश') ||
        p.contains('किनार') ||
        p.contains('मान्सून')) {
      return SlideVisualType.map;
    }
    switch (index % 4) {
      case 0:
        return SlideVisualType.flowchart;
      case 1:
        return SlideVisualType.table;
      case 2:
        return SlideVisualType.timeline;
      default:
        return SlideVisualType.bullets;
    }
  }

  GeneratedMcq _mcqFromPoint(String point, {required int index}) {
    final fact = _shortBoard(point, max: 42);
    return GeneratedMcq(
      question: 'खालीलपैकी "$fact" बाबत योग्य विधान कोणते?',
      options: [
        fact,
        'हे विधान नोट्समध्ये नाही',
        'हे पूर्णपणे असंबंधित आहे',
        'वरीलपैकी एकही नाही',
      ],
      correctIndex: 0,
      explanation: 'Verified notes नुसार योग्य मुद्दा: $fact',
      wrongExplanations: const {
        '1': 'हा पर्याय नोट्समधील तथ्याशी जुळत नाही.',
        '2': 'हा पर्याय विषयाशी असंबंधित आहे.',
        '3': 'योग्य विधान पर्याय १ मध्ये आहे.',
      },
    );
  }

  List<String> _keywordsFrom(String point) {
    final parts = point
        .split(RegExp(r'[—\-–:,]|कलम'))
        .map((e) => e.trim())
        .where((e) => e.length >= 2 && e.length <= 24)
        .take(4)
        .toList();
    if (parts.isEmpty) return [_shortBoard(point, max: 16)];
    return parts;
  }

  String _shortBoard(String text, {int max = 40}) {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length <= max) return t;
    final cut = t.substring(0, max);
    final at = cut.lastIndexOf(' ');
    return '${(at > 12 ? cut.substring(0, at) : cut).trim()}…';
  }

  String _teacherLine(String point) {
    final spoken = speakableMarathi(point);
    if (spoken.isEmpty) return 'हा मुद्दा नोट्समध्ये दिला आहे.';
    return spoken;
  }
}

const VerifiedNotesLessonComposer verifiedNotesLessonComposer =
    VerifiedNotesLessonComposer();
