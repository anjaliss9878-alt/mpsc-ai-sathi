import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

void main() {
  group('asStringList', () {
    test('null and empty', () {
      expect(asStringList(null), isEmpty);
      expect(asStringList(<dynamic>[]), isEmpty);
    });

    test('list of scalars', () {
      expect(asStringList(['a', 'b', 3]), ['a', 'b', '3']);
    });

    test('single string and multiline', () {
      expect(asStringList('one'), ['one']);
      expect(asStringList('a\nb\n'), ['a', 'b']);
    });

    test('index-keyed map and scalar map values', () {
      expect(asStringList({'0': 'x', '1': 'y'}), ['x', 'y']);
      expect(asStringList({'a': 'polity', 'b': 'history'}), ['polity', 'history']);
    });

    test('domain-looking scalar map flattens values (tags/options style)', () {
      // Same shape as index-free option maps; callers that need a Map use asMapList.
      expect(asStringList({'name': 'file.pdf', 'url': 'https://x', 'type': 'pdf'}), [
        'file.pdf',
        'https://x',
        'pdf',
      ]);
    });
  });

  group('asStringTable', () {
    test('reads nested lists and Firestore-safe cell maps', () {
      expect(
        asStringTable([
          ['a', 'b'],
          {'cells': ['c', 'd']},
          {'0': 'e', '1': 'f'},
        ]),
        [
          ['a', 'b'],
          ['c', 'd'],
          ['e', 'f'],
        ],
      );
    });
  });

  group('asMapList', () {
    test('null / list / single map', () {
      expect(asMapList(null), isEmpty);
      expect(
        asMapList([
          {'a': 1},
          {'b': 2},
        ]),
        [
          {'a': 1},
          {'b': 2},
        ],
      );
      expect(asMapList({'name': 'n', 'url': 'u'}), [
        {'name': 'n', 'url': 'u'},
      ]);
    });

    test('map-of-maps uses values', () {
      expect(
        asMapList({
          '0': {'q': 'one'},
          '1': {'q': 'two'},
        }),
        [
          {'q': 'one'},
          {'q': 'two'},
        ],
      );
    });
  });

  group('NoteItem.fromMap Map-shaped list fields', () {
    test('parses Map instead of List without throwing', () {
      final note = NoteItem.fromMap({
        'subjectId': 's1',
        'chapterId': 'c1',
        'importantPoints': {'0': 'Point A', '1': 'Point B'},
        'revisionSummary': 'Single summary line',
        'keywords': {'k1': 'polity', 'k2': 'rights'},
        'tags': 'tag-one',
        'attachments': {
          'name': 'notes.pdf',
          'url': 'https://example.com/notes.pdf',
          'type': 'pdf',
        },
        'mcqs': {
          'question': 'Q?',
          'options': {'0': 'A', '1': 'B', '2': 'C', '3': 'D'},
          'correctIndex': 1,
          'explanation': 'Because',
        },
      }, 'n1');

      expect(note.importantPoints, ['Point A', 'Point B']);
      expect(note.revisionSummary, ['Single summary line']);
      expect(note.keywords, ['polity', 'rights']);
      expect(note.tags, ['tag-one']);
      expect(note.attachments, hasLength(1));
      expect(note.attachments.first.name, 'notes.pdf');
      expect(note.mcqs, hasLength(1));
      expect(note.mcqs.first.options, ['A', 'B', 'C', 'D']);
      expect(note.mcqs.first.correctIndex, 1);
    });
  });

  group('McqItem.fromMap Map-shaped options/tags', () {
    test('parses Map options and tags', () {
      final mcq = McqItem.fromMap({
        'setTitle': 'Set 1',
        'subject': 'Polity',
        'difficulty': 'Easy',
        'question': 'Q?',
        'options': {'a': '1', 'b': '2', 'c': '3', 'd': '4'},
        'correctIndex': 0,
        'explanation': 'E',
        'order': 1,
        'tags': {'0': 'constitution'},
      }, 'm1');

      expect(mcq.options, ['1', '2', '3', '4']);
      expect(mcq.tags, ['constitution']);
    });
  });

  group('GeneratedLesson.fromMap Map-shaped lists', () {
    test('parses Map slides/mcqs/script without throwing', () {
      final lesson = GeneratedLesson.fromMap({
        'question': 'Explain FR',
        'topicName': 'FR',
        'subjectName': 'Polity',
        'script': {'0': 'Hello', '1': 'World'},
        'slides': {
          '0': {
            'title': 'Slide 1',
            'bullets': {'0': 'A', '1': 'B'},
            'keywords': 'right',
          },
        },
        'summary': 'S',
        'mcqs': {
          'question': 'Q?',
          'options': ['1', '2', '3', '4'],
          'correctIndex': 0,
        },
        'notes': 'Note line',
        'createdAt': '2026-01-01T00:00:00.000',
      }, 'lesson1');

      expect(lesson.script, ['Hello', 'World']);
      expect(lesson.slides, hasLength(1));
      expect(lesson.slides.first.bullets, ['A', 'B']);
      expect(lesson.slides.first.keywords, ['right']);
      expect(lesson.mcqs, hasLength(1));
      expect(lesson.notes, ['Note line']);
    });
  });
}
