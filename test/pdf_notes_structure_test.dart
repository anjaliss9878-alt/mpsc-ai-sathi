import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/pdf_content_block.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/chapter_lesson_loader.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/verified_notes_lesson_composer.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/lesson_render_job_builder.dart';
import 'package:mpsc_combine_ai/utils/firestore_payload.dart';

void main() {
  group('PdfContentBlock', () {
    test('parses typed blocks without flattening', () {
      final block = PdfContentBlock.fromMap({
        'type': 'table',
        'title': 'लोकसभा vs राज्यसभा',
        'tableHeaders': ['सभागृह', 'निवड'],
        'tableRows': [
          ['लोकसभा', 'थेट'],
          ['राज्यसभा', 'अप्रत्यक्ष'],
        ],
      });
      expect(block.type, PdfBlockType.table);
      expect(block.tableHeaders, ['सभागृह', 'निवड']);
      expect(block.tableRows.length, 2);

      final encoded = block.toMap();
      expect(hasNestedArrays(encoded), isFalse, reason: findNestedArrayPath(encoded));
      expect(encoded['tableRows'], isA<List>());
      expect((encoded['tableRows'] as List).first, isA<Map>());
      expect(
        PdfContentBlock.fromMap(encoded).tableRows,
        [
          ['लोकसभा', 'थेट'],
          ['राज्यसभा', 'अप्रत्यक्ष'],
        ],
      );

      final md = block.toStructuredMarkdown();
      expect(md.contains('| सभागृह | निवड |'), isTrue);
      expect(md.contains('लोकसभा'), isTrue);
      // Must not be a single flattened sentence blob.
      expect(md.contains('\n'), isTrue);
    });

    test('structured document keeps block separators', () {
      final doc = pdfBlocksToStructuredDocument([
        const PdfContentBlock(
          type: PdfBlockType.heading,
          title: 'प्रस्तावना',
        ),
        const PdfContentBlock(
          type: PdfBlockType.bullets,
          title: 'मुद्दे',
          bullets: ['बिंदू एक', 'बिंदू दोन'],
        ),
        PdfContentBlock(
          type: PdfBlockType.flowchart,
          title: 'प्रक्रिया',
          flowchart: [
            {
              'id': '1',
              'label': 'सुरुवात',
              'nextIds': <String>['2'],
            },
            {
              'id': '2',
              'label': 'शेवट',
              'nextIds': <String>[],
            },
          ],
        ),
      ]);
      expect(doc.contains('[heading]'), isTrue);
      expect(doc.contains('[bullets]'), isTrue);
      expect(doc.contains('[flowchart]'), isTrue);
      expect(doc.contains('--- block'), isTrue);
    });
  });

  group('VerifiedNotesLessonComposer PDF blocks', () {
    test('builds table and flowchart slides from PDF structure', () {
      final lesson = const VerifiedNotesLessonComposer().compose(
        ChapterLessonSource(
          chapter: const ChapterItem(
            id: 'c1',
            subjectId: 's1',
            title: 'संसद',
            order: 1,
            pdfUrl: 'https://example.com/sansad.pdf',
          ),
          subjectTitle: 'राज्यशास्त्र',
          notesText: 'PRIMARY SOURCE: Topic PDF',
          pdfIsPrimary: true,
          pdfStructuredBlocks: [
            const PdfContentBlock(type: PdfBlockType.heading, title: 'संसद रचना'),
            const PdfContentBlock(
              type: PdfBlockType.table,
              title: 'तुलना',
              tableHeaders: ['सभागृह', 'कार्यकाळ'],
              tableRows: [
                ['लोकसभा', '५ वर्षे'],
                ['राज्यसभा', 'स्थायी'],
              ],
            ),
            PdfContentBlock(
              type: PdfBlockType.flowchart,
              title: 'कायदा प्रक्रिया',
              flowchart: [
                {
                  'id': '1',
                  'label': 'विधेयक',
                  'nextIds': <String>['2'],
                },
                {
                  'id': '2',
                  'label': 'मान्यता',
                  'nextIds': <String>[],
                },
              ],
            ),
            const PdfContentBlock(
              type: PdfBlockType.bullets,
              title: 'महत्त्वाचे',
              bullets: [
                'अनुच्छेद ७९ संसदेची रचना सांगतो',
                'लोकसभा थेट निवडणुकीने निवडली जाते',
              ],
            ),
          ],
        ),
      );
      expect(lesson.sourceKind, LessonSourceKind.verifiedNotes);
      expect(lesson.slides.length, greaterThanOrEqualTo(kMinEduSlides));
      expect(
        lesson.slides.any((s) => s.visualType == SlideVisualType.table),
        isTrue,
      );
      expect(
        lesson.slides.any((s) => s.visualType == SlideVisualType.flowchart),
        isTrue,
      );
      expect(
        lesson.slides.any((s) => s.tableHeaders.contains('सभागृह')),
        isTrue,
      );
    });
  });
}
