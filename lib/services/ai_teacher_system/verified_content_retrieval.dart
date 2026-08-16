import 'dart:typed_data';

import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/chapter_lesson_loader.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';

/// Thrown when a topic cannot be grounded in published Firestore notes.
class VerifiedContentException implements Exception {
  const VerifiedContentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One scored match of a student topic against published curriculum content.
class TopicMatchCandidate {
  const TopicMatchCandidate({
    required this.subject,
    required this.chapter,
    required this.score,
    this.note,
  });

  final SubjectItem subject;
  final ChapterItem chapter;
  final NoteItem? note;
  final double score;
}

/// Verified notes package for ANY dynamic topic (never invented facts).
class VerifiedTopicSource {
  const VerifiedTopicSource({
    required this.topic,
    required this.subject,
    required this.chapter,
    required this.notesText,
    required this.matchScore,
    this.note,
    this.pdfBytes,
    this.pdfFileName = '',
  });

  final String topic;
  final SubjectItem subject;
  final ChapterItem chapter;
  final NoteItem? note;
  final String notesText;
  final double matchScore;
  final Uint8List? pdfBytes;
  final String pdfFileName;

  String get subjectTitle => subject.title;

  /// Adapter for the existing Gemini chapter-lesson path.
  ChapterLessonSource toChapterLessonSource() {
    final blocks = note?.pdfStructuredBlocks ?? const [];
    return ChapterLessonSource(
      chapter: chapter,
      subjectTitle: subject.title,
      notesText: notesText,
      note: note,
      pdfBytes: pdfBytes,
      pdfFileName: pdfFileName,
      pdfStructuredBlocks: blocks,
      pdfIsPrimary: (pdfBytes != null && pdfBytes!.isNotEmpty) || blocks.isNotEmpty,
    );
  }

  bool get hasSubstantialNotes {
    if (note?.pdfStructuredBlocks.isNotEmpty == true) return true;
    final t = notesText.trim();
    if (t.length < 80) return false;
    // Reject the loader's "no detailed notes" placeholder.
    if (t.contains('No detailed notes document found')) return false;
    return true;
  }
}

/// Module 1 — Topic → subject detection → published notes only.
///
/// Does not invent syllabus facts. Matches any student topic string against
/// Firestore `subjects` / `chapters` / `notes` and returns verified text (+ PDF).
class VerifiedContentRetrieval {
  VerifiedContentRetrieval({
    NotesRepository? notes,
    ChapterLessonLoader? loader,
  })  : _notes = notes ?? notesRepository,
        _loader = loader ?? chapterLessonLoader;

  final NotesRepository _notes;
  final ChapterLessonLoader _loader;

  /// Minimum fuzzy score to accept a chapter/topic match.
  static const double minAcceptScore = 0.45;

  /// Resolve [topic] to verified notes, or `null` when notes are missing/thin.
  ///
  /// Student video pipeline must never block on a null result — it falls back
  /// to dynamic Gemini lesson generation instead.
  Future<VerifiedTopicSource?> tryRetrieve({
    required String topic,
    String? subjectHint,
    String targetExam = 'MPSC Combined Group B and C',
  }) async {
    final trimmed = topic.trim();
    if (trimmed.isEmpty) return null;

    try {
      final match = await detectBestMatch(
        topic: trimmed,
        subjectHint: subjectHint,
      );
      if (match == null) return null;

      final loaded = await _loader.load(
        chapter: match.chapter,
        subjectTitle: match.subject.title,
        publishedOnly: true,
      );

      final buffered = StringBuffer()
        ..writeln('Target exam: $targetExam')
        ..writeln('Student topic input: $trimmed')
        ..writeln('Matched chapter: ${match.chapter.title}')
        ..writeln('Matched subject: ${match.subject.title}')
        ..writeln('Match score: ${match.score.toStringAsFixed(2)}')
        ..writeln()
        ..write(loaded.notesText);

      if (match.chapter.aiSummary.trim().isNotEmpty) {
        buffered
          ..writeln()
          ..writeln('Chapter AI summary (admin-verified):')
          ..writeln(match.chapter.aiSummary.trim());
      }
      if (match.chapter.revisionNotes.trim().isNotEmpty) {
        buffered
          ..writeln()
          ..writeln('Chapter revision notes (admin-verified):')
          ..writeln(match.chapter.revisionNotes.trim());
      }

      final source = VerifiedTopicSource(
        topic: trimmed,
        subject: match.subject,
        chapter: match.chapter,
        note: loaded.note?.published == true ? loaded.note : null,
        notesText: buffered.toString(),
        matchScore: match.score,
        pdfBytes: loaded.pdfBytes,
        pdfFileName: loaded.pdfFileName,
      );

      if (!source.hasSubstantialNotes &&
          (source.pdfBytes == null || source.pdfBytes!.isEmpty)) {
        return null;
      }
      return source;
    } catch (e) {
      // Firestore / network issues must not block the student video path.
      return null;
    }
  }

  /// Strict retrieve for tools/admin. Prefer [tryRetrieve] for students.
  Future<VerifiedTopicSource> retrieve({
    required String topic,
    String? subjectHint,
    String targetExam = 'MPSC Combined Group B and C',
  }) async {
    final trimmed = topic.trim();
    if (trimmed.isEmpty) {
      throw const VerifiedContentException(
        'कृपया विषय लिहा.\n(Please enter a topic.)',
      );
    }
    final source = await tryRetrieve(
      topic: trimmed,
      subjectHint: subjectHint,
      targetExam: targetExam,
    );
    if (source == null) {
      throw VerifiedContentException(
        'Verified notes unavailable for "$trimmed" (internal).',
      );
    }
    return source;
  }

  /// Subject + chapter detection for any topic string (unit-testable).
  Future<TopicMatchCandidate?> detectBestMatch({
    required String topic,
    String? subjectHint,
  }) async {
    final q = topic.trim().toLowerCase();
    final hint = (subjectHint ?? '').trim().toLowerCase();

    final subjects = await _notes.getSubjectsOnce();
    final publishedSubjects =
        subjects.where((s) => s.published).toList(growable: false);
    if (publishedSubjects.isEmpty) return null;

    TopicMatchCandidate? best;

    for (final subject in publishedSubjects) {
      final chapters = await _notes.getChaptersOnce(subject.id);
      for (final chapter in chapters.where((c) => c.published)) {
        final note = await _notes.getNoteForChapter(chapter.id);
        final publishedNote =
            (note != null && note.published) ? note : null;

        var score = _scoreTopic(
          q: q,
          subject: subject,
          chapter: chapter,
          note: publishedNote,
        );
        if (hint.isNotEmpty) {
          final hintHit = _score(hint, subject.title) > 0 ||
              _score(hint, subject.nameEn) > 0 ||
              _score(hint, subject.slug) > 0;
          if (hintHit) score += 0.12;
        }

        if (score < minAcceptScore) continue;
        if (best == null || score > best.score) {
          best = TopicMatchCandidate(
            subject: subject,
            chapter: chapter,
            note: publishedNote,
            score: score,
          );
        }
      }
    }

    return best;
  }

  double _scoreTopic({
    required String q,
    required SubjectItem subject,
    required ChapterItem chapter,
    NoteItem? note,
  }) {
    final titleScore = _score(q, chapter.title);
    final titleEnScore = _score(q, chapter.titleEn) * 0.95;
    final slugScore = _score(q, chapter.slug.replaceAll('-', ' ')) * 0.85;
    final subjectScore = _score(q, subject.title) * 0.55;
    final subjectEnScore = _score(q, subject.nameEn) * 0.5;
    final descScore = _score(q, chapter.description) * 0.55;
    final tagScore = chapter.tags.isEmpty
        ? 0.0
        : chapter.tags.map((t) => _score(q, t)).fold<double>(0, (a, b) => a > b ? a : b) *
            0.7;

    var noteScore = 0.0;
    if (note != null) {
      final blob = [
        note.title,
        note.contentMarkdown,
        ...note.importantPoints,
        ...note.revisionSummary,
        ...note.keywords,
        ...note.tags,
      ].join(' ');
      noteScore = _score(q, blob) * 0.8;
    }

    return [
      titleScore,
      titleEnScore,
      slugScore,
      subjectScore,
      subjectEnScore,
      descScore,
      tagScore,
      noteScore,
    ].reduce((a, b) => a > b ? a : b);
  }

  /// Same scoring spirit as [ContentSearchService] (kept local to avoid
  /// pulling MCQ search into the video path).
  double _score(String q, String text) {
    final t = text.toLowerCase().trim();
    if (t.isEmpty || q.isEmpty) return 0;
    if (t == q) return 1;
    if (t.startsWith(q) || q.startsWith(t)) return 0.92;
    if (t.contains(q) || q.contains(t)) return 0.78;

    final tokens = q.split(RegExp(r'\s+')).where((e) => e.length > 1);
    var hits = 0;
    var total = 0;
    for (final token in tokens) {
      total++;
      if (t.contains(token)) hits++;
    }
    if (total == 0) return 0;
    final ratio = hits / total;
    return ratio >= 0.5 ? 0.45 + (ratio * 0.3) : 0;
  }
}

final VerifiedContentRetrieval verifiedContentRetrieval =
    VerifiedContentRetrieval();
