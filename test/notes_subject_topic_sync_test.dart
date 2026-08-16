import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Proves Admin create → Student published streams (same Firestore collections).
void main() {
  late FakeFirebaseFirestore firestore;
  late NotesRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = NotesRepository(firestore: firestore);
  });

  test('Admin subject create appears immediately in Admin + Student streams', () async {
    final id = await repo.addSubject(
      const SubjectItem(
        id: '',
        title: 'राज्यशास्त्र',
        subtitle: 'Polity',
        iconName: 'account_balance',
        order: 1,
        slug: 'rajyashastra-test',
        published: true,
      ),
    );
    expect(id, isNotEmpty);

    final stored = await firestore.collection('subjects').doc(id).get();
    expect(stored.data()?['published'], isTrue);
    expect(stored.data()?['title'], 'राज्यशास्त्र');
    expect(stored.data()?['nameMr'], 'राज्यशास्त्र');

    final adminList = await repo.watchSubjects().first;
    expect(adminList.map((s) => s.id), contains(id));
    expect(adminList.firstWhere((s) => s.id == id).title, 'राज्यशास्त्र');

    final studentList = await repo.watchPublishedSubjects().first;
    expect(studentList.map((s) => s.id), contains(id));
    expect(studentList.firstWhere((s) => s.id == id).title, 'राज्यशास्त्र');
  });

  test('subjects missing order field still appear (client-side sort)', () async {
    // Simulate a console/import write that forgot `order`.
    final doc = await firestore.collection('subjects').add({
      'title': 'इतिहास',
      'nameMr': 'इतिहास',
      'published': true,
      // no order
    });

    final list = await repo.watchSubjects().first;
    expect(list.map((s) => s.id), contains(doc.id));
    expect(list.firstWhere((s) => s.id == doc.id).order, 0);
  });

  test('Admin published topic appears under same subject for students', () async {
    final subjectId = await repo.addSubject(
      const SubjectItem(
        id: '',
        title: 'भूगोल',
        subtitle: 'Geography',
        iconName: 'public',
        order: 0,
        slug: 'bhugol-test',
        published: true,
      ),
    );

    final chapterId = await repo.addChapter(
      ChapterItem(
        id: '',
        subjectId: subjectId,
        title: 'भारताचा भूगोल',
        order: 0,
        slug: 'bhugol-bharat',
        published: true,
      ),
    );

    final adminChapters = await repo.watchChapters(subjectId).first;
    expect(adminChapters.map((c) => c.id), contains(chapterId));

    final studentTopics = await repo.watchPublishedChapters(subjectId).first;
    expect(studentTopics, hasLength(1));
    expect(studentTopics.first.title, 'भारताचा भूगोल');
    expect(studentTopics.first.subjectId, subjectId);
  });

  test('Draft topic is hidden from students but visible to Admin', () async {
    final subjectId = await repo.addSubject(
      const SubjectItem(
        id: '',
        title: 'अर्थव्यवस्था',
        subtitle: '',
        iconName: 'trending_up',
        order: 0,
        published: true,
      ),
    );
    await repo.addChapter(
      ChapterItem(
        id: '',
        subjectId: subjectId,
        title: 'Draft Topic',
        order: 0,
        published: false,
      ),
    );
    await repo.addChapter(
      ChapterItem(
        id: '',
        subjectId: subjectId,
        title: 'Published Topic',
        order: 1,
        published: true,
      ),
    );

    final admin = await repo.watchChapters(subjectId).first;
    expect(admin, hasLength(2));

    final student = await repo.watchPublishedChapters(subjectId).first;
    expect(student.map((c) => c.title), ['Published Topic']);
  });

  test('Draft subject is hidden from students', () async {
    await repo.addSubject(
      const SubjectItem(
        id: '',
        title: 'Hidden',
        subtitle: '',
        iconName: 'menu_book',
        order: 0,
        published: false,
      ),
    );
    await repo.addSubject(
      const SubjectItem(
        id: '',
        title: 'Visible',
        subtitle: '',
        iconName: 'menu_book',
        order: 1,
        published: true,
      ),
    );

    final student = await repo.watchPublishedSubjects().first;
    expect(student.map((s) => s.title), ['Visible']);
  });

  test('asBool / asInt harden published + order parsing', () {
    expect(asBool(null), isTrue);
    expect(asBool('false', defaultValue: true), isFalse);
    expect(asBool('1'), isTrue);
    expect(asInt('3'), 3);
    expect(asInt(null), 0);

    final subject = SubjectItem.fromMap({
      'title': 'Test',
      'published': 'true',
      'order': '5',
    }, 'x');
    expect(subject.published, isTrue);
    expect(subject.order, 5);

    final chapter = ChapterItem.fromMap({
      'subjectId': 's1',
      'titleMr': 'टॉपिक',
      'published': 0,
      'order': '2',
    }, 'c1');
    expect(chapter.title, 'टॉपिक');
    expect(chapter.published, isFalse);
    expect(chapter.order, 2);
  });

  test('collections used are subjects + chapters (not topics)', () async {
    final subjectId = await repo.addSubject(
      const SubjectItem(
        id: '',
        title: 'A',
        subtitle: '',
        iconName: 'menu_book',
        order: 0,
      ),
    );
    await repo.addChapter(
      ChapterItem(id: '', subjectId: subjectId, title: 'T', order: 0),
    );

    expect(firestore.collection('subjects'), isNotNull);
    final subjects = await firestore.collection('subjects').get();
    final chapters = await firestore.collection('chapters').get();
    final topics = await firestore.collection('topics').get();
    expect(subjects.docs, hasLength(1));
    expect(chapters.docs, hasLength(1));
    expect(topics.docs, isEmpty);
  });
}
