import 'package:mpsc_combine_ai/models/content_index.dart';

/// Logical Multi-RAG knowledge domain.
///
/// Domains are **filters** over the existing `ragSources` / `ragChunks`
/// collections — they are not separate Firebase projects or databases.
enum RagDomain {
  notes,
  pyq,
  syllabus,
  currentAffairs,
  aiTeacher,
  studentPerformance,
}

String ragDomainToString(RagDomain domain) {
  switch (domain) {
    case RagDomain.notes:
      return 'notes_rag';
    case RagDomain.pyq:
      return 'pyq_rag';
    case RagDomain.syllabus:
      return 'syllabus_rag';
    case RagDomain.currentAffairs:
      return 'current_affairs_rag';
    case RagDomain.aiTeacher:
      return 'ai_teacher_rag';
    case RagDomain.studentPerformance:
      return 'student_performance_rag';
  }
}

RagDomain? ragDomainFromString(String? value) {
  switch ((value ?? '').trim().toLowerCase().replaceAll('-', '_')) {
    case 'notes_rag':
    case 'notes':
    case 'note':
      return RagDomain.notes;
    case 'pyq_rag':
    case 'pyq':
    case 'pyqs':
      return RagDomain.pyq;
    case 'syllabus_rag':
    case 'syllabus':
      return RagDomain.syllabus;
    case 'current_affairs_rag':
    case 'currentaffairs_rag':
    case 'current_affairs':
    case 'currentaffairs':
      return RagDomain.currentAffairs;
    case 'ai_teacher_rag':
    case 'ai_teacher':
    case 'ai_lesson':
      return RagDomain.aiTeacher;
    case 'student_performance_rag':
    case 'student_performance':
    case 'performance':
      return RagDomain.studentPerformance;
    default:
      return null;
  }
}

String ragDomainLabel(RagDomain domain) {
  switch (domain) {
    case RagDomain.notes:
      return 'Notes';
    case RagDomain.pyq:
      return 'PYQs';
    case RagDomain.syllabus:
      return 'Syllabus';
    case RagDomain.currentAffairs:
      return 'Current Affairs';
    case RagDomain.aiTeacher:
      return 'AI Teacher';
    case RagDomain.studentPerformance:
      return 'Student Performance';
  }
}

/// Infers a domain from stored metadata so legacy chunks (no `ragDomain`
/// field) still route correctly without re-indexing.
RagDomain inferRagDomain({
  String ragDomain = '',
  String contentType = '',
  String sourceType = '',
  String linkedCollection = '',
}) {
  final explicit = ragDomainFromString(ragDomain);
  if (explicit != null) return explicit;

  final type = contentType.trim().toLowerCase();
  switch (type) {
    case kPyqContentType:
    case 'pyqs':
      return RagDomain.pyq;
    case kSyllabusContentType:
    case 'chapter':
    case 'chapter_material':
      return RagDomain.syllabus;
    case kCurrentAffairsContentType:
    case 'currentaffairs':
      return RagDomain.currentAffairs;
    case kAiLessonContentType:
    case 'ai_teacher':
      return RagDomain.aiTeacher;
    case kStudentPerformanceContentType:
      return RagDomain.studentPerformance;
    case kNotesPdfContentType:
    case kFlashcardContentType:
    case kSmartTrickContentType:
    case 'notes':
    case 'mpsc_notes':
      return RagDomain.notes;
  }

  final linked = linkedCollection.trim().toLowerCase();
  switch (linked) {
    case 'pyqs':
      return RagDomain.pyq;
    case 'chapters':
      return RagDomain.syllabus;
    case 'currentaffairs':
      return RagDomain.currentAffairs;
    case 'aiteachercontent':
    case 'ailessons':
      return RagDomain.aiTeacher;
    case 'notes':
    case 'flashcards':
    case 'smarttricks':
      return RagDomain.notes;
  }

  switch (sourceType.trim().toLowerCase()) {
    case 'pyq':
    case 'pyqs':
      return RagDomain.pyq;
    case 'chapter':
    case 'chapter_material':
    case 'chapter material':
      return RagDomain.syllabus;
    case 'currentaffairs':
    case 'current_affairs':
    case 'current affairs':
      return RagDomain.currentAffairs;
    default:
      return RagDomain.notes;
  }
}

/// True when [domains] is empty (no restriction) or contains [domain].
bool ragDomainIsAllowed(RagDomain domain, Iterable<RagDomain> domains) {
  if (domains.isEmpty) return true;
  return domains.contains(domain);
}

/// Content-type tags that belong to a domain. Used as a metadata filter on
/// the existing RAG corpus — never as a second collection name.
List<String> ragDomainContentTypes(RagDomain domain) {
  switch (domain) {
    case RagDomain.notes:
      return const [
        kNotesPdfContentType,
        kFlashcardContentType,
        kSmartTrickContentType,
        'notes',
      ];
    case RagDomain.pyq:
      return const [kPyqContentType, 'pyqs'];
    case RagDomain.syllabus:
      return const [kSyllabusContentType, 'chapter'];
    case RagDomain.currentAffairs:
      return const [kCurrentAffairsContentType];
    case RagDomain.aiTeacher:
      return const [kAiLessonContentType];
    case RagDomain.studentPerformance:
      return const [kStudentPerformanceContentType];
  }
}
