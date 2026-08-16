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

  factory AiTeacherContentItem.fromMap(Map<String, dynamic> map, String id) {
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
    );
  }

  Map<String, dynamic> toMap() {
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
      'updatedAt': DateTime.now().toIso8601String(),
    };
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
