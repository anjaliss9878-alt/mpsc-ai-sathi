import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_completeness.dart';

GeneratedLesson _fullClassroomLesson() {
  final slides = <GeneratedSlide>[
    const GeneratedSlide(
      title: 'आजचा विषय',
      bullets: ['परिचय', 'MPSC महत्त्व'],
      sceneType: LessonSceneType.title,
      narration: 'नमस्कार. आज आपण हा विषय सविस्तर शिकणार आहोत. परीक्षा दृष्टीने हा महत्त्वाचा आहे.',
      keywords: ['MPSC'],
    ),
    const GeneratedSlide(
      title: 'आज काय शिकणार',
      bullets: ['व्याख्या', 'उपघटक', 'उदाहरणे'],
      sceneType: LessonSceneType.introduction,
      narration: 'आजच्या धड्यात व्याख्या, सर्व उपघटक, उदाहरणे आणि पुनरावृत्ती पूर्णपणे शिकू.',
    ),
    for (var i = 0; i < 5; i++)
      GeneratedSlide(
        title: 'उपघटक ${i + 1}',
        bullets: const ['मुद्दा अ', 'मुद्दा ब', 'MPSC फॅक्ट'],
        sceneType: LessonSceneType.mainExplanation,
        visualType: i % 3 == 0
            ? SlideVisualType.flowchart
            : i % 3 == 1
                ? SlideVisualType.table
                : SlideVisualType.timeline,
        flowchart: i % 3 == 0
            ? const [
                FlowNode(id: '1', label: 'सुरुवात', nextIds: ['2']),
                FlowNode(id: '2', label: 'शेवट'),
              ]
            : const [],
        tableHeaders: i % 3 == 1 ? const ['अ', 'ब'] : const [],
        tableRows: i % 3 == 1
            ? const [
                ['१', '२'],
              ]
            : const [],
        timeline: i % 3 == 2
            ? const [TimelineEvent(year: '१९५०', label: 'घटना')]
            : const [],
        narration:
            'हा उपघटक सविस्तर समजून घेऊया. अर्थ काय आहे, उदाहरण काय आहे आणि परीक्षा कशी विचारते हे पाहूया.',
        sectionQuestion: i == 1 || i == 3
            ? GeneratedMcq(
                question: 'उपघटक ${i + 1} बद्दल योग्य पर्याय?',
                options: const ['अ', 'ब', 'क', 'ड'],
                correctIndex: 1,
                explanation: 'ब योग्य आहे.',
              )
            : null,
      ),
    const GeneratedSlide(
      title: 'उदाहरणे',
      bullets: ['उदाहरण १', 'उदाहरण २'],
      sceneType: LessonSceneType.examples,
      narration: 'आता दोन सोप्या उदाहरणांनी संकल्पना पक्की करूया. परीक्षेला अशी उदाहरणे उपयोगी ठरतात.',
    ),
    const GeneratedSlide(
      title: 'महत्त्वाची तथ्ये',
      bullets: ['फॅक्ट १', 'फॅक्ट २', 'PYQ कोन'],
      sceneType: LessonSceneType.importantPoints,
      narration: 'ही महत्त्वाची तथ्ये लक्षात ठेवा. MPSC अनेकदा थेट कलम किंवा फरक विचारतो.',
      keywords: ['महत्त्वाची तथ्ये'],
    ),
    const GeneratedSlide(
      title: 'सराव',
      bullets: ['प्रश्न संच'],
      sceneType: LessonSceneType.quiz,
      narration: 'आता थोडा सराव करूया. उत्तर मनात ठरवा आणि मग स्पष्टीकरण ऐका.',
    ),
    const GeneratedSlide(
      title: 'संपूर्ण पुनरावृत्ती',
      bullets: ['सारांश १', 'सारांश २', 'सारांश ३'],
      sceneType: LessonSceneType.summary,
      narration: 'थोडक्यात सर्व मुद्दे परत पाहूया. प्रत्येक उपघटक लक्षात ठेवा आणि उद्याच्या अभ्यासात उपयोग करा.',
    ),
  ];

  return GeneratedLesson(
    question: 'डेमो विषय',
    topicName: 'डेमो विषय',
    subjectName: 'राज्यशास्त्र',
    script: slides.map((s) => s.narration).toList(),
    slides: slides,
    summary: 'संपूर्ण पुनरावृत्ती: सर्व उपघटक, उदाहरणे आणि महत्त्वाची तथ्ये लक्षात ठेवा.',
    mcqs: const [
      GeneratedMcq(
        question: 'प्रश्न १?',
        options: ['अ', 'ब', 'क', 'ड'],
        correctIndex: 0,
        explanation: 'अ.',
      ),
      GeneratedMcq(
        question: 'प्रश्न २?',
        options: ['अ', 'ब', 'क', 'ड'],
        correctIndex: 1,
        explanation: 'ब.',
      ),
      GeneratedMcq(
        question: 'प्रश्न ३?',
        options: ['अ', 'ब', 'क', 'ड'],
        correctIndex: 2,
        explanation: 'क.',
      ),
      GeneratedMcq(
        question: 'प्रश्न ४?',
        options: ['अ', 'ब', 'क', 'ड'],
        correctIndex: 0,
        explanation: 'अ.',
      ),
      GeneratedMcq(
        question: 'प्रश्न ५?',
        options: ['अ', 'ब', 'क', 'ड'],
        correctIndex: 1,
        explanation: 'ब.',
      ),
    ],
    notes: const [
      'टीप १',
      'टीप २',
      'टीप ३',
      'टीप ४',
      'टीप ५',
      'टीप ६',
      'टीप ७',
      'टीप ८',
    ],
    createdAt: DateTime(2026, 8, 10),
    premium: const LessonPremiumExtras(
      importantFacts: ['फॅक्ट अ', 'फॅक्ट ब', 'फॅक्ट क', 'फॅक्ट ड'],
      memoryTricks: ['युक्ती'],
      pyqInsight: ['PYQ'],
      examTips: ['टिप'],
    ),
  );
}

void main() {
  test('full classroom lesson passes completeness gate', () {
    final report = lessonCompleteness.analyze(_fullClassroomLesson());
    expect(report.ok, isTrue, reason: report.gaps.join(' | '));
    expect(report.slideCount, inInclusiveRange(8, 12));
    expect(report.mainExplanationCount, greaterThanOrEqualTo(3));
    expect(report.sectionMcqCount, greaterThanOrEqualTo(2));
    expect(report.visualVarietyCount, greaterThanOrEqualTo(2));
  });

  test('summary-like lesson fails completeness gate', () {
    final thin = GeneratedLesson(
      question: 'थोडा विषय',
      topicName: 'थोडा विषय',
      subjectName: 'टेस्ट',
      script: const ['सारांश'],
      slides: List.generate(
        8,
        (i) => GeneratedSlide(
          title: 'स्लाइड $i',
          bullets: const ['एकच मुद्दा'],
          narration: 'थोडक्यात.',
        ),
      ),
      summary: 'थोडक्यात.',
      mcqs: const [],
      notes: const ['अ'],
      createdAt: DateTime(2026, 8, 10),
    );
    final report = lessonCompleteness.analyze(thin);
    expect(report.ok, isFalse);
    expect(report.gaps, isNotEmpty);
  });

  test('sanitizeBoardText shortens oversized bullets', () {
    final lesson = GeneratedLesson(
      question: 'x',
      topicName: 'x',
      subjectName: 'y',
      script: const ['n'],
      slides: [
        GeneratedSlide(
          title: 'टी',
          bullets: [
            'हा एक खूपच लांब बोर्ड मजकूर आहे जो विद्यार्थ्याला वाचायला कठीण वाटेल आणि संपूर्ण स्पष्टीकरण बोर्डवर टाकतो',
          ],
          narration: 'पूर्ण स्पष्टीकरण आवाजात येते. बोर्डवर फक्त लहान मुद्दे असावेत. परीक्षा दृष्टीने हे महत्त्वाचे आहे.',
        ),
      ],
      summary: 'स',
      mcqs: const [],
      notes: const [],
      createdAt: DateTime(2026, 8, 10),
    );
    final cleaned = lessonCompleteness.sanitizeBoardText(lesson);
    expect(
      cleaned.slides.first.bullets.first.length,
      lessThanOrEqualTo(LessonCompleteness.maxBulletChars + 1),
    );
  });
}
