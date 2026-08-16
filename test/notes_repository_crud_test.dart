import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/pdf_content_block.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/utils/firestore_payload.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late NotesRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = NotesRepository(firestore: firestore);
  });

  test('create note writes published + defaults and returns id', () async {
    final id = await repo.saveNote(
      subjectId: 'sub1',
      chapterId: 'ch1',
      importantPoints: const ['Point A'],
      revisionSummary: const ['Sum A'],
    );
    expect(id, isNotEmpty);

    final snap = await firestore.collection('notes').doc(id).get();
    expect(snap.exists, isTrue);
    final data = snap.data()!;
    expect(data['subjectId'], 'sub1');
    expect(data['chapterId'], 'ch1');
    expect(data['importantPoints'], ['Point A']);
    expect(data['revisionSummary'], ['Sum A']);
    expect(data['contentMarkdown'], '');
    expect(data['published'], isTrue);
    expect(data['attachments'], isEmpty);
    expect(data['mcqs'], isEmpty);
  });

  test('chapter-style update does not wipe importantPoints', () async {
    final id = await repo.saveNote(
      subjectId: 'sub1',
      chapterId: 'ch1',
      importantPoints: const ['Keep me'],
      revisionSummary: const ['Old summary'],
    );

    await repo.saveNote(
      noteId: id,
      subjectId: 'sub1',
      chapterId: 'ch1',
      // importantPoints intentionally omitted (null)
      revisionSummary: const ['New summary'],
      contentMarkdown: '## Body',
      videoUrl: 'https://example.com/v',
    );

    final note = await repo.getNoteForChapter('ch1');
    expect(note, isNotNull);
    expect(note!.id, id);
    expect(note.importantPoints, ['Keep me']);
    expect(note.revisionSummary, ['New summary']);
    expect(note.contentMarkdown, '## Body');
    expect(note.videoUrl, 'https://example.com/v');
  });

  test('notes-form update does not wipe videoUrl/keywords/mcqs when preserved', () async {
    final id = await repo.saveNote(
      subjectId: 'sub1',
      chapterId: 'ch1',
      importantPoints: const ['A'],
      revisionSummary: const ['S'],
      videoUrl: 'https://keep.me/video',
      keywords: const ['polity'],
      mcqs: const [
        NoteMcq(
          question: 'Q?',
          options: ['1', '2', '3', '4'],
          correctIndex: 0,
        ),
      ],
    );

    await repo.saveNote(
      noteId: id,
      subjectId: 'sub1',
      chapterId: 'ch1',
      importantPoints: const ['A', 'B'],
      revisionSummary: const ['S2'],
      contentMarkdown: 'md',
      attachments: const [],
      videoUrl: 'https://keep.me/video',
      keywords: const ['polity'],
      mcqs: const [
        NoteMcq(
          question: 'Q?',
          options: ['1', '2', '3', '4'],
          correctIndex: 0,
        ),
      ],
    );

    final note = await repo.getNoteForChapter('ch1');
    expect(note!.importantPoints, ['A', 'B']);
    expect(note.videoUrl, 'https://keep.me/video');
    expect(note.keywords, ['polity']);
    expect(note.mcqs, hasLength(1));
    expect(note.mcqs.first.question, 'Q?');
  });

  test('saveNote flattens PDF tableRows and writes media URL fields', () async {
    const tableBlock = PdfContentBlock(
      type: PdfBlockType.table,
      title: 'तुलना',
      tableHeaders: ['सभागृह', 'निवड'],
      tableRows: [
        ['लोकसभा', 'थेट'],
        ['राज्यसभा', 'अप्रत्यक्ष'],
      ],
    );
    final id = await repo.saveNote(
      subjectId: 'sub1',
      chapterId: 'ch1',
      title: 'संसद',
      attachments: const [
        NoteAttachment(
          name: 'sansad.pdf',
          url: 'https://example.com/sansad.pdf',
          type: 'pdf',
        ),
        NoteAttachment(
          name: 'chart.png',
          url: 'https://example.com/chart.png',
          type: 'image',
        ),
        NoteAttachment(
          name: 'handout.docx',
          url: 'https://example.com/handout.docx',
          type: 'docx',
        ),
      ],
      pdfStructuredBlocks: const [tableBlock],
      videoUrl: 'https://example.com/topic.mp4',
      tags: const ['polity'],
      mcqs: const [
        NoteMcq(
          question: 'Q?',
          options: ['1', '2', '3', '4'],
          correctIndex: 0,
        ),
      ],
    );

    final snap = await firestore.collection('notes').doc(id).get();
    final data = snap.data()!;
    expect(hasNestedArrays(data), isFalse, reason: findNestedArrayPath(data));
    expect(data['pdfUrl'], 'https://example.com/sansad.pdf');
    expect(data['videoUrl'], 'https://example.com/topic.mp4');
    expect(data['docxUrl'], 'https://example.com/handout.docx');
    expect(data['imageUrls'], ['https://example.com/chart.png']);
    expect(data['attachments'], isA<List>());
    expect((data['attachments'] as List).first, isA<Map>());

    final blocks = data['pdfStructuredBlocks'] as List;
    expect(blocks, hasLength(1));
    final rows = (blocks.first as Map)['tableRows'] as List;
    expect(rows, hasLength(2));
    expect(rows.first, isA<Map>());
    expect((rows.first as Map)['cells'], ['लोकसभा', 'थेट']);

    final note = await repo.getNoteForChapter('ch1');
    expect(note!.pdfUrl, 'https://example.com/sansad.pdf');
    expect(note.docxUrl, 'https://example.com/handout.docx');
    expect(note.imageUrls, ['https://example.com/chart.png']);
    expect(note.pdfStructuredBlocks.first.tableRows, [
      ['लोकसभा', 'थेट'],
      ['राज्यसभा', 'अप्रत्यक्ष'],
    ]);
  });

  test('deleteNote removes the document', () async {
    final id = await repo.saveNote(
      subjectId: 'sub1',
      chapterId: 'ch1',
      importantPoints: const ['X'],
    );
    await repo.deleteNote(id);
    final note = await repo.getNoteForChapter('ch1');
    expect(note, isNull);
  });

  test('edit then read round-trip', () async {
    final id = await repo.saveNote(
      subjectId: 'sub1',
      chapterId: 'ch1',
      importantPoints: const ['One'],
    );
    await repo.saveNote(
      noteId: id,
      subjectId: 'sub1',
      chapterId: 'ch1',
      importantPoints: const ['One', 'Two'],
      revisionSummary: const ['Rev'],
    );
    final note = await repo.getNoteForChapter('ch1');
    expect(note!.importantPoints, ['One', 'Two']);
    expect(note.revisionSummary, ['Rev']);
  });

  test('note title is stored and published notes stream hides drafts', () async {
    final id = await repo.saveNote(
      subjectId: 'sub1',
      chapterId: 'ch1',
      title: 'मूलभूत हक्क — नोट्स',
      contentMarkdown: 'Article 12–35',
      published: true,
    );
    final note = await repo.getNoteForChapter('ch1');
    expect(note!.id, id);
    expect(note.title, 'मूलभूत हक्क — नोट्स');
    expect(note.contentMarkdown, 'Article 12–35');

    await repo.saveNote(
      noteId: id,
      subjectId: 'sub1',
      chapterId: 'ch1',
      published: false,
    );
    final published = await repo.watchPublishedNoteForChapter('ch1').first;
    expect(published, isNull);
  });
}
