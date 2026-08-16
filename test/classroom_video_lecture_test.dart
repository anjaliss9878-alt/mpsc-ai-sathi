import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/classroom_video/classroom_lecture.dart';

void main() {
  test('lecture parser cleans spoken symbols and keeps 10–20 slides', () {
    final lecture = ClassroomLecture.fromMap({
      'title': 'लोकसभा • Page 2',
      'narration': 'GDP + 8% / UPSC',
      'slides': [
        for (var i = 1; i <= 12; i++)
          {
            'heading': 'मुद्दा $i',
            'points': ['• मुद्दा $i', 'Page $i'],
            'spoken': 'GDP + $i% वाढ.',
          },
      ],
    });
    expect(lecture.slides, hasLength(12));
    expect(lecture.title.contains('Page'), isFalse);
    expect(lecture.narration.contains('+'), isFalse);
    expect(lecture.narration.contains('%'), isFalse);
    expect(lecture.narration.contains('/'), isFalse);
    expect(lecture.narration, contains('जी डी पी'));
    expect(lecture.slides.first.points.first.contains('•'), isFalse);
  });

  test('slide durations follow spoken length and sum to total', () {
    final lecture = ClassroomLecture.fromMap({
      'title': 'चाचणी',
      'slides': [
        {'heading': 'अ', 'points': ['अ'], 'spoken': 'एक दोन तीन चार पाच'},
        {'heading': 'ब', 'points': ['ब'], 'spoken': 'सहा'},
      ],
    });
    final total = const Duration(seconds: 10);
    final d = lecture.slideDurations(total);
    expect(d, hasLength(2));
    expect(d[0].inMilliseconds, greaterThan(d[1].inMilliseconds));
    expect(
      d.fold<int>(0, (a, b) => a + b.inMilliseconds),
      total.inMilliseconds,
    );
  });

  test('stripJsonFences extracts object from markdown', () {
    const raw = '```json\n{"title":"अ"}\n```';
    expect(stripJsonFences(raw), '{"title":"अ"}');
  });
}
