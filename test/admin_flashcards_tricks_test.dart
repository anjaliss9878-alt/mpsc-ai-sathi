import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/bulk_flashcard_row.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/bulk_smart_trick_row.dart';
import 'package:mpsc_combine_ai/models/ai_teacher_content_item.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/current_affair_item.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/flashcard_item.dart';
import 'package:mpsc_combine_ai/models/rag_study_pack.dart';
import 'package:mpsc_combine_ai/models/smart_trick_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/admin_ai_study_generator.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_content_repository.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_repository.dart';
import 'package:mpsc_combine_ai/services/content_counts_service.dart';
import 'package:mpsc_combine_ai/services/content_index_resolver.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/flashcard_repository.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/smart_trick_repository.dart';
import 'package:mpsc_combine_ai/services/test_repository.dart';
import 'package:mpsc_combine_ai/services/video_repository.dart';

Future<({String subjectId, String chapterId, String topicId})> _seedIndex(
  NotesRepository notes,
) async {
  await notes.ensureDefaultExam();
  final subjectId = await notes.addSubject(
    const SubjectItem(
      id: '',
      title: 'राज्यशास्त्र',
      subtitle: '',
      iconName: 'account_balance',
      order: 0,
      slug: 'rajyashastra',
      nameEn: 'Polity',
      examId: kDefaultExamId,
      published: true,
    ),
  );
  final chapterId = await notes.addChapter(
    ChapterItem(
      id: '',
      subjectId: subjectId,
      title: 'मूलभूत हक्क',
      titleEn: 'Fundamental Rights',
      order: 0,
      examId: kDefaultExamId,
      nodeType: contentNodeTypeToString(ContentNodeType.chapter),
      published: true,
    ),
  );
  final topicId = await notes.addChapter(
    ChapterItem(
      id: '',
      subjectId: subjectId,
      title: 'अनुच्छेद 14',
      titleEn: 'Article 14',
      order: 0,
      examId: kDefaultExamId,
      parentChapterId: chapterId,
      nodeType: contentNodeTypeToString(ContentNodeType.topic),
      published: true,
    ),
  );
  return (subjectId: subjectId, chapterId: chapterId, topicId: topicId);
}

void main() {
  test('flashcard and smart trick round-trip stay Draft until published', () {
    const card = FlashcardItem(
      id: 'fc1',
      title: 'Article 14',
      front: 'What does Article 14 guarantee?',
      back: 'Equality before law',
      explanation: 'Equals are treated equally.',
      examId: kDefaultExamId,
      targetGroup: 'groupB',
      subjectId: 'pol',
      chapterId: 'fr',
      topicId: 'a14',
      published: false,
      status: NoteWorkflowStatus.draft,
    );
    final cardAgain = FlashcardItem.fromMap(card.toMap(), 'fc1');
    expect(cardAgain.isStudentVisible, isFalse);
    expect(cardAgain.status, NoteWorkflowStatus.draft);
    expect(cardAgain.topicId, 'a14');
    expect(cardAgain.front, 'What does Article 14 guarantee?');

    final published = card.copyWith(status: NoteWorkflowStatus.published);
    expect(published.isStudentVisible, isTrue);
    expect(published.toMap()['published'], isTrue);

    const trick = SmartTrickItem(
      id: 'st1',
      title: 'Article 14 mnemonic',
      concept: 'Equality',
      memoryTrick: 'EQUAL = Equal Quality Under All Laws',
      examId: kDefaultExamId,
      targetGroup: 'groupB',
      subjectId: 'pol',
      chapterId: 'fr',
      topicId: 'a14',
      published: false,
      status: NoteWorkflowStatus.draft,
    );
    final trickAgain = SmartTrickItem.fromMap(trick.toMap(), 'st1');
    expect(trickAgain.isStudentVisible, isFalse);
    expect(trickAgain.memoryTrick.contains('EQUAL'), isTrue);
  });

  test('legacy current affairs without status stay student-visible', () {
    final legacy = CurrentAffairItem.fromMap({
      'title': 'Old CA',
      'description': 'Legacy row',
      'category': 'State',
      'date': DateTime(2025, 1, 1).toIso8601String(),
    }, 'legacy');
    expect(legacy.isStudentVisible, isTrue);
    expect(legacy.status, NoteWorkflowStatus.published);

    final draft = CurrentAffairItem(
      id: 'new',
      title: 'Draft CA',
      description: 'Hidden',
      category: 'State',
      date: DateTime(2026, 8, 27),
      published: false,
      status: NoteWorkflowStatus.draft,
    );
    expect(draft.isStudentVisible, isFalse);
  });

  test('AI mapped flashcards and tricks are always Draft', () {
    final card = AdminAiStudyGenerator.flashcardDraft(
      card: const RagFlashcard(
        front: 'Article 14?',
        back: 'Equality before law',
        explanation: 'From RAG',
      ),
      examId: kDefaultExamId,
      targetGroup: 'groupB',
      subjectId: 'pol',
      chapterId: 'fr',
      topicId: 'a14',
    );
    expect(card.status, NoteWorkflowStatus.draft);
    expect(card.published, isFalse);
    expect(card.isStudentVisible, isFalse);

    final trick = AdminAiStudyGenerator.smartTrickDraft(
      title: 'Equality mnemonic',
      concept: 'Article 14',
      memoryTrick: 'EQUAL',
      explanation: 'Treat equals equally',
      example: 'Classification must be reasonable',
      examId: kDefaultExamId,
      targetGroup: 'groupB',
      subjectId: 'pol',
      chapterId: 'fr',
      topicId: 'a14',
    );
    expect(trick.status, NoteWorkflowStatus.draft);
    expect(trick.isStudentVisible, isFalse);
  });

  test('bulk flashcard and smart trick rows validate index and stay draft-ready',
      () {
    final goodCard = BulkFlashcardRow.parse(2, {
      'Exam': 'MPSC Combine',
      'Target Group': 'Group B',
      'Subject': 'Polity',
      'Chapter': 'Fundamental Rights',
      'Topic': 'Article 14',
      'Front': 'What is Article 14?',
      'Back': 'Equality before law',
    });
    expect(goodCard.isValid, isTrue);

    final badExam = BulkFlashcardRow.parse(3, {
      'Exam': 'Rajyaseva',
      'Target Group': 'Group B',
      'Subject': 'Polity',
      'Chapter': 'Fundamental Rights',
      'Topic': 'Article 14',
      'Front': 'Q',
      'Back': 'A',
    });
    expect(badExam.isValid, isFalse);

    final goodTrick = BulkSmartTrickRow.parse(2, {
      'Exam': 'MPSC Combine',
      'Target Group': 'Group B',
      'Subject': 'Polity',
      'Chapter': 'Fundamental Rights',
      'Topic': 'Article 14',
      'Concept': 'Equality',
      'Memory Trick': 'EQUAL',
    });
    expect(goodTrick.isValid, isTrue);
    expect(ContentIndexResolver.isAllowedExamLabel('Rajyaseva'), isFalse);
  });

  test('students see published Part 3 content and never drafts', () async {
    final db = FakeFirebaseFirestore();
    final notes = NotesRepository(firestore: db);
    final ids = await _seedIndex(notes);
    final cards = FlashcardRepository(firestore: db);
    final tricks = SmartTrickRepository(firestore: db);
    final ca = CurrentAffairsRepository(firestore: db);
    final lessons = AiTeacherContentRepository(firestore: db);

    await cards.add(
      FlashcardItem(
        id: '',
        title: 'Article 14 card',
        front: 'Article 14 guarantees?',
        back: 'Equality before law',
        explanation: 'Equals treated equally.',
        examId: kDefaultExamId,
        targetGroup: 'groupB',
        subjectId: ids.subjectId,
        chapterId: ids.chapterId,
        topicId: ids.topicId,
        published: true,
        status: NoteWorkflowStatus.published,
      ),
    );
    await cards.add(
      FlashcardItem(
        id: '',
        title: 'Draft card',
        front: 'Hidden front',
        back: 'Hidden back',
        examId: kDefaultExamId,
        targetGroup: 'groupB',
        subjectId: ids.subjectId,
        chapterId: ids.chapterId,
        topicId: ids.topicId,
        published: false,
        status: NoteWorkflowStatus.draft,
      ),
    );

    await tricks.add(
      SmartTrickItem(
        id: '',
        title: 'Article 14 trick',
        concept: 'Equality',
        memoryTrick: 'EQUAL = Equal Quality Under All Laws',
        examId: kDefaultExamId,
        targetGroup: 'groupB',
        subjectId: ids.subjectId,
        chapterId: ids.chapterId,
        topicId: ids.topicId,
        published: true,
        status: NoteWorkflowStatus.published,
      ),
    );
    await tricks.add(
      SmartTrickItem(
        id: '',
        title: 'Draft trick',
        concept: 'Hidden',
        memoryTrick: 'Should not appear',
        examId: kDefaultExamId,
        targetGroup: 'groupB',
        subjectId: ids.subjectId,
        chapterId: ids.chapterId,
        topicId: ids.topicId,
        published: false,
        status: NoteWorkflowStatus.draft,
      ),
    );

    await ca.add(
      CurrentAffairItem(
        id: '',
        title: 'SC equality judgment',
        description: 'A recent equality ruling useful for MPSC Combine.',
        category: 'National',
        date: DateTime(2026, 8, 20),
        detailedExplanation: 'Linked to Article 14 reasonable classification.',
        source: 'The Hindu',
        examId: kDefaultExamId,
        targetGroup: 'groupB',
        subjectId: ids.subjectId,
        chapterId: ids.chapterId,
        topicId: ids.topicId,
        published: true,
        status: NoteWorkflowStatus.published,
      ),
    );

    await lessons.add(
      AiTeacherContentItem(
        id: '',
        lessonTitle: 'Article 14 classroom',
        subjectName: 'Polity',
        summary: 'Equality before law for Group B.',
        keywords: const ['article 14', 'equality'],
        aiPrompt: '',
        teachingScript: const ['Article 14 guarantees equality before law.'],
        slides: const [],
        quiz: const [],
        notes: const ['Equals are treated equally.'],
        order: 1,
        examId: kDefaultExamId,
        targetGroup: 'groupB',
        subjectId: ids.subjectId,
        chapterId: ids.chapterId,
        topicId: ids.topicId,
        published: true,
        status: NoteWorkflowStatus.published,
      ),
    );
    await lessons.add(
      AiTeacherContentItem(
        id: '',
        lessonTitle: 'Draft lesson',
        subjectName: 'Polity',
        summary: 'Hidden',
        keywords: const ['article 14'],
        aiPrompt: '',
        teachingScript: const ['hidden'],
        slides: const [],
        quiz: const [],
        notes: const [],
        order: 2,
        examId: kDefaultExamId,
        targetGroup: 'groupB',
        subjectId: ids.subjectId,
        chapterId: ids.chapterId,
        topicId: ids.topicId,
        published: false,
        status: NoteWorkflowStatus.draft,
      ),
    );

    final studentCards = await cards.watchPublished().first;
    expect(studentCards.map((c) => c.title), ['Article 14 card']);

    final studentTricks = await tricks.watchPublished().first;
    expect(studentTricks.map((t) => t.title), ['Article 14 trick']);

    final studentCa = await ca.watchPublished().first;
    expect(studentCa.map((e) => e.title), ['SC equality judgment']);

    final match = await lessons.findMatchingLesson('Explain Article 14 please');
    expect(match?.lessonTitle, 'Article 14 classroom');

    final draftMatch = await lessons.findMatchingLesson('article 14 hidden draft');
    expect(draftMatch?.lessonTitle, isNot('Draft lesson'));
    expect(draftMatch?.status, NoteWorkflowStatus.published);

    final counts = await ContentCountsService(
      notes: notes,
      mcqs: McqRepository(firestore: db),
      pyqs: PyqRepository(firestore: db),
      tests: TestRepository(firestore: db),
      videos: VideoRepository(firestore: db),
      lessons: AiLessonRepository(firestore: db),
      flashcards: cards,
      smartTricks: tricks,
      currentAffairs: ca,
      aiTeacherContent: lessons,
    ).forTopic(topicId: ids.topicId, topicTitle: 'Article 14');
    expect(counts.flashcards, 2);
    expect(counts.smartTricks, 2);
    expect(counts.currentAffairs, 1);
    expect(counts.aiLessons, 2);
    expect(counts.compactLabel.contains('Flashcards 2'), isTrue);
  });
}
