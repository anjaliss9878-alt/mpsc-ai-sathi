import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/ai_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_generation_pipeline.dart';
import 'package:mpsc_combine_ai/utils/student_media.dart';

void main() {
  test('ai_lessons status wire values match production spec', () {
    expect(AiLessonStatus.queued.wire, 'queued');
    expect(AiLessonStatus.generating.wire, 'generating');
    expect(AiLessonStatus.ready.wire, 'ready');
    expect(AiLessonStatus.failed.wire, 'failed');
  });

  test('student-facing lesson errors never leak URLs or HTTP', () {
    final msg = studentFacingLessonMessage(
      'Gemini TTS failed HTTP 429 firebasestorage.googleapis.com/v0/b/x',
    );
    expect(msg.toLowerCase(), isNot(contains('http')));
    expect(msg.toLowerCase(), isNot(contains('firebase')));
    expect(msg, isNot(contains('googleapis')));
    expect(
      msg,
      anyOf(
        'Voice generation is taking longer than expected',
        'Retrying automatically',
        'Lesson will be available shortly',
        'Video is being prepared',
      ),
    );
  });

  test('media helpers never treat storage paths as display names', () {
    expect(
      friendlyAttachmentName(
        'https://firebasestorage.googleapis.com/v0/b/x/o/notes%2Fa.pdf',
      ),
      'Notes',
    );
    expect(looksLikeUrl('gs://bucket/audio/x.wav'), isTrue);
    expect(looksLikeUrl('audio/lesson.wav'), isFalse);
  });

  test('pipeline uploading stage maps to rendering_video api status', () {
    expect(VideoGenerationStage.uploading.apiStatus, 'rendering_video');
    expect(VideoGenerationStage.uploading.progressFraction, closeTo(0.93, 0.001));
  });

  test('AiLesson fromMap stores storage paths not display URLs', () {
    final lesson = AiLesson.fromMap({
      'uid': 'u1',
      'topic': 'संसद',
      'status': 'ready',
      'stage': 'ready',
      'progress': 100,
      'audioUrl': 'audio/u1_abc.wav',
      'videoUrl': 'videos/ai_lessons/u1_abc.mp4',
      'thumbnailUrl': 'thumbnails/u1_abc.jpg',
      'script': ['नमस्कार'],
    }, 'id1');
    expect(lesson.audioUrl.startsWith('http'), isFalse);
    expect(lesson.videoUrl.startsWith('videos/'), isTrue);
    expect(lesson.isReady, isTrue);
  });
}
