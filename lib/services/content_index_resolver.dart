import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';

/// Resolved Content Index ids for one bulk-import / form row.
class ResolvedContentIndex {
  const ResolvedContentIndex({
    required this.examId,
    required this.subjectId,
    required this.chapterId,
    required this.topicId,
    this.subjectTitle = '',
    this.chapterTitle = '',
    this.topicTitle = '',
    this.errors = const [],
  });

  final String examId;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final String subjectTitle;
  final String chapterTitle;
  final String topicTitle;
  final List<String> errors;

  bool get isValid =>
      errors.isEmpty &&
      subjectId.isNotEmpty &&
      chapterId.isNotEmpty &&
      topicId.isNotEmpty;
}

/// Maps exam / subject / chapter / topic *names* onto the Part 1 index
/// (`exams` / `subjects` / `chapters`). Does not create a second tree.
class ContentIndexResolver {
  ContentIndexResolver({
    required this.exams,
    required this.subjects,
    required this.chapters,
  });

  final List<ExamItem> exams;
  final List<SubjectItem> subjects;
  final List<ChapterItem> chapters;

  static Future<ContentIndexResolver> load(NotesRepository notes) async {
    await notes.ensureDefaultExam();
    final exams = await notes.getExamsOnce();
    final subjects = await notes.getSubjectsOnce();
    final chapters = await notes.getAllChaptersOnce();
    return ContentIndexResolver(
      exams: exams.isEmpty ? [ExamItem.mpscCombine()] : exams,
      subjects: subjects,
      chapters: chapters,
    );
  }

  static bool isAllowedExamLabel(String raw) {
    final t = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (t.contains('rajyaseva')) return false;
    if (t.isEmpty) return true;
    return t == 'mpsccombine' ||
        t.contains('combine') ||
        t == kDefaultExamId.replaceAll('_', '');
  }

  ResolvedContentIndex resolve({
    String exam = '',
    String subject = '',
    String chapter = '',
    String topic = '',
  }) {
    final errors = <String>[];
    if (exam.trim().isNotEmpty && !isAllowedExamLabel(exam)) {
      errors.add('Invalid exam (MPSC Combine only)');
    }

    final examId = _examIdFor(exam);
    final subjectItem = _matchSubject(subject, examId);
    if (subject.trim().isEmpty) {
      errors.add('Missing subject');
    } else if (subjectItem == null) {
      errors.add('Missing subject');
    }

    final subjectId = subjectItem?.id ?? '';
    ChapterItem? chapterItem;
    if (chapter.trim().isEmpty) {
      errors.add('Missing chapter');
    } else {
      chapterItem = _matchChapter(chapter, subjectId);
      if (chapterItem == null) errors.add('Missing chapter');
    }

    ChapterItem? topicItem;
    if (topic.trim().isEmpty) {
      errors.add('Missing topic');
    } else if (chapterItem != null) {
      topicItem = _matchTopic(topic, chapterItem);
      if (topicItem == null) errors.add('Missing topic');
    }

    return ResolvedContentIndex(
      examId: examId,
      subjectId: subjectId,
      chapterId: chapterItem?.id ?? '',
      topicId: topicItem?.id ?? '',
      subjectTitle: subjectItem?.title ?? subject.trim(),
      chapterTitle: chapterItem?.title ?? chapter.trim(),
      topicTitle: topicItem?.title ?? topic.trim(),
      errors: errors,
    );
  }

  String _examIdFor(String exam) {
    if (!isAllowedExamLabel(exam)) return kDefaultExamId;
    final needle = _norm(exam);
    if (needle.isEmpty) return kDefaultExamId;
    for (final e in exams) {
      if (_norm(e.id) == needle ||
          _norm(e.title) == needle ||
          _norm(e.titleEn) == needle) {
        return e.id;
      }
    }
    return kDefaultExamId;
  }

  SubjectItem? _matchSubject(String raw, String examId) {
    final needle = _norm(raw);
    if (needle.isEmpty) return null;
    final pool = subjects
        .where((s) => s.examId == examId || s.examId.isEmpty)
        .toList();
    for (final s in pool) {
      if (_norm(s.title) == needle ||
          _norm(s.nameEn) == needle ||
          _norm(s.slug) == needle) {
        return s;
      }
    }
    for (final s in pool) {
      final titles = [_norm(s.title), _norm(s.nameEn)];
      if (titles.any((t) => t.contains(needle) || needle.contains(t))) {
        return s;
      }
    }
    return null;
  }

  ChapterItem? _matchChapter(String raw, String subjectId) {
    final needle = _norm(raw);
    if (needle.isEmpty || subjectId.isEmpty) return null;
    final pool = chapters.where((c) => c.subjectId == subjectId).toList();
    final roots = pool.where((c) => c.parentChapterId.isEmpty).toList();
    final search = roots.isEmpty ? pool : roots;
    for (final c in search) {
      if (_titlesMatch(c, needle)) return c;
    }
    for (final c in pool) {
      if (_titlesMatch(c, needle)) return c;
    }
    return null;
  }

  ChapterItem? _matchTopic(String raw, ChapterItem chapter) {
    final needle = _norm(raw);
    if (needle.isEmpty) return null;
    if (_titlesMatch(chapter, needle)) return chapter;
    final children = chapters
        .where((c) => c.parentChapterId == chapter.id)
        .toList();
    for (final c in children) {
      if (_titlesMatch(c, needle)) return c;
    }
    for (final c in chapters.where((c) => c.subjectId == chapter.subjectId)) {
      if (_titlesMatch(c, needle)) return c;
    }
    return null;
  }

  bool _titlesMatch(ChapterItem c, String needle) {
    final titles = [_norm(c.title), _norm(c.titleEn), _norm(c.slug)];
    return titles.any((t) => t == needle || (t.isNotEmpty && (t.contains(needle) || needle.contains(t))));
  }

  static String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
