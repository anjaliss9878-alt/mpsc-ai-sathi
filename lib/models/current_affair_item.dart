import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// A current affairs entry, stored in Firestore at `currentAffairs/{id}`.
///
/// Legacy docs without [status] stay student-visible (published). New admin
/// entries default to Draft until reviewed.
class CurrentAffairItem {
  const CurrentAffairItem({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.date,
    this.pdfUrl = '',
    this.monthlyPdfUrl = '',
    this.quizQuestion = '',
    this.quizOptions = const [],
    this.quizCorrectIndex = 0,
    this.examId = kDefaultExamId,
    this.targetGroup = 'both',
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
    this.detailedExplanation = '',
    this.source = '',
    this.tags = const [],
    this.language = 'mr',
    this.published = true,
    this.status = NoteWorkflowStatus.published,
    this.createdAt,
    this.updatedAt,
    this.videoUrl = '',
    this.audioUrl = '',
    this.transcriptUrl = '',
    this.thumbnailUrl = '',
    this.videoStatus = kVideoStatusNone,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final DateTime date;

  /// Optional daily CA PDF (Storage / external).
  final String pdfUrl;

  /// Optional monthly digest PDF.
  final String monthlyPdfUrl;

  /// Optional quick quiz tied to this CA entry.
  final String quizQuestion;
  final List<String> quizOptions;
  final int quizCorrectIndex;

  final String examId;
  final String targetGroup;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final String detailedExplanation;
  final String source;
  final List<String> tags;
  final String language;
  final bool published;
  final NoteWorkflowStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String videoUrl;
  final String audioUrl;
  final String transcriptUrl;
  final String thumbnailUrl;
  final String videoStatus;

  bool get hasQuiz => quizQuestion.isNotEmpty && quizOptions.length >= 2;

  bool get isStudentVisible =>
      published && contentWorkflowIsStudentVisible(status);

  String get shortSummary => description;

  bool matchesQuery(String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q) ||
        detailedExplanation.toLowerCase().contains(q) ||
        category.toLowerCase().contains(q) ||
        topicId.toLowerCase().contains(q) ||
        tags.any((t) => t.toLowerCase().contains(q));
  }

  factory CurrentAffairItem.fromMap(Map<String, dynamic> map, String id) {
    final published = asBool(map['published'], defaultValue: true);
    final status = contentWorkflowStatusFromString(
      map['status'] as String?,
      published: published,
    );
    final target = (map['targetGroup'] as String?)?.trim().isNotEmpty == true
        ? (map['targetGroup'] as String).trim()
        : ((map['groupId'] as String?)?.trim() ?? 'both');
    return CurrentAffairItem(
      id: id,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ??
          map['shortSummary'] as String? ??
          '',
      category: map['category'] as String? ?? 'General',
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      pdfUrl: map['pdfUrl'] as String? ?? '',
      monthlyPdfUrl: map['monthlyPdfUrl'] as String? ?? '',
      quizQuestion: map['quizQuestion'] as String? ?? '',
      quizOptions: asStringList(map['quizOptions']),
      quizCorrectIndex: (map['quizCorrectIndex'] as num?)?.toInt() ?? 0,
      examId: (map['examId'] as String?)?.trim().isNotEmpty == true
          ? (map['examId'] as String).trim()
          : kDefaultExamId,
      targetGroup: targetGroupToString(targetGroupFromString(target)),
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      topicId: map['topicId'] as String? ?? '',
      detailedExplanation: map['detailedExplanation'] as String? ?? '',
      source: map['source'] as String? ?? '',
      tags: asStringList(map['tags']),
      language: map['language'] as String? ?? 'mr',
      published: published && contentWorkflowPublishedFlag(status),
      status: status,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? ''),
      videoUrl: map['videoUrl'] as String? ?? '',
      audioUrl: map['audioUrl'] as String? ?? '',
      transcriptUrl: map['transcriptUrl'] as String? ?? '',
      thumbnailUrl: map['thumbnailUrl'] as String? ?? '',
      videoStatus: map['videoStatus'] as String? ?? kVideoStatusNone,
    );
  }

  Map<String, dynamic> toMap() {
    final group = targetGroupToString(targetGroupFromString(targetGroup));
    final now = DateTime.now().toIso8601String();
    return {
      'title': title,
      'description': description,
      'shortSummary': description,
      'category': category,
      'date': date.toIso8601String(),
      'pdfUrl': pdfUrl,
      'monthlyPdfUrl': monthlyPdfUrl,
      'quizQuestion': quizQuestion,
      'quizOptions': quizOptions,
      'quizCorrectIndex': quizCorrectIndex,
      'examId': examId.isEmpty ? kDefaultExamId : examId,
      'targetGroup': group,
      'groupId': group,
      'subjectId': subjectId,
      'chapterId': chapterId,
      'topicId': topicId,
      'detailedExplanation': detailedExplanation,
      'source': source,
      'tags': tags,
      'language': language,
      'published': published && contentWorkflowPublishedFlag(status),
      'status': contentWorkflowStatusToString(status),
      'createdAt': createdAt?.toIso8601String() ?? now,
      'updatedAt': now,
      'videoUrl': videoUrl,
      'audioUrl': audioUrl,
      'transcriptUrl': transcriptUrl,
      'thumbnailUrl': thumbnailUrl,
      'videoStatus': videoStatus,
    };
  }

  CurrentAffairItem copyWith({NoteWorkflowStatus? status, bool? published}) {
    final next = status ?? this.status;
    return CurrentAffairItem(
      id: id,
      title: title,
      description: description,
      category: category,
      date: date,
      pdfUrl: pdfUrl,
      monthlyPdfUrl: monthlyPdfUrl,
      quizQuestion: quizQuestion,
      quizOptions: quizOptions,
      quizCorrectIndex: quizCorrectIndex,
      examId: examId,
      targetGroup: targetGroup,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      detailedExplanation: detailedExplanation,
      source: source,
      tags: tags,
      language: language,
      published: published ?? contentWorkflowPublishedFlag(next),
      status: next,
      createdAt: createdAt,
      videoUrl: videoUrl,
      audioUrl: audioUrl,
      transcriptUrl: transcriptUrl,
      thumbnailUrl: thumbnailUrl,
      videoStatus: videoStatus,
    );
  }
}
