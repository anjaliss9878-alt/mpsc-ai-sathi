import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/services/pyq_analysis_service.dart';

PyqItem _pyq({
  required String id,
  required String topicId,
  required String chapterId,
  required String question,
  String answer = 'official',
  String difficulty = 'Medium',
  NoteWorkflowStatus status = NoteWorkflowStatus.published,
  List<String> tags = const [],
}) {
  return PyqItem(
    id: id,
    title: id,
    subtitle: '',
    fileUrl: '',
    order: 1,
    question: question,
    answer: answer,
    subjectId: 'pol',
    chapterId: chapterId,
    topicId: topicId,
    subject: 'Political Science',
    tags: tags,
    difficulty: difficulty,
    status: status,
    published: status == NoteWorkflowStatus.published,
  );
}

void main() {
  test('PYQ analysis uses only approved/published uploaded rows', () {
    final official = _pyq(
      id: 'p1',
      topicId: 'making',
      chapterId: 'const',
      question: 'How was the Indian Constitution made?',
      tags: const ['constitution'],
    );
    final snap = PyqOfficialSnapshot.of(official);
    final analysis = analyzeUploadedPyqs([
      official,
      _pyq(
        id: 'p2',
        topicId: 'making',
        chapterId: 'const',
        question: 'Who chaired the Drafting Committee of the Constitution?',
        tags: const ['constitution', 'ambedkar'],
        difficulty: 'Hard',
      ),
      _pyq(
        id: 'p3',
        topicId: 'rights',
        chapterId: 'fr',
        question: 'Which article guarantees equality before law?',
        difficulty: 'Easy',
      ),
      _pyq(
        id: 'draft',
        topicId: 'making',
        chapterId: 'const',
        question: 'Draft only — should be ignored',
        status: NoteWorkflowStatus.draft,
      ),
    ]);

    expect(analysis.analyzedCount, 3);
    expect(analysis.topicFrequency.first.id, 'making');
    expect(analysis.topicFrequency.first.count, 2);
    expect(analysis.chapterFrequency.first.id, 'const');
    expect(analysis.difficultyDistribution['Easy'], 1);
    expect(analysis.difficultyDistribution['Hard'], 1);
    expect(analysis.difficultyDistribution['Medium'], 1);
    expect(analysis.preparationPriority.first.id, 'making');
    expect(analysis.repeatedConcepts.any((c) => c.concept.contains('constitution')), isTrue);
    expect(snap.matches(official), isTrue);
    expect(official.question, 'How was the Indian Constitution made?');
    expect(official.answer, 'official');
  });

  test('review flow advances Draft → AI Generated → Under Review → Approved → Published', () {
    expect(
      contentWorkflowNext(NoteWorkflowStatus.draft),
      NoteWorkflowStatus.aiGenerated,
    );
    expect(
      contentWorkflowNext(NoteWorkflowStatus.aiGenerated),
      NoteWorkflowStatus.underReview,
    );
    expect(
      contentWorkflowNext(NoteWorkflowStatus.underReview),
      NoteWorkflowStatus.approved,
    );
    expect(
      contentWorkflowNext(NoteWorkflowStatus.approved),
      NoteWorkflowStatus.published,
    );
    expect(noteWorkflowIsStudentVisible(NoteWorkflowStatus.draft), isFalse);
    expect(noteWorkflowIsStudentVisible(NoteWorkflowStatus.aiGenerated), isFalse);
    expect(noteWorkflowIsStudentVisible(NoteWorkflowStatus.underReview), isFalse);
    expect(noteWorkflowIsStudentVisible(NoteWorkflowStatus.approved), isFalse);
    expect(noteWorkflowIsStudentVisible(NoteWorkflowStatus.published), isTrue);
  });
}
