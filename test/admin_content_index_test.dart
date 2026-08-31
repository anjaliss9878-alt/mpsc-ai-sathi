import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late NotesRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = NotesRepository(firestore: firestore);
  });

  test('ensureDefaultExam writes exams/mpsc_combine', () async {
    final exam = await repo.ensureDefaultExam();
    expect(exam.id, kDefaultExamId);
    final snap = await firestore.collection('exams').doc(kDefaultExamId).get();
    expect(snap.exists, isTrue);
    expect(snap.data()?['title'], ExamItem.mpscCombine().title);
  });

  test('Exam → Subject → Chapter → Topic reuse subjects + chapters', () async {
    await repo.ensureDefaultExam();
    final subjectId = await repo.addSubject(
      const SubjectItem(
        id: '',
        title: 'Indian Polity',
        subtitle: 'राज्यशास्त्र',
        iconName: 'account_balance',
        order: 0,
        slug: 'polity-test',
        examId: kDefaultExamId,
        published: true,
      ),
    );
    final chapterId = await repo.addChapter(
      ChapterItem(
        id: '',
        subjectId: subjectId,
        title: 'Indian Constitution',
        order: 0,
        examId: kDefaultExamId,
        nodeType: contentNodeTypeToString(ContentNodeType.chapter),
        published: true,
      ),
    );
    final topicId = await repo.addChapter(
      ChapterItem(
        id: '',
        subjectId: subjectId,
        title: 'Fundamental Rights',
        order: 0,
        examId: kDefaultExamId,
        parentChapterId: chapterId,
        nodeType: contentNodeTypeToString(ContentNodeType.topic),
        published: true,
      ),
    );

    final subjects = await firestore.collection('subjects').get();
    final chapters = await firestore.collection('chapters').get();
    final topicsCol = await firestore.collection('topics').get();
    expect(subjects.docs, hasLength(1));
    expect(chapters.docs, hasLength(2));
    expect(topicsCol.docs, isEmpty, reason: 'Do not create a parallel topics collection');

    final roots = await repo.watchRootChapters(subjectId).first;
    expect(roots.map((c) => c.id), [chapterId]);

    final topics = await repo.watchChildChapters(chapterId).first;
    expect(topics.map((t) => t.id), [topicId]);
    expect(topics.first.topicId, topicId);

    final student = await repo.watchPublishedChapters(subjectId).first;
    expect(student.map((c) => c.id), [topicId]);
    expect(student.first.title, 'Fundamental Rights');
  });

  test('legacy empty nodeType chapters stay visible to students', () async {
    final subjectId = await repo.addSubject(
      const SubjectItem(
        id: '',
        title: 'भूगोल',
        subtitle: '',
        iconName: 'public',
        order: 0,
        published: true,
      ),
    );
    final legacyId = await repo.addChapter(
      ChapterItem(
        id: '',
        subjectId: subjectId,
        title: 'भारताचा भूगोल',
        order: 0,
        published: true,
      ),
    );
    final student = await repo.watchPublishedChapters(subjectId).first;
    expect(student.map((c) => c.id), [legacyId]);
  });

  test('inactive topic is hidden from students', () async {
    final subjectId = await repo.addSubject(
      const SubjectItem(
        id: '',
        title: 'Polity',
        subtitle: '',
        iconName: 'account_balance',
        order: 0,
        published: true,
      ),
    );
    final chapterId = await repo.addChapter(
      ChapterItem(
        id: '',
        subjectId: subjectId,
        title: 'Constitution',
        order: 0,
        nodeType: 'chapter',
        published: true,
      ),
    );
    await repo.addChapter(
      ChapterItem(
        id: '',
        subjectId: subjectId,
        title: 'Article 14',
        order: 0,
        parentChapterId: chapterId,
        nodeType: 'topic',
        published: false,
      ),
    );
    await repo.addChapter(
      ChapterItem(
        id: '',
        subjectId: subjectId,
        title: 'Article 19',
        order: 1,
        parentChapterId: chapterId,
        nodeType: 'topic',
        published: true,
      ),
    );
    final student = await repo.watchPublishedChapters(subjectId).first;
    expect(student.map((c) => c.title), ['Article 19']);
  });

  test('subject activate/deactivate uses published flag on subjects collection', () async {
    final id = await repo.addSubject(
      const SubjectItem(
        id: '',
        title: 'Hidden then shown',
        subtitle: '',
        iconName: 'menu_book',
        order: 0,
        published: false,
      ),
    );
    var student = await repo.watchPublishedSubjects().first;
    expect(student, isEmpty);

    final stored = await repo.getSubject(id);
    await repo.updateSubject(stored!.copyWith(published: true));
    student = await repo.watchPublishedSubjects().first;
    expect(student.single.id, id);
  });

  test('note on a topic is found when student opens that topic id', () async {
    final subjectId = await repo.addSubject(
      const SubjectItem(
        id: '',
        title: 'Polity',
        subtitle: '',
        iconName: 'account_balance',
        order: 0,
        published: true,
      ),
    );
    final chapterId = await repo.addChapter(
      ChapterItem(
        id: '',
        subjectId: subjectId,
        title: 'Constitution',
        order: 0,
        nodeType: 'chapter',
        published: true,
      ),
    );
    final topicId = await repo.addChapter(
      ChapterItem(
        id: '',
        subjectId: subjectId,
        title: 'Fundamental Rights',
        order: 0,
        parentChapterId: chapterId,
        nodeType: 'topic',
        published: true,
      ),
    );
    final noteId = await repo.saveNote(
      examId: kDefaultExamId,
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: topicId,
      title: 'FR PDF notes',
      status: NoteWorkflowStatus.published,
      attachments: const [
        NoteAttachment(
          name: 'fr.pdf',
          url: 'https://example.com/fr.pdf',
          type: 'pdf',
        ),
      ],
    );
    final studentNote = await repo.watchPublishedNoteForChapter(topicId).first;
    expect(studentNote, isNotNull);
    expect(studentNote!.id, noteId);
    expect(studentNote.pdfUrl, 'https://example.com/fr.pdf');
    expect(studentNote.examId, kDefaultExamId);
    expect(studentNote.topicId, topicId);
    expect(studentNote.chapterId, chapterId);
  });

  test('Save Draft creates a note that students cannot see', () async {
    await repo.ensureDefaultExam();
    final exams = await repo.getExamsOnce();
    expect(exams.first.id, kDefaultExamId);

    final subjectId = await repo.addSubject(
      const SubjectItem(
        id: '',
        title: 'Polity',
        subtitle: '',
        iconName: 'account_balance',
        order: 0,
        published: true,
      ),
    );
    final chapterId = await repo.addChapter(
      ChapterItem(
        id: '',
        subjectId: subjectId,
        title: 'Fundamental Rights',
        order: 0,
        published: true,
      ),
    );
    final noteId = await repo.saveNote(
      subjectId: subjectId,
      chapterId: chapterId,
      topicId: chapterId,
      title: 'Article 14 draft',
      status: NoteWorkflowStatus.draft,
    );
    final saved = await repo.getNote(noteId);
    expect(saved, isNotNull);
    expect(saved!.status, NoteWorkflowStatus.draft);
    expect(saved.isStudentVisible, isFalse);

    final student = await repo.watchPublishedNotes().first;
    expect(student.map((n) => n.id), isNot(contains(noteId)));
  });
}
