import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/ai_teacher_content_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/current_affair_item.dart';
import 'package:mpsc_combine_ai/models/flashcard_item.dart';
import 'package:mpsc_combine_ai/models/job_alert.dart';
import 'package:mpsc_combine_ai/models/smart_trick_item.dart';
import 'package:mpsc_combine_ai/models/test_item.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_content_repository.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/flashcard_repository.dart';
import 'package:mpsc_combine_ai/services/job_alerts_repository.dart';
import 'package:mpsc_combine_ai/services/smart_trick_repository.dart';
import 'package:mpsc_combine_ai/services/test_repository.dart';

FlashcardItem _card({
  required String title,
  required bool published,
  required NoteWorkflowStatus status,
}) {
  return FlashcardItem(
    id: '',
    title: title,
    front: title,
    back: 'back',
    published: published,
    status: status,
  );
}

SmartTrickItem _trick({
  required String title,
  required bool published,
  required NoteWorkflowStatus status,
}) {
  return SmartTrickItem(
    id: '',
    title: title,
    concept: title,
    memoryTrick: 'trick',
    published: published,
    status: status,
  );
}

CurrentAffairItem _ca({
  required String title,
  required bool published,
  required NoteWorkflowStatus status,
}) {
  return CurrentAffairItem(
    id: '',
    title: title,
    description: title,
    category: 'General',
    date: DateTime(2026, 1, 1),
    published: published,
    status: status,
  );
}

TestItem _test({
  required String title,
  required bool published,
  required NoteWorkflowStatus status,
}) {
  return TestItem(
    id: '',
    title: title,
    subtitle: '',
    durationSeconds: 600,
    correctMarks: 2,
    negativeMarks: 0.5,
    questions: const [],
    order: 0,
    published: published,
    status: status,
  );
}

AiTeacherContentItem _lesson({
  required String title,
  required bool published,
  required NoteWorkflowStatus status,
  List<String> keywords = const ['polity'],
}) {
  return AiTeacherContentItem(
    id: '',
    lessonTitle: title,
    subjectName: 'Polity',
    summary: title,
    keywords: keywords,
    aiPrompt: '',
    teachingScript: const ['script'],
    slides: const [],
    quiz: const [],
    notes: const [],
    order: 0,
    published: published,
    status: status,
  );
}

JobAlert _job({required String name, required bool published}) {
  return JobAlert(
    id: '',
    examName: name,
    organization: 'MPSC',
    post: 'PSI',
    eligibility: 'Graduate',
    description: 'Notice',
    applicationUrl: 'https://mpsc.gov.in',
    published: published,
  );
}

void main() {
  test('student published queries hide draft underReview approved unpublished',
      () async {
    final db = FakeFirebaseFirestore();
    final cards = FlashcardRepository(firestore: db);
    final tricks = SmartTrickRepository(firestore: db);
    final ca = CurrentAffairsRepository(firestore: db);
    final tests = TestRepository(firestore: db);
    final lessons = AiTeacherContentRepository(firestore: db);
    final jobs = JobAlertsRepository(firestore: db);

    await cards.add(_card(
      title: 'Live card',
      published: true,
      status: NoteWorkflowStatus.published,
    ));
    await cards.add(_card(
      title: 'Draft card',
      published: false,
      status: NoteWorkflowStatus.draft,
    ));
    await cards.add(_card(
      title: 'Review card',
      published: false,
      status: NoteWorkflowStatus.underReview,
    ));
    await cards.add(_card(
      title: 'Approved card',
      published: false,
      status: NoteWorkflowStatus.approved,
    ));

    await tricks.add(_trick(
      title: 'Live trick',
      published: true,
      status: NoteWorkflowStatus.published,
    ));
    await tricks.add(_trick(
      title: 'Draft trick',
      published: false,
      status: NoteWorkflowStatus.draft,
    ));

    await ca.add(_ca(
      title: 'Live CA',
      published: true,
      status: NoteWorkflowStatus.published,
    ));
    await ca.add(_ca(
      title: 'Draft CA',
      published: false,
      status: NoteWorkflowStatus.draft,
    ));
    await ca.add(_ca(
      title: 'Review CA',
      published: false,
      status: NoteWorkflowStatus.underReview,
    ));

    await tests.add(_test(
      title: 'Live paper',
      published: true,
      status: NoteWorkflowStatus.published,
    ));
    await tests.add(_test(
      title: 'Approved paper',
      published: false,
      status: NoteWorkflowStatus.approved,
    ));

    await lessons.add(_lesson(
      title: 'Live lesson',
      published: true,
      status: NoteWorkflowStatus.published,
    ));
    await lessons.add(_lesson(
      title: 'Draft lesson',
      published: false,
      status: NoteWorkflowStatus.draft,
    ));

    await jobs.add(_job(name: 'Live job', published: true));
    await jobs.add(_job(name: 'Draft job', published: false));

    expect(
      (await cards.watchPublished().first).map((c) => c.title),
      ['Live card'],
    );
    expect(
      (await tricks.watchPublished().first).map((t) => t.title),
      ['Live trick'],
    );
    expect(
      (await ca.watchPublished().first).map((e) => e.title),
      ['Live CA'],
    );
    expect(
      (await tests.watchPublished().first).map((t) => t.title),
      ['Live paper'],
    );
    expect(
      (await lessons.watchPublished().first).map((l) => l.lessonTitle),
      ['Live lesson'],
    );
    expect(
      (await jobs.watchPublished().first).map((j) => j.examName),
      ['Live job'],
    );
    expect((await jobs.getPublished()).map((j) => j.examName), ['Live job']);

    expect((await cards.watchAll().first).length, 4);
    expect((await tricks.watchAll().first).length, 2);
    expect((await ca.watchAll().first).length, 3);
    expect((await tests.watchAll().first).length, 2);
    expect((await lessons.watchAll().first).length, 2);
    expect((await jobs.watchAll().first).length, 2);
  });

  test('legacy published docs missing status stay student-visible', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('flashcards').add({
      'title': 'Legacy card',
      'front': 'Q',
      'back': 'A',
      'published': true,
      'order': 0,
    });
    await db.collection('smartTricks').add({
      'title': 'Legacy trick',
      'concept': 'C',
      'memoryTrick': 'M',
      'published': true,
      'order': 0,
    });
    await db.collection('currentAffairs').add({
      'title': 'Legacy CA',
      'description': 'D',
      'category': 'General',
      'date': DateTime(2026, 2, 1).toIso8601String(),
      'published': true,
    });
    await db.collection('tests').add({
      'title': 'Legacy paper',
      'subtitle': '',
      'durationSeconds': 600,
      'correctMarks': 2,
      'negativeMarks': 0.5,
      'questions': <Map<String, dynamic>>[],
      'order': 0,
      'published': true,
    });
    await db.collection('aiTeacherContent').add({
      'lessonTitle': 'Legacy lesson',
      'subjectName': 'Polity',
      'summary': 'S',
      'keywords': ['article 12'],
      'aiPrompt': '',
      'teachingScript': <String>['s'],
      'slides': <Map<String, dynamic>>[],
      'quiz': <Map<String, dynamic>>[],
      'notes': <String>[],
      'order': 0,
      'published': true,
    });
    await db.collection('jobAlerts').add({
      'examName': 'Legacy job',
      'organization': 'MPSC',
      'post': 'PSI',
      'eligibility': '',
      'description': '',
      'applicationUrl': '',
      'published': true,
    });

    expect(
      (await FlashcardRepository(firestore: db).watchPublished().first)
          .single
          .title,
      'Legacy card',
    );
    expect(
      (await SmartTrickRepository(firestore: db).watchPublished().first)
          .single
          .title,
      'Legacy trick',
    );
    expect(
      (await CurrentAffairsRepository(firestore: db).watchPublished().first)
          .single
          .title,
      'Legacy CA',
    );
    expect(
      (await TestRepository(firestore: db).watchPublished().first).single.title,
      'Legacy paper',
    );
    expect(
      (await AiTeacherContentRepository(firestore: db).watchPublished().first)
          .single
          .lessonTitle,
      'Legacy lesson',
    );
    expect(
      (await JobAlertsRepository(firestore: db).watchPublished().first)
          .single
          .examName,
      'Legacy job',
    );
  });

  test('published=true with draft/underReview status stays hidden', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('flashcards').add({
      'title': 'Draft status card',
      'front': 'Q',
      'back': 'A',
      'published': true,
      'status': 'draft',
      'order': 0,
    });
    await db.collection('currentAffairs').add({
      'title': 'Review CA',
      'description': 'D',
      'category': 'General',
      'date': DateTime(2026, 3, 1).toIso8601String(),
      'published': true,
      'status': 'underReview',
    });
    await db.collection('tests').add({
      'title': 'Approved paper',
      'subtitle': '',
      'durationSeconds': 600,
      'correctMarks': 2,
      'negativeMarks': 0.5,
      'questions': <Map<String, dynamic>>[],
      'order': 0,
      'published': true,
      'status': 'approved',
    });
    expect(await FlashcardRepository(firestore: db).watchPublished().first, isEmpty);
    expect(
      await CurrentAffairsRepository(firestore: db).watchPublished().first,
      isEmpty,
    );
    expect(await TestRepository(firestore: db).watchPublished().first, isEmpty);
    expect(
      (await FlashcardRepository(firestore: db).watchAll().first).single.title,
      'Draft status card',
    );
  });

  test('jobAlerts ignore workflow status; unpublished stay hidden', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('jobAlerts').add({
      'examName': 'Live with stray status',
      'organization': 'MPSC',
      'post': 'PSI',
      'eligibility': '',
      'description': '',
      'applicationUrl': '',
      'published': true,
      'status': 'draft',
    });
    await db.collection('jobAlerts').add({
      'examName': 'Hidden',
      'organization': 'MPSC',
      'post': 'STI',
      'eligibility': '',
      'description': '',
      'applicationUrl': '',
      'published': false,
    });
    final repo = JobAlertsRepository(firestore: db);
    expect(
      (await repo.watchPublished().first).map((j) => j.examName),
      ['Live with stray status'],
    );
    expect((await repo.getPublished()).single.examName, 'Live with stray status');
    expect((await repo.watchAll().first).length, 2);
  });

  test('findMatchingLesson uses published docs only', () async {
    final db = FakeFirebaseFirestore();
    final lessons = AiTeacherContentRepository(firestore: db);
    await lessons.add(_lesson(
      title: 'Draft lesson',
      published: false,
      status: NoteWorkflowStatus.draft,
      keywords: const ['article 14'],
    ));
    await lessons.add(_lesson(
      title: 'Live lesson',
      published: true,
      status: NoteWorkflowStatus.published,
      keywords: const ['article 14'],
    ));
    final match = await lessons.findMatchingLesson('Explain Article 14');
    expect(match?.lessonTitle, 'Live lesson');
    expect(await lessons.findMatchingLesson('unrelated topic'), isNull);
  });

  test('admin can still write after student published filter', () async {
    final db = FakeFirebaseFirestore();
    final tests = TestRepository(firestore: db);
    final id = await tests.add(_test(
      title: 'Paper',
      published: false,
      status: NoteWorkflowStatus.draft,
    ));
    await tests.update(
      TestItem(
        id: id,
        title: 'Paper live',
        subtitle: '',
        durationSeconds: 600,
        correctMarks: 2,
        negativeMarks: 0.5,
        questions: const [],
        order: 0,
        published: true,
        status: NoteWorkflowStatus.published,
      ),
    );
    expect((await tests.watchPublished().first).single.title, 'Paper live');
    await tests.delete(id);
    expect(await tests.watchAll().first, isEmpty);
  });
}
