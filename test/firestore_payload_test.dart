import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/utils/firestore_payload.dart';

void main() {
  test('flattenFirestoreValue converts nested arrays to cell maps', () {
    final nested = {
      'tableRows': [
        ['लोकसभा', 'थेट'],
        ['राज्यसभा', 'अप्रत्यक्ष'],
      ],
      'attachments': [
        {'name': 'a.pdf', 'url': 'https://x', 'type': 'pdf'},
      ],
      'mcqs': [
        {
          'question': 'Q?',
          'options': ['1', '2', '3', '4'],
        },
      ],
    };

    final flat = flattenFirestoreValue(nested) as Map<String, dynamic>;
    expect(hasNestedArrays(nested), isTrue);
    expect(hasNestedArrays(flat), isFalse);
    expect(findNestedArrayPath(nested), r'$.tableRows[0]');
    expect((flat['tableRows'] as List).first, isA<Map>());
    expect(((flat['tableRows'] as List).first as Map)['cells'], ['लोकसभा', 'थेट']);
    expect(((flat['mcqs'] as List).first as Map)['options'], ['1', '2', '3', '4']);
  });

  test('prepareFirestoreNotePayload flattens nested tableRows before write', () {
    final payload = prepareFirestoreNotePayload({
      'attachments': [
        {'name': 'a.pdf', 'url': 'https://x', 'type': 'pdf'},
      ],
      'pdfStructuredBlocks': [
        {
          'type': 'table',
          'tableRows': [
            ['a', 'b'],
          ],
        },
      ],
    });
    expect(hasNestedArrays(payload), isFalse);
    final rows = (payload['pdfStructuredBlocks'] as List).first['tableRows'] as List;
    expect(rows.first, isA<Map>());
    expect((rows.first as Map)['cells'], ['a', 'b']);
  });
}
