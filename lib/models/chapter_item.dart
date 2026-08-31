import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// A chapter/topic within a subject, stored in Firestore at `chapters/{id}`.
///
/// The same collection holds the content-index tree:
/// - [ContentNodeType.chapter] — grouping node under a subject
/// - [ContentNodeType.topic] / [ContentNodeType.subtopic] — child via
///   [parentChapterId]
///
/// Legacy seed rows have empty [nodeType] / [parentChapterId] and remain
/// student-visible leaves (treated as topics).
class ChapterItem {
  const ChapterItem({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.order,
    this.estimatedStudyMinutes = 0,
    this.description = '',
    this.slug = '',
    this.titleEn = '',
    this.examId = kDefaultExamId,
    this.parentChapterId = '',
    this.nodeType = '',
    this.published = true,
    this.tags = const [],
    this.thumbnailUrl = '',
    this.pdfUrl = '',
    this.aiSummary = '',
    this.revisionNotes = '',
    this.classroomLessonId = '',
    this.updatedAt,
  });

  final String id;
  final String subjectId;

  /// Primary display title (Marathi). Also written as `titleMr`.
  final String title;
  final int order;

  /// Estimated time (in minutes) to study this chapter, shown to students
  /// as a study-planning hint. `0` means "not set".
  final int estimatedStudyMinutes;

  /// Short description shown under the chapter title in the student app.
  final String description;

  /// Stable slug for idempotent seeding (e.g. `rajyashastra-प्रस्तावना`).
  final String slug;

  final String titleEn;
  final String examId;

  /// Parent `chapters/{id}` for topics / sub-topics. Empty = root chapter
  /// (or a legacy leaf that students already see).
  final String parentChapterId;

  /// `chapter` | `topic` | `subtopic`. Empty = legacy leaf topic.
  final String nodeType;

  final bool published;
  final List<String> tags;
  final String thumbnailUrl;

  /// Convenience primary PDF URL (also mirrored in note attachments).
  final String pdfUrl;

  /// AI-generated summary (Admin "Generate AI Summary").
  final String aiSummary;

  /// Short revision text shown in revision hub / topic detail.
  final String revisionNotes;

  /// Optional link to `aiTeacherContent/{id}` or classroom lesson cache key.
  final String classroomLessonId;

  final DateTime? updatedAt;

  String get titleMr => title;

  ContentNodeType get contentNodeType => contentNodeTypeFromString(nodeType);

  /// Grouping chapter in the admin tree — hidden from the student topic list.
  bool get isGroupingChapter =>
      nodeType.trim().toLowerCase() == 'chapter';

  /// Student-facing leaf (legacy empty type, topic, or sub-topic).
  bool get isStudentLeaf => published && !isGroupingChapter;

  /// When this row is a topic, its id is [topicId].
  String get topicId => id;

  /// Chapter/topic outline text for syllabus RAG (not the notes PDF body).
  String get searchableText {
    final buf = StringBuffer();
    if (title.trim().isNotEmpty) buf.writeln(title.trim());
    if (titleEn.trim().isNotEmpty) buf.writeln(titleEn.trim());
    if (description.trim().isNotEmpty) buf.writeln(description.trim());
    if (aiSummary.trim().isNotEmpty) buf.writeln(aiSummary.trim());
    if (revisionNotes.trim().isNotEmpty) buf.writeln(revisionNotes.trim());
    for (final tag in tags) {
      if (tag.trim().isNotEmpty) buf.writeln(tag.trim());
    }
    return buf.toString();
  }

  factory ChapterItem.fromMap(Map<String, dynamic> map, String id) {
    final rawTitle = map['title'] ?? map['titleMr'] ?? map['name'];
    final title = rawTitle is String ? rawTitle.trim() : '';
    final titleMr = (map['titleMr'] as String?)?.trim() ?? '';
    return ChapterItem(
      id: id,
      subjectId: map['subjectId'] as String? ?? '',
      title: title.isNotEmpty ? title : titleMr,
      order: asInt(map['order']),
      estimatedStudyMinutes: asInt(map['estimatedStudyMinutes']),
      description: map['description'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
      titleEn: map['titleEn'] as String? ?? '',
      examId: (map['examId'] as String?)?.trim().isNotEmpty == true
          ? (map['examId'] as String).trim()
          : kDefaultExamId,
      parentChapterId: map['parentChapterId'] as String? ?? '',
      nodeType: map['nodeType'] as String? ?? '',
      published: asBool(map['published'], defaultValue: true),
      tags: asStringList(map['tags']),
      thumbnailUrl: map['thumbnailUrl'] as String? ?? '',
      pdfUrl: map['pdfUrl'] as String? ?? '',
      aiSummary: map['aiSummary'] as String? ?? '',
      revisionNotes: map['revisionNotes'] as String? ?? '',
      classroomLessonId: map['classroomLessonId'] as String? ?? '',
      updatedAt: _parseUpdatedAt(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    final now = DateTime.now().toIso8601String();
    return {
      'subjectId': subjectId,
      'title': title,
      'titleMr': title,
      'titleEn': titleEn,
      'order': order,
      'estimatedStudyMinutes': estimatedStudyMinutes,
      'description': description,
      'slug': slug,
      'examId': examId.isEmpty ? kDefaultExamId : examId,
      'parentChapterId': parentChapterId,
      'nodeType': nodeType,
      'published': published,
      'tags': tags,
      'thumbnailUrl': thumbnailUrl,
      'pdfUrl': pdfUrl,
      'aiSummary': aiSummary,
      'revisionNotes': revisionNotes,
      'classroomLessonId': classroomLessonId,
      'updatedAt': now,
    };
  }

  ChapterItem copyWith({
    String? title,
    int? order,
    int? estimatedStudyMinutes,
    String? description,
    String? slug,
    String? titleEn,
    String? examId,
    String? parentChapterId,
    String? nodeType,
    bool? published,
    List<String>? tags,
    String? thumbnailUrl,
    String? pdfUrl,
    String? aiSummary,
    String? revisionNotes,
    String? classroomLessonId,
    DateTime? updatedAt,
  }) {
    return ChapterItem(
      id: id,
      subjectId: subjectId,
      title: title ?? this.title,
      order: order ?? this.order,
      estimatedStudyMinutes: estimatedStudyMinutes ?? this.estimatedStudyMinutes,
      description: description ?? this.description,
      slug: slug ?? this.slug,
      titleEn: titleEn ?? this.titleEn,
      examId: examId ?? this.examId,
      parentChapterId: parentChapterId ?? this.parentChapterId,
      nodeType: nodeType ?? this.nodeType,
      published: published ?? this.published,
      tags: tags ?? this.tags,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      aiSummary: aiSummary ?? this.aiSummary,
      revisionNotes: revisionNotes ?? this.revisionNotes,
      classroomLessonId: classroomLessonId ?? this.classroomLessonId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

DateTime? _parseUpdatedAt(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
