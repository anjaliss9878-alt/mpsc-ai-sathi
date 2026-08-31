import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Admin-authored AI Teacher lesson content, stored in Firestore at
/// `aiTeacherContent/{id}`.
///
/// This is deliberately shaped exactly like a Gemini-[GeneratedLesson] (same
/// slides/quiz/notes types) via [toGeneratedLesson], so the AI Teacher
/// Classroom pipeline can narrate an admin-authored lesson exactly the same
/// way it narrates a live Gemini-generated one — no UI or playback code
/// needs to know the difference. [keywords] is what the classroom matches
/// a student's question against before falling back to Gemini.
///
/// Legacy docs without [status] stay student-visible. New admin entries
/// default to Draft until reviewed. Generation jobs in `ai_lessons` are
/// unchanged.
class AiTeacherContentItem {
  const AiTeacherContentItem({
    required this.id,
    required this.lessonTitle,
    required this.subjectName,
    required this.summary,
    required this.keywords,
    required this.aiPrompt,
    required this.teachingScript,
    required this.slides,
    required this.quiz,
    required this.notes,
    required this.order,
    this.examId = kDefaultExamId,
    this.targetGroup = 'groupB',
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
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
  final String lessonTitle;
  final String subjectName;
  final String summary;

  /// Words/phrases a student's question is matched against (case-insensitive
  /// substring match) to decide whether this authored lesson answers it.
  final List<String> keywords;

  /// Optional prompt an admin can hand to an external AI tool while drafting
  /// this lesson — purely informational, never sent anywhere by the app.
  final String aiPrompt;

  final List<String> teachingScript;
  final List<GeneratedSlide> slides;
  final List<GeneratedMcq> quiz;
  final List<String> notes;
  final int order;

  final String examId;
  final String targetGroup;
  final String subjectId;
  final String chapterId;
  final String topicId;
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

  bool get isStudentVisible =>
      published && contentWorkflowIsStudentVisible(status);

  String get lessonContentText {
    final buf = StringBuffer()
      ..writeln(lessonTitle)
      ..writeln(summary)
      ..writeln(teachingScript.join('\n'))
      ..writeln(notes.join('\n'));
    for (final s in slides) {
      buf.writeln(s.title);
      buf.writeln(s.bullets.join('\n'));
    }
    return buf.toString();
  }

  bool matchesQuery(String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return true;
    return lessonTitle.toLowerCase().contains(q) ||
        summary.toLowerCase().contains(q) ||
        subjectName.toLowerCase().contains(q) ||
        topicId.toLowerCase().contains(q) ||
        keywords.any((k) => k.toLowerCase().contains(q));
  }

  factory AiTeacherContentItem.fromMap(Map<String, dynamic> map, String id) {
    final published = asBool(map['published'], defaultValue: true);
    final status = contentWorkflowStatusFromString(
      map['status'] as String?,
      published: published,
    );
    final target = (map['targetGroup'] as String?)?.trim().isNotEmpty == true
        ? (map['targetGroup'] as String).trim()
        : ((map['groupId'] as String?)?.trim() ?? '');
    return AiTeacherContentItem(
      id: id,
      lessonTitle: map['lessonTitle'] as String? ?? '',
      subjectName: map['subjectName'] as String? ?? '',
      summary: map['summary'] as String? ?? '',
      keywords: asStringList(map['keywords']),
      aiPrompt: map['aiPrompt'] as String? ?? '',
      teachingScript: asStringList(map['teachingScript']),
      slides: asMapList(map['slides']).map(GeneratedSlide.fromMap).toList(),
      quiz: asMapList(map['quiz']).map(GeneratedMcq.fromMap).toList(),
      notes: asStringList(map['notes']),
      order: (map['order'] as num?)?.toInt() ?? 0,
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
      'lessonTitle': lessonTitle,
      'subjectName': subjectName,
      'summary': summary,
      'keywords': keywords,
      'aiPrompt': aiPrompt,
      'teachingScript': teachingScript,
      'slides': slides.map((s) => s.toMap()).toList(),
      'quiz': quiz.map((q) => q.toMap()).toList(),
      'notes': notes,
      'order': order,
      'examId': examId.isEmpty ? kDefaultExamId : examId,
      'targetGroup': group,
      'groupId': group,
      'subjectId': subjectId,
      'chapterId': chapterId,
      'topicId': topicId,
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

  AiTeacherContentItem copyWith({
    NoteWorkflowStatus? status,
    bool? published,
  }) {
    final next = status ?? this.status;
    return AiTeacherContentItem(
      id: id,
      lessonTitle: lessonTitle,
      subjectName: subjectName,
      summary: summary,
      keywords: keywords,
      aiPrompt: aiPrompt,
      teachingScript: teachingScript,
      slides: slides,
      quiz: quiz,
      notes: notes,
      order: order,
      examId: examId,
      targetGroup: targetGroup,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
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

  GeneratedLesson toGeneratedLesson({required String question}) {
    return GeneratedLesson(
      question: question,
      topicName: lessonTitle,
      subjectName: subjectName,
      script: teachingScript,
      slides: slides,
      summary: summary,
      mcqs: quiz,
      notes: notes,
      createdAt: DateTime.now(),
    );
  }
}
