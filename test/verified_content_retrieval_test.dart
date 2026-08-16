import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/chapter_lesson_loader.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/verified_content_retrieval.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late NotesRepository notes;
  late VerifiedContentRetrieval retrieval;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    notes = NotesRepository(firestore: firestore);
    retrieval = VerifiedContentRetrieval(
      notes: notes,
      loader: ChapterLessonLoader(notes: notes),
    );

    final subjectId = await notes.addSubject(
      const SubjectItem(
        id: '',
        title: 'राज्यशास्त्र',
        subtitle: 'Polity',
        iconName: 'account_balance',
        order: 1,
        slug: 'rajyashastra',
        nameEn: 'Polity',
        published: true,
      ),
    );
    final chapterId = await notes.addChapter(
      ChapterItem(
        id: '',
        subjectId: subjectId,
        title: 'मूलभूत हक्क',
        order: 1,
        slug: 'rajyashastra-mulbhut-hakk',
        titleEn: 'Fundamental Rights',
        published: true,
        description: 'भारतीय संविधानातील मूलभूत हक्क',
        tags: const ['rights', 'constitution'],
      ),
    );
    await notes.saveNote(
      subjectId: subjectId,
      chapterId: chapterId,
      importantPoints: const [
        'कलम १२ ते ३५ मध्ये मूलभूत हक्क आहेत.',
        'हे हक्क न्यायालयात लागू करता येतात.',
        'आर्टिकल ३२ हा संवैधानिक उपाय आहे.',
      ],
      revisionSummary: const [
        'मूलभूत हक्क न्याय्य आहेत.',
        'MPSC Prelims मध्ये वारंवार विचारले जातात.',
      ],
      contentMarkdown: '## मूलभूत हक्क\n\nनागरिकांचे मूलभूत हक्क.',
      keywords: const ['कलम ३२', 'मूलभूत हक्क'],
      published: true,
    );
  });

  test('detects subject and chapter for any matching topic string', () async {
    final match = await retrieval.detectBestMatch(topic: 'मूलभूत हक्क');
    expect(match, isNotNull);
    expect(match!.chapter.title, 'मूलभूत हक्क');
    expect(match.subject.title, 'राज्यशास्त्र');
    expect(match.score, greaterThanOrEqualTo(0.45));
  });

  test('matches English topic aliases without hardcoding one topic', () async {
    final match = await retrieval.detectBestMatch(topic: 'Fundamental Rights');
    expect(match, isNotNull);
    expect(match!.chapter.titleEn, 'Fundamental Rights');
  });

  test('retrieve returns verified notes text only', () async {
    final source = await retrieval.retrieve(topic: 'मूलभूत हक्क');
    expect(source.hasSubstantialNotes, isTrue);
    expect(source.notesText, contains('कलम १२ ते ३५'));
    expect(source.notesText, contains('MPSC Combined Group B and C'));
    expect(source.notesText, isNot(contains('No detailed notes document found')));
  });

  test('tryRetrieve returns null for unknown topic (student fallback path)', () async {
    final source = await retrieval.tryRetrieve(topic: 'zzz_unknown_topic_xyz_999');
    expect(source, isNull);
  });

  test('strict retrieve still signals missing notes for tools/admin', () async {
    expect(
      () => retrieval.retrieve(topic: 'zzz_unknown_topic_xyz_999'),
      throwsA(isA<VerifiedContentException>()),
    );
  });
}
