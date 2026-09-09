import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/models/rag_study_pack.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Review state for a student-submitted study pack. Never auto-published.
enum StudyPackReviewStatus {
  pendingReview,
  savedAsDraft,
  dismissed,
}

StudyPackReviewStatus studyPackReviewStatusFromString(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'savedasdraft':
    case 'saved_as_draft':
    case 'draft':
      return StudyPackReviewStatus.savedAsDraft;
    case 'dismissed':
      return StudyPackReviewStatus.dismissed;
    default:
      return StudyPackReviewStatus.pendingReview;
  }
}

String studyPackReviewStatusToString(StudyPackReviewStatus status) {
  switch (status) {
    case StudyPackReviewStatus.pendingReview:
      return 'pendingReview';
    case StudyPackReviewStatus.savedAsDraft:
      return 'savedAsDraft';
    case StudyPackReviewStatus.dismissed:
      return 'dismissed';
  }
}

/// AI-generated study pack submitted for admin review (`studyPacks/{id}`).
class StudyContentPack {
  const StudyContentPack({
    required this.id,
    required this.uid,
    required this.topic,
    this.subjectTitle = '',
    this.subjectId = '',
    this.chapterId = '',
    this.examId = '',
    this.insufficient = false,
    this.detailedNotes = '',
    this.shortNotes = '',
    this.fiveMinuteRevision = '',
    this.importantFacts = const [],
    this.examPoints = const [],
    this.commonMistakes = const [],
    this.citations = const [],
    this.sourceIds = const [],
    this.status = StudyPackReviewStatus.pendingReview,
    this.published = false,
    this.noteId = '',
    this.createdAt,
  });

  final String id;
  final String uid;
  final String topic;
  final String subjectTitle;
  final String subjectId;
  final String chapterId;
  final String examId;
  final bool insufficient;
  final String detailedNotes;
  final String shortNotes;
  final String fiveMinuteRevision;
  final List<String> importantFacts;
  final List<String> examPoints;
  final List<String> commonMistakes;
  final List<RagCitation> citations;
  final List<String> sourceIds;
  final StudyPackReviewStatus status;

  /// Always false. Packs are never student-visible content.
  final bool published;
  final String noteId;
  final DateTime? createdAt;

  factory StudyContentPack.fromMap(Map<String, dynamic> map, String id) {
    DateTime? createdAt;
    final raw = map['createdAt'];
    if (raw is String && raw.isNotEmpty) {
      createdAt = DateTime.tryParse(raw);
    }
    return StudyContentPack(
      id: id,
      uid: map['uid'] as String? ?? '',
      topic: map['topic'] as String? ?? '',
      subjectTitle: map['subjectTitle'] as String? ?? '',
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      examId: map['examId'] as String? ?? '',
      insufficient: map['insufficient'] == true,
      detailedNotes: map['detailedNotes'] as String? ?? '',
      shortNotes: map['shortNotes'] as String? ?? '',
      fiveMinuteRevision: map['fiveMinuteRevision'] as String? ?? '',
      importantFacts: asStringList(map['importantFacts']),
      examPoints: asStringList(map['examPoints']),
      commonMistakes: asStringList(map['commonMistakes']),
      citations: asMapList(map['citations']).map(RagCitation.fromMap).toList(),
      sourceIds: asStringList(map['sourceIds']),
      status: studyPackReviewStatusFromString(map['status'] as String?),
      published: false,
      noteId: map['noteId'] as String? ?? '',
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'topic': topic,
      'subjectTitle': subjectTitle,
      'subjectId': subjectId,
      'chapterId': chapterId,
      'examId': examId,
      'insufficient': insufficient,
      'detailedNotes': detailedNotes,
      'shortNotes': shortNotes,
      'fiveMinuteRevision': fiveMinuteRevision,
      'importantFacts': importantFacts,
      'examPoints': examPoints,
      'commonMistakes': commonMistakes,
      'citations': citations.map((c) => c.toMap()).toList(),
      'sourceIds': sourceIds,
      'status': studyPackReviewStatusToString(status),
      'published': false,
      'noteId': noteId,
      'origin': 'ai-study-content',
      'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
    };
  }

  RagSourceSummary get asSummary => RagSourceSummary(
        detailed: detailedNotes,
        shortNotes: shortNotes,
        fiveMinuteRevision: fiveMinuteRevision,
        importantFacts: importantFacts,
        examPoints: examPoints,
        commonMistakes: commonMistakes,
        citations: citations,
      );
}
