import 'package:mpsc_combine_ai/rag/rag_text.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Stable id for the default MPSC Combine exam document at `exams/{id}`.
const String kDefaultExamId = 'mpsc_combine';

/// Group B Combined (Prelims + Mains) — separate from [kDefaultExamId].
const String kGroupBCombinedExamId = 'mpsc_group_b_combined';
const String kExamStagePrelims = 'prelims';
const String kExamStageMains = 'mains';
const String kGroupBPaperGat = 'general_ability_test';
const String kGroupBPaper1 = 'paper1';
const String kGroupBPaper2 = 'paper2';

const String kGroupBSubjectPrelimsGatId =
    'mpsc_group_b_prelims_general_ability_test';
const String kGroupBSubjectMainsMarathiId = 'mpsc_group_b_mains_paper1_marathi';
const String kGroupBSubjectMainsEnglishId = 'mpsc_group_b_mains_paper1_english';
const String kGroupBSubjectMainsGsId = 'mpsc_group_b_mains_paper2_gs';

/// Canonical Student Group B Combined subjects (Prelims GAT + Mains).
const List<String> kGroupBCombinedSubjectIds = [
  kGroupBSubjectPrelimsGatId,
  kGroupBSubjectMainsMarathiId,
  kGroupBSubjectMainsEnglishId,
  kGroupBSubjectMainsGsId,
];

bool isGroupBCombinedSubjectId(String id) =>
    kGroupBCombinedSubjectIds.contains(id);

/// Resolves exam id for notes / RAG chunks when the stored exam id is missing.
/// Group B Combined subjects never fall back to [kDefaultExamId].
String resolvedContentExamId({
  required String examId,
  required String subjectId,
}) {
  if (examId.isNotEmpty) return examId;
  if (isGroupBCombinedSubjectId(subjectId)) return kGroupBCombinedExamId;
  return kDefaultExamId;
}

/// Stage on an exam document (`prelims` / `mains`). Not a Firestore collection.
class ExamStageSpec {
  const ExamStageSpec({
    required this.id,
    required this.title,
    this.order = 0,
  });

  final String id;
  final String title;
  final int order;

  factory ExamStageSpec.fromMap(Map<String, dynamic> map) {
    return ExamStageSpec(
      id: '${map['id'] ?? ''}'.trim(),
      title: '${map['title'] ?? map['name'] ?? ''}'.trim(),
      order: asInt(map['order']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'order': order,
      };
}

/// Paper on an exam document. Optional marks/duration come from the exam plan.
class ExamPaperSpec {
  const ExamPaperSpec({
    required this.id,
    required this.title,
    required this.stageId,
    this.order = 0,
    this.questionCount = 0,
    this.marks = 0,
    this.durationMinutes = 0,
    this.medium = '',
    this.questionType = '',
  });

  final String id;
  final String title;
  final String stageId;
  final int order;
  final int questionCount;
  final int marks;
  final int durationMinutes;
  final String medium;
  final String questionType;

  factory ExamPaperSpec.fromMap(Map<String, dynamic> map) {
    return ExamPaperSpec(
      id: '${map['id'] ?? ''}'.trim(),
      title: '${map['title'] ?? map['name'] ?? ''}'.trim(),
      stageId: '${map['stageId'] ?? ''}'.trim(),
      order: asInt(map['order']),
      questionCount: asInt(map['questionCount']),
      marks: asInt(map['marks']),
      durationMinutes: asInt(map['durationMinutes']),
      medium: '${map['medium'] ?? ''}'.trim(),
      questionType: '${map['questionType'] ?? ''}'.trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'stageId': stageId,
      'order': order,
      if (questionCount > 0) 'questionCount': questionCount,
      if (marks > 0) 'marks': marks,
      if (durationMinutes > 0) 'durationMinutes': durationMinutes,
      if (medium.isNotEmpty) 'medium': medium,
      if (questionType.isNotEmpty) 'questionType': questionType,
    };
  }
}

/// Recruitment post (ASO / STI / PSI…). Metadata only — not a subject.
class ExamPostSpec {
  const ExamPostSpec({
    required this.id,
    required this.title,
    this.extraStages = const [],
  });

  final String id;
  final String title;
  final List<String> extraStages;

  factory ExamPostSpec.fromMap(Map<String, dynamic> map) {
    return ExamPostSpec(
      id: '${map['id'] ?? ''}'.trim(),
      title: '${map['title'] ?? map['name'] ?? ''}'.trim(),
      extraStages: asStringList(map['extraStages']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        if (extraStages.isNotEmpty) 'extraStages': extraStages,
      };
}

/// An exam at the top of the content index:
/// Exam → Subject → Chapter → Topic → Sub-topic.
///
/// Stored in Firestore at `exams/{examId}`. Subjects, chapters, notes, and
/// RAG sources reuse this id via `examId`.
class ExamItem {
  const ExamItem({
    required this.id,
    required this.title,
    this.titleEn = '',
    this.order = 0,
    this.published = true,
    this.updatedAt,
    this.stages = const [],
    this.papers = const [],
    this.posts = const [],
  });

  final String id;
  final String title;
  final String titleEn;
  final int order;
  final bool published;
  final DateTime? updatedAt;
  final List<ExamStageSpec> stages;
  final List<ExamPaperSpec> papers;
  final List<ExamPostSpec> posts;

  factory ExamItem.mpscCombine() {
    return const ExamItem(
      id: kDefaultExamId,
      title: kMpscDefaultExam,
      titleEn: 'MPSC Combine',
      order: 0,
      published: true,
    );
  }

  factory ExamItem.groupBCombined() {
    return const ExamItem(
      id: kGroupBCombinedExamId,
      title: 'MPSC Group B Combined Examination',
      titleEn: 'MPSC Group B Combined Examination',
      order: 1,
      published: true,
      stages: [
        ExamStageSpec(
          id: kExamStagePrelims,
          title: 'Preliminary Examination',
          order: 0,
        ),
        ExamStageSpec(
          id: kExamStageMains,
          title: 'Main Examination',
          order: 1,
        ),
      ],
      papers: [
        ExamPaperSpec(
          id: kGroupBPaperGat,
          title: 'General Ability Test',
          stageId: kExamStagePrelims,
          order: 0,
          questionCount: 100,
          marks: 100,
          durationMinutes: 60,
          medium: 'Marathi and English',
          questionType: 'objective_mcq',
        ),
        ExamPaperSpec(
          id: kGroupBPaper1,
          title: 'Paper 1 — Common',
          stageId: kExamStageMains,
          order: 1,
        ),
        ExamPaperSpec(
          id: kGroupBPaper2,
          title: 'Paper 2 — General Studies / General Ability & Intelligence',
          stageId: kExamStageMains,
          order: 2,
        ),
      ],
      posts: [
        ExamPostSpec(
          id: 'aso',
          title: 'Assistant Section Officer (ASO)',
        ),
        ExamPostSpec(
          id: 'sti',
          title: 'State Tax Inspector (STI)',
        ),
        ExamPostSpec(
          id: 'deputy_registrar',
          title: 'Deputy Registrar',
        ),
        ExamPostSpec(
          id: 'psi',
          title: 'Police Sub-Inspector (PSI)',
          extraStages: [
            'written_examination',
            'physical_test',
            'interview',
          ],
        ),
      ],
    );
  }

  factory ExamItem.fromMap(Map<String, dynamic> map, String id) {
    final rawTitle = map['title'] ?? map['name'] ?? map['nameEn'];
    final title = rawTitle is String ? rawTitle.trim() : '';
    return ExamItem(
      id: id,
      title: title.isNotEmpty ? title : kMpscDefaultExam,
      titleEn: map['titleEn'] as String? ?? '',
      order: asInt(map['order']),
      published: asBool(map['published'], defaultValue: true),
      updatedAt: _parseUpdatedAt(map['updatedAt']),
      stages: [
        for (final m in asMapList(map['stages'])) ExamStageSpec.fromMap(m),
      ].where((s) => s.id.isNotEmpty).toList(),
      papers: [
        for (final m in asMapList(map['papers'])) ExamPaperSpec.fromMap(m),
      ].where((p) => p.id.isNotEmpty).toList(),
      posts: [
        for (final m in asMapList(map['posts'])) ExamPostSpec.fromMap(m),
      ].where((p) => p.id.isNotEmpty).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'titleEn': titleEn,
      'order': order,
      'published': published,
      'updatedAt': DateTime.now().toIso8601String(),
      if (stages.isNotEmpty)
        'stages': [for (final s in stages) s.toMap()],
      if (papers.isNotEmpty)
        'papers': [for (final p in papers) p.toMap()],
      if (posts.isNotEmpty) 'posts': [for (final p in posts) p.toMap()],
    };
  }

  ExamItem copyWith({
    String? title,
    String? titleEn,
    int? order,
    bool? published,
    DateTime? updatedAt,
    List<ExamStageSpec>? stages,
    List<ExamPaperSpec>? papers,
    List<ExamPostSpec>? posts,
  }) {
    return ExamItem(
      id: id,
      title: title ?? this.title,
      titleEn: titleEn ?? this.titleEn,
      order: order ?? this.order,
      published: published ?? this.published,
      updatedAt: updatedAt ?? this.updatedAt,
      stages: stages ?? this.stages,
      papers: papers ?? this.papers,
      posts: posts ?? this.posts,
    );
  }
}

DateTime? _parseUpdatedAt(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
