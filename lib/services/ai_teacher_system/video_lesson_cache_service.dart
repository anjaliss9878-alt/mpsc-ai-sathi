import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_cache_service.dart';
import '../tts_io_stub.dart' if (dart.library.io) '../tts_io_impl.dart' as tts_io;

/// Cached completed AI video lesson for fast replay (any dynamic topic).
class CachedVideoLesson {
  const CachedVideoLesson({
    required this.topic,
    required this.lesson,
    this.videoPath,
    this.videoMimeType = 'video/mp4',
    this.hasRenderedVideo = false,
  });

  final String topic;
  final GeneratedLesson lesson;
  final String? videoPath;
  final String videoMimeType;
  final bool hasRenderedVideo;
}

/// Stores Gemini lesson JSON + completed MP4 path keyed by normalized topic.
///
/// Cache hit = faster playback. Cache miss / force = fresh Gemini generation.
class VideoLessonCacheService {
  VideoLessonCacheService({LessonCacheService? lessonCache})
      : _lessons = lessonCache ?? lessonCacheService;

  final LessonCacheService _lessons;
  final Map<String, CachedVideoLesson> _memory = {};

  String keyForTopic(String topic) {
    final material = 'dynvideo|${topic.trim().toLowerCase()}';
    return sha256.convert(utf8.encode(material)).toString().substring(0, 32);
  }

  Future<CachedVideoLesson?> read(String topic) async {
    final key = keyForTopic(topic);
    final mem = _memory[key];
    if (mem != null && mem.lesson.slides.length >= 8) {
      // Re-validate video file on IO when present.
      if (mem.hasRenderedVideo && mem.videoPath != null && !kIsWeb) {
        final ok = await tts_io.cacheFileExists(mem.videoPath!);
        if (!ok) {
          return CachedVideoLesson(
            topic: mem.topic,
            lesson: mem.lesson,
            hasRenderedVideo: false,
          );
        }
      }
      return mem;
    }

    final lesson = await _lessons.read(_lessons.keyFor(question: topic.trim()));
    if (lesson == null || lesson.slides.length < 8) return null;

    String? videoPath;
    var mime = 'video/mp4';
    if (!kIsWeb) {
      final meta = await tts_io.readTtsCacheFile('videometa_$key', ext: 'json');
      if (meta != null) {
        try {
          final map = jsonDecode(utf8.decode(meta.bytes)) as Map<String, dynamic>;
          final path = (map['videoPath'] as String?)?.trim() ?? '';
          mime = (map['mimeType'] as String?) ?? 'video/mp4';
          if (path.isNotEmpty && await tts_io.cacheFileExists(path)) {
            videoPath = path;
          }
        } catch (_) {}
      }
    }

    final cached = CachedVideoLesson(
      topic: topic.trim(),
      lesson: lesson,
      videoPath: videoPath,
      videoMimeType: mime,
      hasRenderedVideo: videoPath != null,
    );
    _memory[key] = cached;
    return cached;
  }

  Future<void> writeLesson(String topic, GeneratedLesson lesson) async {
    final key = keyForTopic(topic);
    await _lessons.write(_lessons.keyFor(question: topic.trim()), lesson);
    final prev = _memory[key];
    _memory[key] = CachedVideoLesson(
      topic: topic.trim(),
      lesson: lesson,
      videoPath: prev?.videoPath,
      videoMimeType: prev?.videoMimeType ?? 'video/mp4',
      hasRenderedVideo: prev?.hasRenderedVideo ?? false,
    );
  }

  Future<void> writeVideo({
    required String topic,
    required GeneratedLesson lesson,
    required String videoPath,
    String mimeType = 'video/mp4',
  }) async {
    final key = keyForTopic(topic);
    await writeLesson(topic, lesson);

    if (!kIsWeb) {
      try {
        final meta = jsonEncode({
          'topic': topic.trim(),
          'videoPath': videoPath,
          'mimeType': mimeType,
          'cachedAt': DateTime.now().toIso8601String(),
        });
        await tts_io.writeTtsCacheFile(
          'videometa_$key',
          utf8.encode(meta),
          ext: 'json',
        );
      } catch (e) {
        debugPrint('VideoLessonCacheService writeVideo: $e');
      }
    }

    _memory[key] = CachedVideoLesson(
      topic: topic.trim(),
      lesson: lesson,
      videoPath: videoPath,
      videoMimeType: mimeType,
      hasRenderedVideo: true,
    );
  }
}

final VideoLessonCacheService videoLessonCacheService = VideoLessonCacheService();
