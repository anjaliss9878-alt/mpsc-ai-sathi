import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_content_repository.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_repository.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/flashcard_repository.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/smart_trick_repository.dart';
import 'package:mpsc_combine_ai/services/test_repository.dart';
import 'package:mpsc_combine_ai/services/video_repository.dart';

/// Counts existing content linked to one topic (`chapters/{id}`).
///
/// PYQ / MCQ / Tests / Flashcards / Smart Tricks reuse the existing
/// collections — drafts are included so the Admin Topic screen reflects
/// authored content, not only published.
class ContentCountsService {
  ContentCountsService({
    NotesRepository? notes,
    McqRepository? mcqs,
    PyqRepository? pyqs,
    TestRepository? tests,
    VideoRepository? videos,
    AiLessonRepository? lessons,
    FlashcardRepository? flashcards,
    SmartTrickRepository? smartTricks,
    CurrentAffairsRepository? currentAffairs,
    AiTeacherContentRepository? aiTeacherContent,
  })  : _notes = notes ?? notesRepository,
        _mcqs = mcqs ?? mcqRepository,
        _pyqs = pyqs ?? pyqRepository,
        _tests = tests ?? testRepository,
        _videos = videos ?? videoRepository,
        _lessons = lessons ?? aiLessonRepository,
        _flashcards = flashcards ?? flashcardRepository,
        _smartTricks = smartTricks ?? smartTrickRepository,
        _currentAffairs = currentAffairs ?? currentAffairsRepository,
        _aiTeacherContent = aiTeacherContent ?? aiTeacherContentRepository;

  final NotesRepository _notes;
  final McqRepository _mcqs;
  final PyqRepository _pyqs;
  final TestRepository _tests;
  final VideoRepository _videos;
  final AiLessonRepository _lessons;
  final FlashcardRepository _flashcards;
  final SmartTrickRepository _smartTricks;
  final CurrentAffairsRepository _currentAffairs;
  final AiTeacherContentRepository _aiTeacherContent;

  Future<TopicContentCounts> forTopic({
    required String topicId,
    String topicTitle = '',
  }) async {
    if (topicId.isEmpty) return TopicContentCounts.empty;

    final notes = await _notes.getNotesForTopicOnce(topicId);
    final mcqs = (await _mcqs.watchAll().first).where(
      (q) => contentLinkedToTopic(
        topicId: topicId,
        topicIdField: q.topicId,
        chapterIdField: q.chapterId,
      ),
    );
    final pyqs = (await _pyqs.watchAll().first).where(
      (p) => contentLinkedToTopic(
        topicId: topicId,
        topicIdField: p.topicId,
        chapterIdField: p.chapterId,
      ),
    );
    final tests = (await _tests.watchAll().first).where(
      (t) => contentLinkedToTopic(
        topicId: topicId,
        topicIdField: t.topicId,
        chapterIdField: t.chapterId,
        topicIds: t.topicIds,
      ),
    );
    final flashcards = (await _flashcards.watchAll().first).where(
      (c) => contentLinkedToTopic(
        topicId: topicId,
        topicIdField: c.topicId,
        chapterIdField: c.chapterId,
      ),
    );
    final tricks = (await _smartTricks.watchAll().first).where(
      (t) => contentLinkedToTopic(
        topicId: topicId,
        topicIdField: t.topicId,
        chapterIdField: t.chapterId,
      ),
    );
    final ca = (await _currentAffairs.watchAll().first).where(
      (e) => contentLinkedToTopic(
        topicId: topicId,
        topicIdField: e.topicId,
        chapterIdField: e.chapterId,
      ),
    );
    final authored = (await _aiTeacherContent.watchAll().first).where(
      (l) => contentLinkedToTopic(
        topicId: topicId,
        topicIdField: l.topicId,
        chapterIdField: l.chapterId,
      ),
    );
    final lessons = await _lessons.watchAll(limit: 200).first;
    final videos = await _videos.watchAll().first;

    final titleNeedle = topicTitle.trim().toLowerCase();
    var videoCount = 0;
    if (titleNeedle.isNotEmpty) {
      for (final v in videos) {
        final hay = '${v.title} ${v.subject} ${v.description}'.toLowerCase();
        if (hay.contains(titleNeedle)) videoCount++;
      }
    }

    final generated = lessons.where(
      (l) => contentLinkedToTopic(
        topicId: topicId,
        topicIdField: l.topicId,
        chapterIdField: l.chapterId,
      ),
    );

    return TopicContentCounts(
      notes: notes.length,
      pyqs: pyqs.length,
      mcqs: mcqs.length,
      tests: tests.length,
      flashcards: flashcards.length,
      smartTricks: tricks.length,
      currentAffairs: ca.length,
      videos: videoCount,
      aiLessons: authored.length + generated.length,
    );
  }
}

final ContentCountsService contentCountsService = ContentCountsService();
