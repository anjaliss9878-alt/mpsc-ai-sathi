import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';

enum SearchResultKind { topic, note, mcq, question }

class SearchHit {
  const SearchHit({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.score,
    this.subject,
    this.chapter,
    this.note,
    this.mcq,
  });

  final SearchResultKind kind;
  final String title;
  final String subtitle;
  final double score;
  final SubjectItem? subject;
  final ChapterItem? chapter;
  final NoteItem? note;
  final McqItem? mcq;
}

/// Client-side instant search across subjects/chapters/notes/MCQs.
///
/// Loads lightly (subjects + chapters + notes + mcqs once per query burst)
/// and scores matches locally — no extra Firebase indexes required.
class ContentSearchService {
  ContentSearchService({
    NotesRepository? notes,
    McqRepository? mcqs,
  })  : _notes = notes ?? notesRepository,
        _mcqs = mcqs ?? mcqRepository;

  final NotesRepository _notes;
  final McqRepository _mcqs;

  List<SubjectItem>? _subjectsCache;
  Map<String, List<ChapterItem>>? _chaptersBySubject;
  List<NoteItem>? _notesCache;
  List<McqItem>? _mcqsCache;
  DateTime? _cacheAt;

  Future<void> _ensureCache({bool force = false}) async {
    final fresh = _cacheAt != null &&
        DateTime.now().difference(_cacheAt!) < const Duration(minutes: 2);
    if (!force && fresh && _subjectsCache != null) return;

    final subjects = (await _notes.watchPublishedSubjects().first);
    final chaptersBySubject = <String, List<ChapterItem>>{};
    for (final s in subjects) {
      chaptersBySubject[s.id] = await _notes.watchPublishedChapters(s.id).first;
    }
    final notes = await _notes.watchPublishedNotes().first;
    final mcqs = await _mcqs.watchPublished().first;

    _subjectsCache = subjects;
    _chaptersBySubject = chaptersBySubject;
    _notesCache = notes;
    _mcqsCache = mcqs;
    _cacheAt = DateTime.now();
  }

  Future<List<SearchHit>> search(String rawQuery, {int limit = 40}) async {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];

    await _ensureCache();
    final subjects = _subjectsCache ?? const <SubjectItem>[];
    final chaptersBySubject = _chaptersBySubject ?? const {};
    final notes = _notesCache ?? const <NoteItem>[];
    final mcqs = _mcqsCache ?? const <McqItem>[];
    final notesByChapter = {for (final n in notes) n.chapterId: n};

    final hits = <SearchHit>[];

    for (final subject in subjects) {
      final chapters = chaptersBySubject[subject.id] ?? const <ChapterItem>[];
      for (final chapter in chapters) {
        final titleScore = _score(q, chapter.title);
        final subjectScore = _score(q, subject.title) * 0.6;
        final descScore = _score(q, chapter.description) * 0.5;
        final best = [titleScore, subjectScore, descScore]
            .reduce((a, b) => a > b ? a : b);
        if (best > 0) {
          hits.add(
            SearchHit(
              kind: SearchResultKind.topic,
              title: chapter.title,
              subtitle: 'Topic · ${subject.title}',
              score: best + 0.15,
              subject: subject,
              chapter: chapter,
              note: notesByChapter[chapter.id],
            ),
          );
        }

        final note = notesByChapter[chapter.id];
        if (note != null) {
          final blob = [
            note.contentMarkdown,
            ...note.importantPoints,
            ...note.revisionSummary,
            ...note.keywords,
          ].join(' ');
          final noteScore = _score(q, blob);
          if (noteScore > 0) {
            hits.add(
              SearchHit(
                kind: SearchResultKind.note,
                title: chapter.title,
                subtitle: 'Notes · ${subject.title}',
                score: noteScore + 0.1,
                subject: subject,
                chapter: chapter,
                note: note,
              ),
            );
          }
        }
      }
    }

    for (final mcq in mcqs) {
      final blob = [
        mcq.question,
        mcq.setTitle,
        mcq.subject,
        ...mcq.options,
        mcq.explanation,
        ...mcq.tags,
      ].join(' ');
      final score = _score(q, blob);
      if (score > 0) {
        hits.add(
          SearchHit(
            kind: SearchResultKind.mcq,
            title: mcq.question,
            subtitle: 'MCQ · ${mcq.setTitle}',
            score: score,
            mcq: mcq,
          ),
        );
        hits.add(
          SearchHit(
            kind: SearchResultKind.question,
            title: mcq.question,
            subtitle: 'Question · ${mcq.subject}',
            score: score * 0.95,
            mcq: mcq,
          ),
        );
      }
    }

    hits.sort((a, b) => b.score.compareTo(a.score));
    // Deduplicate near-identical titles keeping highest score.
    final seen = <String>{};
    final unique = <SearchHit>[];
    for (final h in hits) {
      final key = '${h.kind.name}|${h.title}|${h.subtitle}';
      if (seen.add(key)) unique.add(h);
      if (unique.length >= limit) break;
    }
    return unique;
  }

  Future<List<String>> suggestions(String rawQuery, {int limit = 8}) async {
    final hits = await search(rawQuery, limit: limit * 2);
    final out = <String>[];
    final seen = <String>{};
    for (final h in hits) {
      final label = h.title.trim();
      if (label.isEmpty) continue;
      if (seen.add(label.toLowerCase())) out.add(label);
      if (out.length >= limit) break;
    }
    return out;
  }

  double _score(String q, String text) {
    final t = text.toLowerCase();
    if (t.isEmpty || q.isEmpty) return 0;
    if (t == q) return 1;
    if (t.startsWith(q)) return 0.9;
    if (t.contains(q)) return 0.75;
    // Token overlap for multi-word Marathi/English queries.
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

final ContentSearchService contentSearchService = ContentSearchService();
