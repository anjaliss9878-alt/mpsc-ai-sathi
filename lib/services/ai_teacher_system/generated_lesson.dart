import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subtitle_timing.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Classroom scene order for the Video Lesson Engine.
enum LessonSceneType {
  title,
  introduction,
  mainExplanation,
  importantPoints,
  examples,
  diagram,
  summary,
  quiz,
}

LessonSceneType lessonSceneTypeFromString(String? value) {
  switch (value) {
    case 'title':
      return LessonSceneType.title;
    case 'introduction':
      return LessonSceneType.introduction;
    case 'mainExplanation':
    case 'main':
      return LessonSceneType.mainExplanation;
    case 'importantPoints':
    case 'points':
    case 'pyq':
    case 'pyqExplanation':
      // Scene 6 in Topic→Video Teacher: dedicated PYQ explanation.
      return LessonSceneType.importantPoints;
    case 'examples':
      return LessonSceneType.examples;
    case 'diagram':
      return LessonSceneType.diagram;
    case 'summary':
      return LessonSceneType.summary;
    case 'quiz':
      return LessonSceneType.quiz;
    default:
      return LessonSceneType.mainExplanation;
  }
}

/// How the Lesson Studio Scene Engine should render a scene.
/// Gemini picks the best type per topic — Flutter only dispatches on this.
enum SlideVisualType {
  bullets,
  whiteboard,
  flowchart,
  mindmap,
  timeline,
  map,
  table,
  graph,
  icons,
  image,
}

SlideVisualType slideVisualTypeFromString(String? value) {
  switch (value) {
    case 'whiteboard':
    case 'drawing':
      return SlideVisualType.whiteboard;
    case 'flowchart':
      return SlideVisualType.flowchart;
    case 'mindmap':
    case 'mindMap':
      return SlideVisualType.mindmap;
    case 'table':
    case 'comparison':
    case 'infographic':
      return SlideVisualType.table;
    case 'map':
      return SlideVisualType.map;
    case 'timeline':
      return SlideVisualType.timeline;
    case 'graph':
    case 'chart':
      return SlideVisualType.graph;
    case 'icons':
      return SlideVisualType.icons;
    case 'image':
      return SlideVisualType.image;
    case 'bullets':
    default:
      return SlideVisualType.bullets;
  }
}

/// Legacy highlight badge (kept for older lessons / admin content).
enum SlideHighlightType { none, diagram, map, timeline }

SlideHighlightType slideHighlightTypeFromString(String? value) {
  switch (value) {
    case 'diagram':
      return SlideHighlightType.diagram;
    case 'map':
      return SlideHighlightType.map;
    case 'timeline':
      return SlideHighlightType.timeline;
    default:
      return SlideHighlightType.none;
  }
}

/// One node in an auto-generated flowchart graphic.
class FlowNode {
  const FlowNode({required this.id, required this.label, this.nextIds = const []});

  final String id;
  final String label;
  final List<String> nextIds;

  factory FlowNode.fromMap(Map<String, dynamic> map) {
    return FlowNode(
      id: (map['id'] as String?) ?? '',
      label: (map['label'] as String?) ?? '',
      nextIds: asStringList(map['nextIds']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'nextIds': nextIds,
      };
}

/// One event on an auto-generated timeline graphic.
class TimelineEvent {
  const TimelineEvent({required this.year, required this.label});

  final String year;
  final String label;

  factory TimelineEvent.fromMap(Map<String, dynamic> map) {
    return TimelineEvent(
      year: (map['year'] as String?) ?? '',
      label: (map['label'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() => {'year': year, 'label': label};
}

/// One stroke/step on a whiteboard drawing animation.
class DrawStep {
  const DrawStep({
    required this.kind,
    required this.label,
    this.x = 0.1,
    this.y = 0.1,
  });

  /// text | box | circle | arrow
  final String kind;
  final String label;
  final double x;
  final double y;

  factory DrawStep.fromMap(Map<String, dynamic> map) {
    return DrawStep(
      kind: (map['kind'] as String?) ?? 'text',
      label: (map['label'] as String?) ?? '',
      x: (map['x'] as num?)?.toDouble() ?? 0.1,
      y: (map['y'] as num?)?.toDouble() ?? 0.1,
    );
  }

  Map<String, dynamic> toMap() => {
        'kind': kind,
        'label': label,
        'x': x,
        'y': y,
      };
}

class MindMapBranch {
  const MindMapBranch({required this.label, this.children = const []});

  final String label;
  final List<String> children;

  factory MindMapBranch.fromMap(Map<String, dynamic> map) {
    return MindMapBranch(
      label: (map['label'] as String?) ?? '',
      children: asStringList(map['children']),
    );
  }

  Map<String, dynamic> toMap() => {'label': label, 'children': children};
}

class MindMapData {
  const MindMapData({required this.center, this.branches = const []});

  final String center;
  final List<MindMapBranch> branches;

  factory MindMapData.fromMap(Map<String, dynamic> map) {
    return MindMapData(
      center: (map['center'] as String?) ?? '',
      branches: asMapList(map['branches']).map(MindMapBranch.fromMap).toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'center': center,
        'branches': branches.map((b) => b.toMap()).toList(),
      };
}

class GraphData {
  const GraphData({
    this.type = 'bar',
    this.labels = const [],
    this.values = const [],
  });

  final String type;
  final List<String> labels;
  final List<double> values;

  factory GraphData.fromMap(Map<String, dynamic> map) {
    return GraphData(
      type: (map['type'] as String?) ?? 'bar',
      labels: asStringList(map['labels']),
      values: asDoubleList(map['values']),
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type,
        'labels': labels,
        'values': values,
      };
}

/// One slide / scene on the Teaching Board / Lesson Studio canvas.
class GeneratedSlide {
  const GeneratedSlide({
    required this.title,
    required this.bullets,
    this.highlightType = SlideHighlightType.none,
    this.highlightLabel = '',
    this.sceneType = LessonSceneType.mainExplanation,
    this.visualType = SlideVisualType.bullets,
    this.keywords = const [],
    this.tableHeaders = const [],
    this.tableRows = const [],
    this.flowchart = const [],
    this.timeline = const [],
    this.mapRegions = const [],
    this.iconLabels = const [],
    this.imageUrl = '',
    this.drawSteps = const [],
    this.mindMap,
    this.graph,
    this.pointerPath = const [],
    this.handwriting = const [],
    this.transition = 'fade',
    this.narration = '',
    this.bulletExpansions = const [],
    this.sectionQuestion,
    this.subtitleTiming = const [],
    this.explanation = '',
  });

  final String title;
  final List<String> bullets;
  final SlideHighlightType highlightType;
  final String highlightLabel;
  final LessonSceneType sceneType;
  final SlideVisualType visualType;
  final List<String> keywords;
  final List<String> tableHeaders;
  final List<List<String>> tableRows;
  final List<FlowNode> flowchart;
  final List<TimelineEvent> timeline;
  final List<String> mapRegions;
  final List<String> iconLabels;
  final String imageUrl;
  final List<DrawStep> drawSteps;
  final MindMapData? mindMap;
  final GraphData? graph;
  final List<String> pointerPath;
  final List<String> handwriting;
  final String transition;
  final String narration;

  /// Optional per-bullet spoken expansions (same order as [bullets]).
  /// Empty for legacy lessons — teaching sequence synthesizes fallbacks.
  final List<String> bulletExpansions;
  final GeneratedMcq? sectionQuestion;

  /// Karaoke / word-sync cues for this scene (0–1 normalized). Empty → derived
  /// from [narration] or spoken beat text at playback time.
  final List<SubtitleCue> subtitleTiming;

  /// Short scene explanation shown / spoken after the concept (optional).
  final String explanation;

  /// Effective subtitle cues for this scene.
  List<SubtitleCue> resolvedSubtitleTiming([String? spokenFallback]) {
    if (subtitleTiming.isNotEmpty) return subtitleTiming;
    final source = (spokenFallback ?? narration).trim();
    if (source.isEmpty) return const [];
    return buildSubtitleTimingFromText(source);
  }

  /// How many progressive animation steps this scene has (voice sync).
  int get animationSteps {
    switch (resolvedVisualType) {
      case SlideVisualType.whiteboard:
        return drawSteps.isNotEmpty
            ? drawSteps.length
            : (bullets.isEmpty ? 1 : bullets.length);
      case SlideVisualType.flowchart:
        return flowchart.isNotEmpty ? flowchart.length : 3;
      case SlideVisualType.mindmap:
        final branches = mindMap?.branches.length ?? 0;
        return branches > 0
            ? branches + 1
            : (bullets.isEmpty ? 1 : bullets.length);
      case SlideVisualType.timeline:
        return timeline.isNotEmpty ? timeline.length : 3;
      case SlideVisualType.map:
        return mapRegions.isNotEmpty ? mapRegions.length : 2;
      case SlideVisualType.table:
        return tableRows.isNotEmpty ? tableRows.length : bullets.length;
      case SlideVisualType.graph:
        return graph?.values.length ??
            (bullets.isEmpty ? 1 : bullets.length);
      case SlideVisualType.icons:
        final n =
            iconLabels.isNotEmpty ? iconLabels.length : bullets.length;
        return n == 0 ? 1 : n;
      case SlideVisualType.image:
      case SlideVisualType.bullets:
        if (handwriting.isNotEmpty) return handwriting.length;
        return bullets.isEmpty ? 1 : bullets.length;
    }
  }

  /// Picks the richest payload if Gemini omitted / mismatched visualType.
  SlideVisualType get resolvedVisualType {
    if (visualType != SlideVisualType.bullets) return visualType;
    if (drawSteps.isNotEmpty) return SlideVisualType.whiteboard;
    if (mindMap != null && (mindMap!.center.isNotEmpty || mindMap!.branches.isNotEmpty)) {
      return SlideVisualType.mindmap;
    }
    if (graph != null && graph!.values.isNotEmpty) return SlideVisualType.graph;
    if (flowchart.isNotEmpty) return SlideVisualType.flowchart;
    if (timeline.isNotEmpty) return SlideVisualType.timeline;
    if (mapRegions.isNotEmpty) return SlideVisualType.map;
    if (tableHeaders.isNotEmpty || tableRows.isNotEmpty) return SlideVisualType.table;
    if (imageUrl.trim().isNotEmpty) return SlideVisualType.image;
    if (iconLabels.isNotEmpty) return SlideVisualType.icons;
    return SlideVisualType.bullets;
  }

  factory GeneratedSlide.fromMap(Map<String, dynamic> map) {
    GeneratedMcq? sectionQ;
    final rawQ = map['sectionQuestion'];
    if (rawQ is Map) {
      sectionQ = GeneratedMcq.fromMap(Map<String, dynamic>.from(rawQ));
    }
    MindMapData? mind;
    final rawMind = map['mindMap'] ?? map['mindmap'];
    if (rawMind is Map) {
      mind = MindMapData.fromMap(Map<String, dynamic>.from(rawMind));
    }
    GraphData? graph;
    final rawGraph = map['graph'];
    if (rawGraph is Map) {
      graph = GraphData.fromMap(Map<String, dynamic>.from(rawGraph));
    }
    return GeneratedSlide(
      title: (map['title'] as String?)?.trim().isNotEmpty == true
          ? map['title'] as String
          : 'Untitled slide',
      bullets: asStringList(map['bullets']),
      highlightType: slideHighlightTypeFromString(map['highlightType'] as String?),
      highlightLabel: (map['highlightLabel'] as String?) ?? '',
      sceneType: lessonSceneTypeFromString(map['sceneType'] as String?),
      visualType: slideVisualTypeFromString(map['visualType'] as String?),
      keywords: asStringList(map['keywords']),
      tableHeaders: asStringList(map['tableHeaders'], keepEmpty: true),
      tableRows: asStringTable(map['tableRows']),
      flowchart: asMapList(map['flowchart']).map(FlowNode.fromMap).toList(),
      timeline: asMapList(map['timeline']).map(TimelineEvent.fromMap).toList(),
      mapRegions: asStringList(map['mapRegions']),
      iconLabels: asStringList(map['iconLabels']),
      imageUrl: (map['imageUrl'] as String?) ?? '',
      drawSteps: asMapList(map['drawSteps']).map(DrawStep.fromMap).toList(),
      mindMap: mind,
      graph: graph,
      pointerPath: asStringList(map['pointerPath']),
      handwriting: asStringList(map['handwriting']),
      transition: (map['transition'] as String?) ?? 'fade',
      narration: (map['narration'] as String?) ?? '',
      bulletExpansions: asStringList(map['bulletExpansions']),
      sectionQuestion: sectionQ,
      subtitleTiming: asMapList(map['subtitleTiming'])
          .map(SubtitleCue.fromMap)
          .toList(),
      explanation: (map['explanation'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'bullets': bullets,
        'highlightType': highlightType.name,
        'highlightLabel': highlightLabel,
        'sceneType': sceneType.name,
        'visualType': visualType.name,
        'keywords': keywords,
        'tableHeaders': tableHeaders,
        'tableRows': tableRows,
        'flowchart': flowchart.map((n) => n.toMap()).toList(),
        'timeline': timeline.map((e) => e.toMap()).toList(),
        'mapRegions': mapRegions,
        'iconLabels': iconLabels,
        'imageUrl': imageUrl,
        'drawSteps': drawSteps.map((d) => d.toMap()).toList(),
        if (mindMap != null) 'mindMap': mindMap!.toMap(),
        if (graph != null) 'graph': graph!.toMap(),
        'pointerPath': pointerPath,
        'handwriting': handwriting,
        'transition': transition,
        'narration': narration,
        'bulletExpansions': bulletExpansions,
        if (sectionQuestion != null) 'sectionQuestion': sectionQuestion!.toMap(),
        'subtitleTiming': subtitleTiming.map((c) => c.toMap()).toList(),
        'explanation': explanation,
      };
}

/// One AI-generated multiple-choice question.
class GeneratedMcq {
  const GeneratedMcq({
    required this.question,
    required this.options,
    required this.correctIndex,
    this.explanation = '',
    this.wrongExplanations = const {},
    this.difficulty = McqDifficulty.medium,
    this.kind = McqKind.standard,
  });

  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  /// Optional per-wrong-option explanations (key = option index as string).
  final Map<String, String> wrongExplanations;
  final McqDifficulty difficulty;
  final McqKind kind;

  String get difficultyLabelMr => switch (difficulty) {
        McqDifficulty.easy => 'सोपे',
        McqDifficulty.medium => 'मध्यम',
        McqDifficulty.hard => 'कठीण',
      };

  String get kindLabelMr => switch (kind) {
        McqKind.standard => 'तथ्य',
        McqKind.factual => 'तथ्य',
        McqKind.conceptual => 'संकल्पना',
        McqKind.statement => 'विधान',
        McqKind.assertionReason => 'विधान-कारण',
        McqKind.match => 'जोडी जुळवा',
        McqKind.mapBased => 'नकाशा',
      };

  String explanationFor(int selectedIndex) {
    if (selectedIndex == correctIndex) return explanation;
    final keyed = wrongExplanations['$selectedIndex'];
    if (keyed != null && keyed.trim().isNotEmpty) return keyed;
    return explanation;
  }

  factory GeneratedMcq.fromMap(Map<String, dynamic> map) {
    final options = asStringList(map['options']);
    var correctIndex = (map['correctIndex'] as num?)?.toInt() ??
        (map['correct_index'] as num?)?.toInt() ??
        0;
    final correctAnswer =
        '${map['correctAnswer'] ?? map['correct_answer'] ?? ''}'.trim();
    if (correctAnswer.isNotEmpty && options.isNotEmpty) {
      final byText = options.indexWhere(
        (o) => o.trim() == correctAnswer || o.trim().contains(correctAnswer),
      );
      if (byText >= 0) correctIndex = byText;
    }
    if (options.isEmpty) {
      correctIndex = 0;
    } else {
      correctIndex = correctIndex.clamp(0, options.length - 1);
    }
    final rawWrong = map['wrongExplanations'];
    final wrong = <String, String>{};
    if (rawWrong is Map) {
      rawWrong.forEach((k, v) => wrong[k.toString()] = v.toString());
    }
    return GeneratedMcq(
      question: (map['question'] as String?) ?? '',
      options: options,
      correctIndex: correctIndex,
      explanation: (map['explanation'] as String?) ?? '',
      wrongExplanations: wrong,
      difficulty: McqDifficultyX.parse(map['difficulty'] as String?),
      kind: McqKindX.parse(map['kind'] as String? ?? map['type'] as String?),
    );
  }

  Map<String, dynamic> toMap() => {
        'question': question,
        'options': options,
        'correctIndex': correctIndex,
        'explanation': explanation,
        'wrongExplanations': wrongExplanations,
        'difficulty': difficulty.name,
        'kind': kind.name,
      };
}

enum McqDifficulty { easy, medium, hard }

extension McqDifficultyX on McqDifficulty {
  static McqDifficulty parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'easy':
      case 'सोपे':
        return McqDifficulty.easy;
      case 'hard':
      case 'कठीण':
        return McqDifficulty.hard;
      default:
        return McqDifficulty.medium;
    }
  }
}

enum McqKind { standard, factual, conceptual, statement, assertionReason, match, mapBased }

extension McqKindX on McqKind {
  static McqKind parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'factual':
      case 'fact':
        return McqKind.factual;
      case 'conceptual':
      case 'concept':
        return McqKind.conceptual;
      case 'statement':
      case 'statement-based':
      case 'statementbased':
        return McqKind.statement;
      case 'assertionreason':
      case 'assertion-reason':
      case 'assertion_reason':
        return McqKind.assertionReason;
      case 'match':
      case 'matchthepairs':
      case 'match_the_pairs':
      case 'match the following':
        return McqKind.match;
      case 'map':
      case 'mapbased':
      case 'map-based':
        return McqKind.mapBased;
      default:
        return McqKind.standard;
    }
  }
}

/// Previous-year-style exam question with analysis (not always MCQ).
class GeneratedPyq {
  const GeneratedPyq({
    required this.question,
    this.year = '',
    this.answer = '',
    this.analysis = '',
    this.trend = '',
    this.exam = '',
    this.whyAsked = '',
  });

  final String question;
  final String year;
  final String answer;
  final String analysis;
  final String trend;
  final String exam;
  final String whyAsked;

  factory GeneratedPyq.fromMap(Map<String, dynamic> map) {
    final rawYear =
        '${(map['year'] as String?) ?? (map['examYear'] as String?) ?? ''}'
            .trim();
    final rawExam = '${(map['exam'] as String?) ?? (map['paper'] as String?) ?? (map['examName'] as String?) ?? ''}'
        .trim();
    final knownOfficial = _looksLikeOfficialPyq(year: rawYear, exam: rawExam);
    return GeneratedPyq(
      question: (map['question'] as String?) ?? '',
      year: knownOfficial ? rawYear : '',
      answer: (map['answer'] as String?) ?? '',
      analysis: (map['analysis'] as String?) ??
          (map['explanation'] as String?) ??
          '',
      trend: (map['trend'] as String?) ??
          (map['trendAnalysis'] as String?) ??
          '',
      exam: knownOfficial ? rawExam : 'PYQ-based practice question',
      whyAsked: (map['whyAsked'] as String?) ??
          (map['whyItWasAsked'] as String?) ??
          '',
    );
  }

  Map<String, dynamic> toMap() => {
        'question': question,
        'year': year,
        'answer': answer,
        'analysis': analysis,
        'trend': trend,
        'exam': exam,
        'whyAsked': whyAsked,
      };
}

bool _looksLikeOfficialPyq({required String year, required String exam}) {
  final lower = exam.toLowerCase();
  if (lower.contains('practice') ||
      lower.contains('based') ||
      lower.contains('सराव') ||
      exam.trim().isEmpty) {
    return false;
  }
  final match = RegExp(r'(19|20)\d{2}').firstMatch(year);
  if (match == null) return false;
  final y = int.tryParse(match.group(0)!);
  if (y == null || y < 1990 || y > DateTime.now().year) return false;
  // Dynamic Gemini output is not a verified PYQ archive.
  return false;
}

/// A single step shown on the horizontal [LessonTimeline] strip.
class LessonTimelineStep {
  const LessonTimelineStep({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

IconData _iconForScene(LessonSceneType type, SlideHighlightType highlight) {
  switch (type) {
    case LessonSceneType.title:
      return Icons.flag_rounded;
    case LessonSceneType.introduction:
      return Icons.waving_hand_rounded;
    case LessonSceneType.mainExplanation:
      return Icons.menu_book_rounded;
    case LessonSceneType.importantPoints:
      return Icons.star_rounded;
    case LessonSceneType.examples:
      return Icons.lightbulb_rounded;
    case LessonSceneType.diagram:
      return Icons.account_tree_rounded;
    case LessonSceneType.summary:
      return Icons.summarize_rounded;
    case LessonSceneType.quiz:
      return Icons.quiz_rounded;
  }
}

/// Builds the [LessonTimeline] strip's steps directly from a lesson's slides.
List<LessonTimelineStep> timelineFromSlides(List<GeneratedSlide> slides) {
  if (slides.isEmpty) return const [];
  return List.generate(slides.length, (i) {
    final slide = slides[i];
    return LessonTimelineStep(
      label: slide.title,
      icon: _iconForScene(slide.sceneType, slide.highlightType),
    );
  });
}

/// Spoken segments derived from slides (narration field) or the flat script.
List<String> narrationSegmentsFor(GeneratedLesson lesson) {
  if (lesson.slides.any((s) => s.narration.trim().isNotEmpty)) {
    return lesson.slides
        .map((s) => s.narration.trim().isNotEmpty
            ? s.narration.trim()
            : (s.bullets.isNotEmpty ? s.bullets.join('. ') : s.title))
        .toList();
  }
  return lesson.script;
}

/// Optional MPSC premium extras — empty for older cached / welcome lessons.
class LessonPremiumExtras {
  const LessonPremiumExtras({
    this.pyqInsight = const [],
    this.examTips = const [],
    this.commonMistakes = const [],
    this.memoryTricks = const [],
    this.importantFacts = const [],
    this.examTraps = const [],
    this.onePageSummary = '',
    this.quickRevision = '',
    this.introduction = '',
    this.mainConcepts = const [],
    this.factBox = '',
    this.pyqConnection = '',
    this.examples = const [],
  });

  final List<String> pyqInsight;
  final List<String> examTips;
  final List<String> commonMistakes;
  final List<String> memoryTricks;
  final List<String> importantFacts;
  final List<String> examTraps;
  final String onePageSummary;
  final String quickRevision;
  final String introduction;
  final List<String> mainConcepts;
  final String factBox;
  final String pyqConnection;
  final List<String> examples;

  bool get hasContent =>
      pyqInsight.isNotEmpty ||
      examTips.isNotEmpty ||
      commonMistakes.isNotEmpty ||
      memoryTricks.isNotEmpty ||
      importantFacts.isNotEmpty ||
      examTraps.isNotEmpty ||
      onePageSummary.trim().isNotEmpty ||
      quickRevision.trim().isNotEmpty ||
      introduction.trim().isNotEmpty ||
      mainConcepts.isNotEmpty ||
      factBox.trim().isNotEmpty ||
      pyqConnection.trim().isNotEmpty ||
      examples.isNotEmpty;

  factory LessonPremiumExtras.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const LessonPremiumExtras();

    // Gemini occasionally returns a bare string instead of a list for tip
    // fields — tolerate both so lesson generation never crashes at parse time.
    String text(String key) {
      final raw = map[key];
      if (raw is String) return raw;
      if (raw is List || raw is Map) {
        return asStringList(raw).join('\n');
      }
      return '';
    }

    return LessonPremiumExtras(
      pyqInsight: asStringList(map['pyqInsight']),
      examTips: asStringList(map['examTips']).isNotEmpty
          ? asStringList(map['examTips'])
          : asStringList(map['mpsc_points']),
      commonMistakes: asStringList(map['commonMistakes']).isNotEmpty
          ? asStringList(map['commonMistakes'])
          : asStringList(map['common_mistakes']),
      memoryTricks: asStringList(map['memoryTricks']).isNotEmpty
          ? asStringList(map['memoryTricks'])
          : asStringList(map['memory_tricks']),
      importantFacts: asStringList(map['importantFacts']).isNotEmpty
          ? asStringList(map['importantFacts'])
          : asStringList(map['important_facts']).isNotEmpty
              ? asStringList(map['important_facts'])
              : asStringList(map['importantPoints']),
      examTraps: asStringList(map['examTraps']).isNotEmpty
          ? asStringList(map['examTraps'])
          : asStringList(map['exam_traps']),
      onePageSummary: text('onePageSummary').trim().isNotEmpty
          ? text('onePageSummary')
          : text('explanation'),
      quickRevision: text('quickRevision').trim().isNotEmpty
          ? text('quickRevision')
          : asStringList(map['revision_points']).isNotEmpty
              ? asStringList(map['revision_points']).join('\n')
              : asStringList(map['revision']).join('\n'),
      introduction: text('introduction'),
      mainConcepts: asStringList(map['mainConcepts']).isNotEmpty
          ? asStringList(map['mainConcepts'])
          : asStringList(map['concepts']),
      factBox: text('factBox'),
      pyqConnection: text('pyqConnection'),
      examples: asStringList(map['examples']),
    );
  }

  LessonPremiumExtras mergeVerifiedNotes(Map<String, dynamic>? notes) {
    if (notes == null) return this;
    final pack = LessonPremiumExtras.fromMap(notes);
    return LessonPremiumExtras(
      pyqInsight: pyqInsight,
      examTips: examTips,
      commonMistakes: commonMistakes,
      memoryTricks: memoryTricks.isNotEmpty ? memoryTricks : pack.memoryTricks,
      importantFacts:
          importantFacts.isNotEmpty ? importantFacts : pack.importantFacts,
      examTraps: examTraps.isNotEmpty ? examTraps : pack.examTraps,
      onePageSummary: onePageSummary,
      quickRevision: quickRevision,
      introduction:
          introduction.trim().isNotEmpty ? introduction : pack.introduction,
      mainConcepts: mainConcepts.isNotEmpty ? mainConcepts : pack.mainConcepts,
      factBox: factBox.trim().isNotEmpty ? factBox : pack.factBox,
      pyqConnection:
          pyqConnection.trim().isNotEmpty ? pyqConnection : pack.pyqConnection,
      examples: examples.isNotEmpty ? examples : pack.examples,
    );
  }

  Map<String, dynamic> toMap() => {
        'pyqInsight': pyqInsight,
        'examTips': examTips,
        'commonMistakes': commonMistakes,
        'memoryTricks': memoryTricks,
        'importantFacts': importantFacts,
        'examTraps': examTraps,
        'onePageSummary': onePageSummary,
        'quickRevision': quickRevision,
        'introduction': introduction,
        'mainConcepts': mainConcepts,
        'factBox': factBox,
        'pyqConnection': pyqConnection,
        'examples': examples,
      };
}

/// Internal grounding label — never shown as a student-facing blocker.
enum LessonSourceKind {
  /// Built from published Firestore notes / PDF.
  verifiedNotes,

  /// Dynamic Gemini (or offline AI composer) when notes are missing.
  aiGenerated,
}

LessonSourceKind lessonSourceKindFromString(String? value) {
  switch (value) {
    case 'verifiedNotes':
    case 'verified_notes':
      return LessonSourceKind.verifiedNotes;
    case 'aiGenerated':
    case 'ai_generated':
    default:
      return LessonSourceKind.aiGenerated;
  }
}

/// A complete AI Teacher lesson package for the Video Lesson Engine.
class GeneratedLesson {
  const GeneratedLesson({
    required this.question,
    required this.topicName,
    required this.subjectName,
    required this.script,
    required this.slides,
    required this.summary,
    required this.mcqs,
    required this.notes,
    required this.createdAt,
    this.id = '',
    this.chapterId = '',
    this.subjectId = '',
    this.premium = const LessonPremiumExtras(),
    this.sourceKind = LessonSourceKind.aiGenerated,
    this.pyqs = const [],
  });

  final String id;
  final String question;
  final String topicName;
  final String subjectName;
  final List<String> script;
  final List<GeneratedSlide> slides;
  final String summary;
  final List<GeneratedMcq> mcqs;
  final List<String> notes;
  final DateTime createdAt;
  final String chapterId;
  final String subjectId;

  /// Optional premium MPSC pack — safe empty default for older lessons.
  final LessonPremiumExtras premium;

  /// Internal only: verified notes vs dynamic AI generation.
  final LessonSourceKind sourceKind;

  /// Previous-year-style questions with analysis.
  final List<GeneratedPyq> pyqs;

  bool get isAiGenerated => sourceKind == LessonSourceKind.aiGenerated;
  bool get isVerifiedNotes => sourceKind == LessonSourceKind.verifiedNotes;

  GeneratedLesson copyWith({
    String? id,
    String? chapterId,
    String? subjectId,
    String? topicName,
    String? subjectName,
    String? question,
    LessonPremiumExtras? premium,
    LessonSourceKind? sourceKind,
    List<GeneratedMcq>? mcqs,
    List<GeneratedPyq>? pyqs,
    List<String>? notes,
    String? summary,
    List<String>? script,
    List<GeneratedSlide>? slides,
  }) =>
      GeneratedLesson(
        id: id ?? this.id,
        question: question ?? this.question,
        topicName: topicName ?? this.topicName,
        subjectName: subjectName ?? this.subjectName,
        script: script ?? this.script,
        slides: slides ?? this.slides,
        summary: summary ?? this.summary,
        mcqs: mcqs ?? this.mcqs,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        chapterId: chapterId ?? this.chapterId,
        subjectId: subjectId ?? this.subjectId,
        premium: premium ?? this.premium,
        sourceKind: sourceKind ?? this.sourceKind,
        pyqs: pyqs ?? this.pyqs,
      );

  factory GeneratedLesson.fromMap(Map<String, dynamic> map, String id) {
    final rawPremium = map['premium'];
    final rawVerified = map['verifiedNotes'];
    var premium = LessonPremiumExtras.fromMap(
      rawPremium is Map ? Map<String, dynamic>.from(rawPremium) : null,
    );
    if (rawVerified is Map) {
      premium = premium.mergeVerifiedNotes(Map<String, dynamic>.from(rawVerified));
    }
    return GeneratedLesson(
      id: id,
      question: (map['question'] as String?) ?? (map['topic'] as String?) ?? '',
      topicName: (map['topicName'] as String?) ??
          (map['title'] as String?) ??
          (map['topic'] as String?) ??
          'AI Teacher Lesson',
      subjectName: (map['subjectName'] as String?) ??
          (map['subject'] as String?) ??
          'MPSC Combine',
      script: _scriptFromMap(map),
      slides: _slidesFromMap(map),
      summary: (map['summary'] as String?) ??
          (map['explanation'] as String?) ??
          (map['introduction'] as String?) ??
          '',
      mcqs: asMapList(map['mcqs']).map(GeneratedMcq.fromMap).toList(),
      notes: _notesFromMap(map),
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      chapterId: (map['chapterId'] as String?) ?? '',
      subjectId: (map['subjectId'] as String?) ?? '',
      sourceKind: lessonSourceKindFromString(map['sourceKind'] as String?),
      pyqs: asMapList(map['pyqs']).map(GeneratedPyq.fromMap).toList(),
      premium: _premiumFromLessonMap(map, premium),
    );
  }

  Map<String, dynamic> toMap() => {
        'question': question,
        'topicName': topicName,
        'subjectName': subjectName,
        'script': script,
        'slides': slides.map((s) => s.toMap()).toList(),
        'summary': summary,
        'mcqs': mcqs.map((m) => m.toMap()).toList(),
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'chapterId': chapterId,
        'subjectId': subjectId,
        'premium': premium.toMap(),
        'sourceKind': sourceKind.name,
        'pyqs': pyqs.map((p) => p.toMap()).toList(),
      };
}

List<String> _scriptFromMap(Map<String, dynamic> map) {
  final list = asStringList(map['script']);
  if (list.isNotEmpty) return list;
  final teaching =
      '${map['teaching_script'] ?? map['teachingScript'] ?? ''}'.trim();
  if (teaching.isNotEmpty) {
    return teaching
        .split(RegExp(r'\n{2,}'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  final explanation = '${map['explanation'] ?? map['summary'] ?? ''}'.trim();
  return explanation.isEmpty ? const [] : [explanation];
}

List<GeneratedSlide> _slidesFromMap(Map<String, dynamic> map) {
  final slides = asMapList(map['slides']).map(GeneratedSlide.fromMap).toList();
  if (slides.isNotEmpty) return slides;
  final title = '${map['title'] ?? map['topicName'] ?? map['topic'] ?? ''}'.trim();
  final intro = '${map['introduction'] ?? map['explanation'] ?? map['summary'] ?? ''}'.trim();
  final points = asStringList(map['importantPoints']).isNotEmpty
      ? asStringList(map['importantPoints'])
      : asStringList(map['important_facts']);
  if (title.isEmpty && intro.isEmpty && points.isEmpty) return const [];
  return [
    GeneratedSlide(
      title: title.isEmpty ? 'धडा' : title,
      bullets: points.take(4).toList(),
      narration: intro,
      keywords: points.take(4).toList(),
      sceneType: LessonSceneType.introduction,
    ),
  ];
}

List<String> _notesFromMap(Map<String, dynamic> map) {
  final notes = asStringList(map['notes']);
  if (notes.isNotEmpty) return notes;
  final intro = '${map['introduction'] ?? ''}'.trim();
  final explanation = '${map['explanation'] ?? map['summary'] ?? ''}'.trim();
  return <String>[
    if (intro.isNotEmpty) intro,
    if (explanation.isNotEmpty) explanation,
    ...asStringList(map['importantPoints']),
    ...asStringList(map['concepts']),
    ...asStringList(map['important_facts']),
    ...asStringList(map['mpsc_points']),
    ...asStringList(map['revision_points']),
    ...asStringList(map['revision']),
  ];
}

LessonPremiumExtras _premiumFromLessonMap(
  Map<String, dynamic> map,
  LessonPremiumExtras base,
) {
  final top = LessonPremiumExtras.fromMap(map);
  return LessonPremiumExtras(
    pyqInsight: base.pyqInsight.isNotEmpty ? base.pyqInsight : top.pyqInsight,
    examTips: base.examTips.isNotEmpty ? base.examTips : top.examTips,
    commonMistakes:
        base.commonMistakes.isNotEmpty ? base.commonMistakes : top.commonMistakes,
    memoryTricks:
        base.memoryTricks.isNotEmpty ? base.memoryTricks : top.memoryTricks,
    importantFacts:
        base.importantFacts.isNotEmpty ? base.importantFacts : top.importantFacts,
    examTraps: base.examTraps.isNotEmpty ? base.examTraps : top.examTraps,
    onePageSummary: base.onePageSummary.trim().isNotEmpty
        ? base.onePageSummary
        : top.onePageSummary,
    quickRevision: base.quickRevision.trim().isNotEmpty
        ? base.quickRevision
        : top.quickRevision,
    introduction: base.introduction.trim().isNotEmpty
        ? base.introduction
        : top.introduction,
    mainConcepts:
        base.mainConcepts.isNotEmpty ? base.mainConcepts : top.mainConcepts,
    factBox: base.factBox.trim().isNotEmpty ? base.factBox : top.factBox,
    pyqConnection: base.pyqConnection.trim().isNotEmpty
        ? base.pyqConnection
        : top.pyqConnection,
    examples: base.examples.isNotEmpty ? base.examples : top.examples,
  );
}

bool isPlaceholderLesson(GeneratedLesson lesson, {String topic = ''}) {
  final blob = [
    lesson.summary,
    lesson.topicName,
    ...lesson.notes,
    ...lesson.slides.map((s) => '${s.title} ${s.narration} ${s.bullets.join(' ')}'),
  ].join(' ').toLowerCase();
  if (blob.contains('मॉक') ||
      blob.contains('mock lesson') ||
      blob.contains('ai_api_key') ||
      blob.contains('खऱ्या gemini')) {
    return true;
  }
  final asked = topic.trim();
  if (asked.isEmpty) return false;
  final hay = [
    lesson.question,
    lesson.topicName,
    lesson.summary,
    ...lesson.notes,
    ...lesson.script,
    ...lesson.slides.map((s) => '${s.title} ${s.narration} ${s.bullets.join(' ')}'),
  ].join(' ');
  final hayLower = hay.toLowerCase();
  final askedLower = asked.toLowerCase();
  if (hay.contains(asked) || hayLower.contains(askedLower)) {
    return false;
  }
  for (final alias in topicMatchAliases(asked)) {
    if (alias.isEmpty) continue;
    if (hay.contains(alias) || hayLower.contains(alias.toLowerCase())) {
      return false;
    }
  }
  final tokens = asked
      .split(RegExp(r'\s+'))
      .where((t) => t.trim().length >= 2);
  final tokenHit = tokens.any(
    (t) => hay.contains(t) || hayLower.contains(t.toLowerCase()),
  );
  return !tokenHit;
}

/// Romanization / bilingual aliases so "sansad" matches a संसद lesson.
List<String> topicMatchAliases(String topic) {
  final key = topic.trim().toLowerCase();
  const map = <String, List<String>>{
    'sansad': ['संसद', 'parliament', 'sansad', 'लोकसभा', 'राज्यसभा'],
    'संसद': ['संसद', 'parliament', 'sansad'],
    'parliament': ['संसद', 'parliament', 'sansad'],
    'monsoon': ['मान्सून', 'monsoon'],
    'मान्सून': ['मान्सून', 'monsoon'],
    'mansoon': ['मान्सून', 'monsoon'],
    'महागाई': ['महागाई', 'inflation'],
    'inflation': ['महागाई', 'inflation', 'चलनवाढ'],
  };
  return map[key] ?? const [];
}

/// Canonical 8-scene MPSC classroom sample (संसद). Used as the empty-state
/// demo and as the teaching-sequence / quiz regression contract.
final GeneratedLesson welcomeLesson = GeneratedLesson(
  question: 'भारतीय संसद म्हणजे काय?',
  topicName: 'भारतीय संसद',
  subjectName: 'राज्यव्यवस्था',
  createdAt: DateTime(2026, 1, 1),
  script: const [
    'नमस्कार. आज भारतीय संसद शिकूया.',
    'संसद ही भारताचे केंद्रीय विधिमंडळ आहे.',
    'उदाहरणार्थ अर्थसंकल्प प्रथम लोकसभेत येतो.',
    'रा लो रा — राष्ट्रपती, लोकसभा, राज्यसभा.',
    'मागील प्रश्नपत्रिकांमध्ये हा फरक वारंवार येतो.',
    'संसदेचे तीन भाग कोणते?',
    'विधिमंडळ आणि दोन सभागृहे आठवा.',
    'समारोप — संकल्पना पक्की करा.',
  ],
  slides: const [
    GeneratedSlide(
      title: 'भारतीय संसद',
      bullets: ['आजचा विषय', 'MPSC महत्त्व', 'तीन भाग'],
      sceneType: LessonSceneType.title,
      visualType: SlideVisualType.icons,
      iconLabels: ['अभिवादन', 'संसद', 'MPSC'],
      keywords: ['संसद'],
      narration:
          'नमस्कार विद्यार्थी मित्रांनो. आज आपण भारतीय संसद शिकणार आहोत. '
          'MPSC Combine मध्ये हा विषय वारंवार येतो.',
    ),
    GeneratedSlide(
      title: 'मूलभूत संकल्पना',
      bullets: ['केंद्रीय विधिमंडळ', 'अनुच्छेद ७९', 'तीन अंगे'],
      sceneType: LessonSceneType.introduction,
      visualType: SlideVisualType.whiteboard,
      keywords: ['विधिमंडळ', 'अनुच्छेद'],
      narration:
          'संसद म्हणजे भारताचे केंद्रीय विधिमंडळ. अनुच्छेद ७९ नुसार तिच्यात '
          'राष्ट्रपती, लोकसभा आणि राज्यसभा येतात. फक्त सभागृह नाही — तीनही अंगे मिळून संसद.',
    ),
    GeneratedSlide(
      title: 'सविस्तर स्पष्टीकरण',
      bullets: ['लोकसभा', 'राज्यसभा', 'राष्ट्रपती'],
      sceneType: LessonSceneType.mainExplanation,
      visualType: SlideVisualType.table,
      tableHeaders: ['अंग', 'ओळख'],
      tableRows: [
        ['लोकसभा', 'थेट निवड'],
        ['राज्यसभा', 'स्थायी सभागृह'],
        ['राष्ट्रपती', 'संसदेचा भाग'],
      ],
      keywords: ['लोकसभा', 'राज्यसभा'],
      narration:
          'लोकसभा थेट निवडणुकीने येते, राज्यसभा स्थायी आहे, आणि राष्ट्रपती संसदेचा '
          'अविभाज्य भाग आहे. परीक्षा या तीन फरकांवरच विचारते.',
      sectionQuestion: GeneratedMcq(
        question: 'संसदेत कोणते तीन भाग येतात?',
        options: [
          'राष्ट्रपती, लोकसभा, राज्यसभा',
          'फक्त लोकसभा',
          'सुप्रीम कोर्ट',
          'मंत्रिमंडळ',
        ],
        correctIndex: 0,
        explanation: 'अनुच्छेद ७९ नुसार संसदेत राष्ट्रपती, लोकसभा व राज्यसभा येतात.',
      ),
    ),
    GeneratedSlide(
      title: 'उदाहरण',
      bullets: ['अर्थसंकल्प', 'लोकसभा प्रथम', 'मनी बिल'],
      sceneType: LessonSceneType.examples,
      narration:
          'उदाहरणार्थ, अर्थसंकल्प आणि मनी बिल प्रथम लोकसभेत मांडले जातात. '
          'हे फरक Prelims मध्ये थेट विचारले जातात.',
    ),
    GeneratedSlide(
      title: 'आकृती',
      bullets: ['विधेयक', 'दोन्ही सभागृहे', 'राष्ट्रपती'],
      sceneType: LessonSceneType.diagram,
      visualType: SlideVisualType.flowchart,
      flowchart: [
        FlowNode(id: '1', label: 'विधेयक', nextIds: ['2']),
        FlowNode(id: '2', label: 'सभागृहे', nextIds: ['3']),
        FlowNode(id: '3', label: 'मान्यता', nextIds: []),
      ],
      narration:
          'कायदा प्रक्रिया अशी: विधेयक सभागृहात येते, दोन्ही सभागृहे पास करतात, '
          'मग राष्ट्रपतींची मान्यता. बोर्ड ही पायरी दाखवेल — मी संकल्पना समजावेन.',
    ),
    GeneratedSlide(
      title: 'PYQ स्पष्टीकरण',
      bullets: ['व्याख्या व फरक', 'अनुच्छेद ७९', 'सामान्य चूक'],
      sceneType: LessonSceneType.importantPoints,
      keywords: ['PYQ', 'अनुच्छेद'],
      narration:
          'मागील प्रश्नपत्रिकांमध्ये संसदेची व्याख्या आणि लोकसभा-राज्यसभा फरक '
          'वारंवार येतो. विद्यार्थी राष्ट्रपतीला संसदेबाहेर समजतात — ती चूक टाळा.',
    ),
    GeneratedSlide(
      title: 'सराव MCQ',
      bullets: ['पाच प्रश्न', 'स्पष्टीकरणासह'],
      sceneType: LessonSceneType.quiz,
      narration:
          'आता पाच सराव प्रश्न सोडवूया. प्रत्येक उत्तरामागचे कारण मनात बांधा.',
    ),
    GeneratedSlide(
      title: 'पुनरावलोकन',
      bullets: ['तीन अंगे', 'लोकसभा प्रथम', 'अनुच्छेद ७९'],
      sceneType: LessonSceneType.summary,
      narration:
          'थोडक्यात: संसद म्हणजे राष्ट्रपती अधिक दोन सभागृहे. अर्थसंकल्प लोकसभेत '
          'प्रथम येतो. अनुच्छेद ७९ ही व्याख्या आठवा.',
    ),
  ],
  summary:
      'भारतीय संसद = राष्ट्रपती + लोकसभा + राज्यसभा. अर्थसंकल्प लोकसभेत प्रथम.',
  mcqs: const [
    GeneratedMcq(
      question: 'भारतीय संसदेत कोणते तीन भाग येतात?',
      options: [
        'राष्ट्रपती, लोकसभा, राज्यसभा',
        'फक्त लोकसभा व राज्यसभा',
        'मंत्रिमंडळ व न्यायालय',
        'राज्यपाल व विधानसभा',
      ],
      correctIndex: 0,
      explanation: 'अनुच्छेद ७९ नुसार संसदेत राष्ट्रपती, लोकसभा आणि राज्यसभा येतात.',
      wrongExplanations: {
        '1': 'राष्ट्रपती संसदेचा भाग आहे, केवळ दोन सभागृहे नाहीत.',
        '2': 'मंत्रिमंडळ व न्यायालय संसद नाहीत.',
        '3': 'ही राज्य स्तराची रचना आहे.',
      },
    ),
    GeneratedMcq(
      question: 'अर्थसंकल्प प्रथम कोठे मांडला जातो?',
      options: ['लोकसभा', 'राज्यसभा', 'सुप्रीम कोर्ट', 'निवडणूक आयोग'],
      correctIndex: 0,
      explanation: 'मनी बिल व अर्थसंकल्प प्रथम लोकसभेत मांडले जातात.',
    ),
    GeneratedMcq(
      question: 'संसदेची रचना कोणत्या अनुच्छेदात आहे?',
      options: ['७९', '५२', '३५६', '२१'],
      correctIndex: 0,
      explanation: 'अनुच्छेद ७९ संसदेची रचना सांगतो.',
    ),
    GeneratedMcq(
      question: 'राज्यसभा कोणत्या प्रकारचे सभागृह आहे?',
      options: ['स्थायी', 'पाच वर्षांचे', 'तात्पुरते', 'नियुक्त नाही'],
      correctIndex: 0,
      explanation: 'राज्यसभा स्थायी सभागृह आहे; ती पूर्णपणे विसर्जित होत नाही.',
    ),
    GeneratedMcq(
      question: 'राष्ट्रपती संसदेचा भाग आहे का?',
      options: ['होय', 'नाही', 'फक्त युद्धात', 'फक्त अर्थसंकल्पात'],
      correctIndex: 0,
      explanation: 'होय. अनुच्छेद ७९ नुसार राष्ट्रपती संसदेचा भाग आहे.',
    ),
  ],
  notes: const [
    'संसद = राष्ट्रपती + लोकसभा + राज्यसभा',
    'अनुच्छेद ७९ — रचना',
    'अर्थसंकल्प लोकसभेत प्रथम',
    'राज्यसभा स्थायी सभागृह',
    'लोकसभा थेट निवड',
  ],
  premium: const LessonPremiumExtras(
    importantFacts: [
      'अनुच्छेद ७९ संसदेची रचना सांगतो.',
      'राष्ट्रपती संसदेचा भाग आहे.',
      'अर्थसंकल्प प्रथम लोकसभेत येतो.',
    ],
    examTips: ['व्याख्या व फरक एकत्र बांधा — तीन अंगे विसरू नका.'],
    memoryTricks: ['रा + लो + रा — राष्ट्रपती, लोकसभा, राज्यसभा.'],
    pyqInsight: [
      'मागील वर्षी संसदेची व्याख्या व लोकसभा-राज्यसभा फरक थेट विचारले गेले.',
    ],
    commonMistakes: ['राष्ट्रपतीला संसदेबाहेर समजणे.'],
    onePageSummary:
        'संसद म्हणजे केंद्रीय विधिमंडळ: राष्ट्रपती, लोकसभा, राज्यसभा.',
    quickRevision: '७९ · तीन अंगे · अर्थसंकल्प लोकसभा · राज्यसभा स्थायी.',
  ),
);

