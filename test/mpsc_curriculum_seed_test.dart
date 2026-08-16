import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/admin/seed/mpsc_curriculum_seeder.dart';
import 'package:mpsc_combine_ai/data/subject_notes_data.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';

void main() {
  test('curriculum catalog has 10 subjects and full topic lists', () {
    expect(mpscCurriculumSubjectCount, 10);
    expect(mpscCurriculumTopicCount, 144);
    expect(subjectNotesCatalog.first.title, 'राज्यशास्त्र');
    expect(subjectNotesCatalog.first.topics, contains('महत्त्वाच्या घटनादुरुस्त्या'));
    expect(subjectNotesCatalog.last.title, 'इंग्रजी');
    expect(subjectNotesCatalog.last.topics, contains('Sentence Correction'));
  });

  test('seedMpscCurriculumStructure is idempotent by slug', () async {
    final firestore = FakeFirebaseFirestore();
    final repo = NotesRepository(firestore: firestore);

    final first = await seedMpscCurriculumStructure(repository: repo);
    expect(first, contains('10 विषय'));
    expect(first, contains('144 टॉपिक'));

    final subjects = await repo.getSubjectsOnce();
    expect(subjects, hasLength(10));
    expect(subjects.every((s) => s.slug.isNotEmpty), isTrue);
    expect(subjects.every((s) => s.published), isTrue);

    var topicTotal = 0;
    for (final s in subjects) {
      final chapters = await repo.getChaptersOnce(s.id);
      topicTotal += chapters.length;
      expect(chapters.every((c) => c.slug.isNotEmpty), isTrue);
      expect(chapters.every((c) => c.published), isTrue);
    }
    expect(topicTotal, 144);

    final second = await seedMpscCurriculumStructure(repository: repo);
    expect(second, contains('+0'));
    final subjectsAgain = await repo.getSubjectsOnce();
    expect(subjectsAgain, hasLength(10));
  });

  test('published filters hide draft subjects/chapters', () async {
    final firestore = FakeFirebaseFirestore();
    final repo = NotesRepository(firestore: firestore);
    await seedMpscCurriculumStructure(repository: repo);
    final subjects = await repo.getSubjectsOnce();
    final first = subjects.first;
    await repo.updateSubject(first.copyWith(published: false));

    final published = await repo.watchPublishedSubjects().first;
    expect(published.any((s) => s.id == first.id), isFalse);
    expect(published.length, 9);
  });
}
