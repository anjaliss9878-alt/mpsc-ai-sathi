import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Admin-authored memory trick at `smartTricks/{id}`.
class SmartTrickItem {
  const SmartTrickItem({
    required this.id,
    required this.title,
    required this.concept,
    required this.memoryTrick,
    this.explanation = '',
    this.example = '',
    this.tags = const [],
    this.examId = kDefaultExamId,
    this.targetGroup = 'groupB',
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
    this.language = 'mr',
    this.published = false,
    this.status = NoteWorkflowStatus.draft,
    this.order = 0,
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
  final String concept;
  final String memoryTrick;
  final String explanation;
  final String example;
  final List<String> tags;
  final String examId;
  final String targetGroup;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final String language;
  final bool published;
  final NoteWorkflowStatus status;
  final int order;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String videoUrl;
  final String audioUrl;
  final String transcriptUrl;
  final String thumbnailUrl;
  final String videoStatus;

  bool get isStudentVisible =>
      published && contentWorkflowIsStudentVisible(status);

  factory SmartTrickItem.fromMap(Map<String, dynamic> map, String id) {
    final published = asBool(map['published'], defaultValue: false);
    final status = contentWorkflowStatusFromString(
      map['status'] as String?,
      published: published,
    );
    final target = (map['targetGroup'] as String?)?.trim().isNotEmpty == true
        ? (map['targetGroup'] as String).trim()
        : ((map['groupId'] as String?)?.trim() ?? '');
    return SmartTrickItem(
      id: id,
      title: map['title'] as String? ?? '',
      concept: map['concept'] as String? ?? '',
      memoryTrick: map['memoryTrick'] as String? ?? map['trick'] as String? ?? '',
      explanation: map['explanation'] as String? ?? '',
      example: map['example'] as String? ?? '',
      tags: asStringList(map['tags']),
      examId: (map['examId'] as String?)?.trim().isNotEmpty == true
          ? (map['examId'] as String).trim()
          : kDefaultExamId,
      targetGroup: targetGroupToString(targetGroupFromString(target)),
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      topicId: map['topicId'] as String? ?? '',
      language: map['language'] as String? ?? 'mr',
      published: published && contentWorkflowPublishedFlag(status),
      status: status,
      order: asInt(map['order']),
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
      'concept': concept,
      'memoryTrick': memoryTrick,
      'explanation': explanation,
      'example': example,
      'tags': tags,
      'examId': examId.isEmpty ? kDefaultExamId : examId,
      'targetGroup': group,
      'groupId': group,
      'subjectId': subjectId,
      'chapterId': chapterId,
      'topicId': topicId,
      'language': language,
      'published': published && contentWorkflowPublishedFlag(status),
      'status': contentWorkflowStatusToString(status),
      'order': order,
      'createdAt': createdAt?.toIso8601String() ?? now,
      'updatedAt': now,
      'videoUrl': videoUrl,
      'audioUrl': audioUrl,
      'transcriptUrl': transcriptUrl,
      'thumbnailUrl': thumbnailUrl,
      'videoStatus': videoStatus,
    };
  }

  SmartTrickItem copyWith({NoteWorkflowStatus? status, bool? published}) {
    final next = status ?? this.status;
    return SmartTrickItem(
      id: id,
      title: title,
      concept: concept,
      memoryTrick: memoryTrick,
      explanation: explanation,
      example: example,
      tags: tags,
      examId: examId,
      targetGroup: targetGroup,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      language: language,
      published: published ?? contentWorkflowPublishedFlag(next),
      status: next,
      order: order,
      createdAt: createdAt,
      videoUrl: videoUrl,
      audioUrl: audioUrl,
      transcriptUrl: transcriptUrl,
      thumbnailUrl: thumbnailUrl,
      videoStatus: videoStatus,
    );
  }

  bool matchesQuery(String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        concept.toLowerCase().contains(q) ||
        memoryTrick.toLowerCase().contains(q) ||
        tags.any((t) => t.toLowerCase().contains(q));
  }
}
