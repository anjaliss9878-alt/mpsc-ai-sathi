import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/utils/student_media.dart';
import 'package:mpsc_combine_ai/widgets/lesson_video_controls.dart';

void main() {
  test('friendlyAttachmentName hides URLs and timestamps', () {
    expect(
      friendlyAttachmentName(
        'https://firebasestorage.googleapis.com/v0/b/x/o/a.pdf',
        fallback: 'PDF Notes',
      ),
      'PDF Notes',
    );
    expect(
      friendlyAttachmentName('1712345678901_Polity.pdf', fallback: 'Notes'),
      'Polity.pdf',
    );
    expect(friendlyAttachmentName('', fallback: 'Notes'), 'Notes');
  });

  test('studentFacingMediaError never echoes TypeError or URLs', () {
    const raw =
        'TypeError: Failed to fetch https://firebasestorage.googleapis.com/v0/b/x';
    final msg = studentFacingMediaError(raw);
    expect(msg.toLowerCase().contains('typeerror'), isFalse);
    expect(msg.toLowerCase().contains('firebase'), isFalse);
    expect(msg.toLowerCase().contains('http'), isFalse);
    expect(msg, contains('try again'));
  });

  test('youtubeVideoId parses watch and short links', () {
    expect(
      youtubeVideoId('https://www.youtube.com/watch?v=abc123XYZ00'),
      'abc123XYZ00',
    );
    expect(youtubeVideoId('https://youtu.be/abc123XYZ00'), 'abc123XYZ00');
  });

  test('lesson speed labels cover 1x–2x', () {
    expect(lessonSpeedLabel(1), '1x');
    expect(lessonSpeedLabel(1.25), '1.25x');
    expect(lessonSpeedLabel(1.5), '1.5x');
    expect(lessonSpeedLabel(2), '2x');
    expect(kLessonPlaybackSpeeds, [1.0, 1.25, 1.5, 2.0]);
  });
}
