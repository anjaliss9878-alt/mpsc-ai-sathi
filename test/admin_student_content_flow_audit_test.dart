import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/flashcard_item.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/models/smart_trick_item.dart';
import 'package:mpsc_combine_ai/services/ai_generated_content_repository.dart';
import 'package:mpsc_combine_ai/services/flashcard_repository.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/smart_trick_repository.dart';
import 'package:mpsc_combine_ai/models/ai_generated_content.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';

/// End-to-end Admin → draft → publish → Student visibility for temporary
/// integration content. Uses FakeFirebaseFirestore only (no production data).
void main() {
  const examId = kGroupBCombinedExamId;
  const subjectId = 'gs_paper_2_audit';
  const chapterId = 'mh_current_affairs_audit';
  const topicId = 'mh_ca_topic_audit';
  const marker = 'TEMP_AUDIT_E2E_20260911';

  late FakeFirebaseFirestore db;
  late NotesRepository notes;
  late McqRepository mcqs;
  late FlashcardRepository cards;
  late SmartTrickRepository tricks;
  late PyqRepository pyqs;
  late AiGeneratedContentRepository staging;

  setUp(() {
    db = FakeFirebaseFirestore();
    notes = NotesRepository(firestore: db);
    mcqs = McqRepository(firestore: db);
    cards = FlashcardRepository(firestore: db);
    tricks = SmartTrickRepository(firestore: db);
    pyqs = PyqRepository(firestore: db);
    staging = AiGeneratedContentRepository(firestore: db);
  });

  test('Group B Combined exam id is canonical (not mpsc_combine)', () {
    expect(examId, 'mpsc_group_b_combined');
    expect(examId, isNot('mpsc_combine'));
  });

  test('draft academic content is invisible to student published queries',
      () async {
    final noteId = await notes.saveNote(
      examId: examId,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      title: '$marker Note Draft',
      description: 'temp',
      contentMarkdown: 'temp body',
      status: NoteWorkflowStatus.draft,
      tags: const [marker],
    );
    final mcqId = await mcqs.add(
      McqItem(
        id: '',
        setTitle: marker,
        subject: 'GS Paper 2',
        difficulty: 'Easy',
        question: '$marker Q?',
        options: const ['a', 'b', 'c', 'd'],
        correctIndex: 0,
        explanation: 'e',
        order: 1,
        examId: examId,
        subjectId: subjectId,
        chapterId: chapterId,
        topicId: topicId,
        published: false,
        status: NoteWorkflowStatus.draft,
      ),
    );
    final cardId = await cards.add(
      FlashcardItem(
        id: '',
        title: '$marker Card',
        front: 'F',
        back: 'B',
        examId: examId,
        subjectId: subjectId,
        chapterId: chapterId,
        topicId: topicId,
        published: false,
        status: NoteWorkflowStatus.draft,
      ),
    );
    final trickId = await tricks.add(
      SmartTrickItem(
        id: '',
        title: '$marker Trick',
        concept: 'c',
        memoryTrick: 'm',
        explanation: 'e',
        examId: examId,
        subjectId: subjectId,
        chapterId: chapterId,
        topicId: topicId,
        published: false,
        status: NoteWorkflowStatus.draft,
      ),
    );

    expect(await notes.watchPublishedNotes().first, isEmpty);
    expect(await mcqs.watchPublished().first, isEmpty);
    expect(await cards.watchPublished().first, isEmpty);
    expect(await tricks.watchPublished().first, isEmpty);

    // Publish only these temp items.
    await notes.saveNote(
      noteId: noteId,
      examId: examId,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      title: '$marker Note Live',
      description: 'temp',
      contentMarkdown: 'temp body',
      status: NoteWorkflowStatus.published,
      tags: const [marker],
    );
    await mcqs.update(
      (await mcqs.watchAll().first).single.copyWith(
            published: true,
            status: NoteWorkflowStatus.published,
            setTitle: 'AI Practice Question',
            tags: const ['ai-practice-question', marker],
          ),
    );
    await cards.update(
      (await cards.watchAll().first).single.copyWith(
            published: true,
            status: NoteWorkflowStatus.published,
          ),
    );
    await tricks.update(
      (await tricks.watchAll().first).single.copyWith(
            published: true,
            status: NoteWorkflowStatus.published,
          ),
    );

    final liveNotes = await notes.watchPublishedNotes().first;
    final liveMcqs = await mcqs.watchForChapter(chapterId).first;
    final liveCards = await cards.watchPublished().first;
    final liveTricks = await tricks.watchPublished().first;

    expect(liveNotes.single.title, '$marker Note Live');
    expect(liveNotes.single.examId, examId);
    expect(liveNotes.single.subjectId, subjectId);
    expect(liveNotes.single.chapterId, chapterId);
    expect(liveNotes.single.published, isTrue);
    expect(liveNotes.single.status, NoteWorkflowStatus.published);

    expect(liveMcqs, hasLength(1));
    expect(liveMcqs.single.examId, examId);
    expect(liveMcqs.single.chapterId, chapterId);
    expect(liveMcqs.single.isAiPracticeQuestion, isTrue);
    expect(liveMcqs.single.isActualPyq, isFalse);
    expect(liveMcqs.single.practiceLabel, 'AI Practice Question');

    expect(liveCards.single.chapterId, chapterId);
    expect(liveTricks.single.chapterId, chapterId);

    // Wrong chapter must not receive these MCQs.
    expect(await mcqs.watchForChapter('other_chapter').first, isEmpty);

    // Rollback temp data only.
    await notes.deleteNote(noteId);
    await mcqs.delete(mcqId);
    await cards.delete(cardId);
    await tricks.delete(trickId);
    expect(await notes.watchPublishedNotes().first, isEmpty);
    expect(await mcqs.watchPublished().first, isEmpty);
  });

  test('PYQs stay separate from AI practice MCQs', () async {
    await pyqs.add(
      PyqItem(
        id: '',
        title: '$marker PYQ Paper',
        subtitle: '2024',
        fileUrl: '',
        order: 1,
        year: 2024,
        examName: 'MPSC Group B Combined',
        question: '$marker PYQ',
        options: const ['a', 'b', 'c', 'd'],
        correctIndex: 1,
        explanation: 'official',
        examId: examId,
        subjectId: subjectId,
        chapterId: chapterId,
        topicId: topicId,
        published: true,
        status: NoteWorkflowStatus.published,
        source: 'MPSC Official',
      ),
    );
    await mcqs.add(
      McqItem(
        id: '',
        setTitle: 'AI Practice Question',
        subject: 'GS',
        difficulty: 'Medium',
        question: '$marker AI Q',
        options: const ['a', 'b', 'c', 'd'],
        correctIndex: 0,
        explanation: 'from rag',
        order: 2,
        tags: const ['ai-practice-question'],
        examId: examId,
        subjectId: subjectId,
        chapterId: chapterId,
        published: true,
        status: NoteWorkflowStatus.published,
      ),
    );

    final pyqList = await pyqs.watchPublished().first;
    final mcqList = await mcqs.watchPublished().first;
    expect(pyqList.single.question, '$marker PYQ');
    expect(mcqList.single.isAiPracticeQuestion, isTrue);
    expect(mcqList.single.setTitle.toLowerCase(), isNot(contains('previous year')));
  });

  test('aiGeneratedContent staging stays draft until publish fields set',
      () async {
    final id = await staging.add(
      AiGeneratedContentItem(
        id: '',
        examId: examId,
        subjectId: subjectId,
        chapterId: chapterId,
        topicId: topicId,
        sourceId: 'ready_src',
        contentType: AiGeneratedContentType.mcq,
        content: {
          'question': '$marker staged',
          'options': ['a', 'b', 'c', 'd'],
          'correctIndex': 0,
          'explanation': 'e',
          'label': 'AI Practice Question',
          'isActualPyq': false,
        },
        sourceCitation: 'Ready PDF p.1',
        status: NoteWorkflowStatus.draft,
        generationBatchId: 'batch_audit',
      ),
    );
    final item = await staging.get(id);
    expect(item, isNotNull);
    expect(item!.isDraft, isTrue);
    expect(item.content['isActualPyq'], isFalse);
    expect(item.examId, examId);
    expect(item.sourceCitation, 'Ready PDF p.1');
    await staging.delete(id);
    expect(await staging.get(id), isNull);
  });
}
