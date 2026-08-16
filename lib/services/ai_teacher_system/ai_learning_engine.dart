import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mpsc_combine_ai/models/ai_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_chapter_debug.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_repository.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/full_lesson_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_cache_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_generation_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/media_bytes_cache.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/teaching_sequence.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_generation_pipeline.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';

/// Production AI learning pack: video lecture + notes + MCQs + PYQs + revision.
class AiLearningPack {
  const AiLearningPack({
    required this.lesson,
    required this.subject,
    this.audio,
    this.fromCache = false,
  });

  final GeneratedLesson lesson;
  final MpscTeachingSubject subject;
  final LessonAudioBundle? audio;
  final bool fromCache;

  bool get hasAudio => audio != null && audio!.bytes.isNotEmpty;
}

/// Topic → subject teacher → Gemini lesson → cleaned script → ElevenLabs.
///
/// No PDF upload. No student-visible backend stages. Cached lessons replay
/// instantly. MP4 ffmpeg is never on the student wait path.
class AiLearningEngine {
  AiLearningEngine({
    VideoGenerationPipeline? pipeline,
    LessonGenerationService? generation,
    FullLessonNarrationService? narration,
    LessonCacheService? cache,
    AiLessonRepository? lessons,
  })  : _pipeline = pipeline ?? VideoGenerationPipeline(),
        _generation = generation ?? lessonGenerationService,
        _narration = narration ?? fullLessonNarrationService,
        _cache = cache ?? lessonCacheService,
        _lessons = lessons ?? aiLessonRepository;

  final VideoGenerationPipeline _pipeline;
  final LessonGenerationService _generation;
  final FullLessonNarrationService _narration;
  final LessonCacheService _cache;
  final AiLessonRepository _lessons;

  static const int targetMcqCount = 20;
  static const int targetPyqCount = 10;

  String cacheKeyFor({
    required String topic,
    String chapterId = '',
    String subjectId = '',
  }) {
    return _cache.keyFor(
      question: topic,
      chapterId: chapterId,
      subjectId: subjectId,
    );
  }

  Future<GeneratedLesson> buildLesson({
    required String topic,
    String? subjectContext,
    String chapterId = '',
    String subjectId = '',
    bool forceRegenerate = false,
    MpscTeachingSubject? teachingSubject,
  }) async {
    final trimmed = topic.trim();
    if (trimmed.isEmpty) {
      throw const LessonGenerationException(
        'कृपया विषय लिहा. (Please enter a topic.)',
      );
    }

    final detected = teachingSubject ??
        detectMpscTeachingSubject(trimmed, hint: subjectContext);
    aiChapterLog('topic_received', {
      'topic': trimmed,
      'detected_subject': detected.nameEn,
    });

    final key = cacheKeyFor(
      topic: trimmed,
      chapterId: chapterId,
      subjectId: subjectId.isNotEmpty ? subjectId : detected.id,
    );

    if (!forceRegenerate) {
      final cached = await _cache.read(key);
      if (cached != null &&
          _hasDisplayableChapter(cached) &&
          !isPlaceholderLesson(cached, topic: trimmed)) {
        aiChapterLog('cache_hit_local', {'title': cached.topicName});
        return _withIds(cached, chapterId: chapterId, subjectId: subjectId);
      }
      final uid = authService.currentUser?.uid;
      if (uid != null) {
        try {
          final remote = await _lessons.get(
            _lessons.docIdFor(uid: uid, topic: trimmed),
          );
          if (remote != null &&
              remote.isReady &&
              remote.lesson != null &&
              _hasDisplayableChapter(remote.lesson!) &&
              !isPlaceholderLesson(remote.lesson!, topic: trimmed)) {
            final lesson = _withIds(
              remote.lesson!,
              chapterId: chapterId.isNotEmpty ? chapterId : remote.chapterId,
              subjectId: subjectId.isNotEmpty ? subjectId : remote.subjectId,
            );
            unawaited(_cache.write(key, lesson));
            aiChapterLog('cache_hit_firestore', {'title': lesson.topicName});
            return lesson;
          }
        } catch (e) {
          aiChapterLog('firestore_cache_skip', {'error': '$e'});
        }
      }
    }

    aiChapterLog('gemini_generate_start', {
      'topic': trimmed,
      'subject': detected.nameEn,
    });
    final generated = await _generation.generateLesson(
      question: trimmed,
      subjectContext: subjectContext ?? detected.displayName,
      teachingSubject: detected,
    );
    final lesson = _withIds(
      generated,
      chapterId: chapterId,
      subjectId: subjectId,
    );
    _logChapter(lesson);
    try {
      await _cache.write(key, lesson);
    } catch (e) {
      aiChapterLog('local_cache_write_fail', {'error': '$e'});
    }
    unawaited(_persistLesson(lesson, trimmed));
    return lesson;
  }

  bool _hasDisplayableChapter(GeneratedLesson lesson) {
    return lesson.slides.isNotEmpty ||
        lesson.notes.isNotEmpty ||
        lesson.summary.trim().isNotEmpty ||
        lesson.premium.introduction.trim().isNotEmpty;
  }

  void _logChapter(GeneratedLesson lesson) {
    aiChapterLog('chapter_object', {
      'title': lesson.topicName,
      'subject': lesson.subjectName,
      'sections': lesson.slides.length,
      'notes': lesson.notes.isNotEmpty ||
          lesson.summary.trim().isNotEmpty ||
          lesson.premium.introduction.trim().isNotEmpty,
      'tricks': lesson.premium.memoryTricks.isNotEmpty,
      'revision': lesson.premium.quickRevision.trim().isNotEmpty,
      'mcqs': lesson.mcqs.length,
      'pyqs': lesson.pyqs.length,
    });
  }

  Future<LessonAudioBundle> narrate({
    required GeneratedLesson lesson,
    required String topic,
    MpscTeachingSubject? subject,
  }) async {
    final style = subject ??
        detectMpscTeachingSubject(topic, hint: lesson.subjectName);
    final script = _narration.buildLectureScript(
      beats: teachingSequenceFor(lesson),
      scriptLines: lesson.script,
    );
    final audioKey =
        'tts_${sha256.convert(utf8.encode(script)).toString().substring(0, 24)}';
    final cachedBytes = mediaBytesCache.read(audioKey);
    if (cachedBytes != null && cachedBytes.isNotEmpty) {
      final duration = Duration(
        milliseconds: (script.length * 72).clamp(8000, 240000),
      );
      return LessonAudioBundle(
        bytes: cachedBytes,
        mimeType: 'audio/mpeg',
        duration: duration,
        script: script,
        spans: beatSpansFor(
          texts: lesson.script.isNotEmpty ? lesson.script : [script],
          total: duration,
        ),
      );
    }

    final audio = await _narration.synthesize(
      beats: teachingSequenceFor(lesson),
      scriptLines: lesson.script,
      subject: style,
      topic: topic,
    );
    mediaBytesCache.write(audioKey, audio.bytes);
    return audio;
  }

  Future<AiLearningPack> generatePack({
    required String topic,
    String? subjectContext,
    String chapterId = '',
    String subjectId = '',
    bool forceRegenerate = false,
    MpscTeachingSubject? teachingSubject,
  }) async {
    final lesson = await buildLesson(
      topic: topic,
      subjectContext: subjectContext,
      chapterId: chapterId,
      subjectId: subjectId,
      forceRegenerate: forceRegenerate,
      teachingSubject: teachingSubject,
    );
    final subject = teachingSubject ??
        detectMpscTeachingSubject(
          topic,
          hint: subjectContext ?? lesson.subjectName,
        );
    LessonAudioBundle? audio;
    try {
      audio = await narrate(lesson: lesson, topic: topic, subject: subject);
    } catch (e) {
      debugPrint('[AiLearningEngine] narration skipped: $e');
    }
    return AiLearningPack(
      lesson: lesson,
      subject: subject,
      audio: audio,
      fromCache: false,
    );
  }

  GeneratedLesson _withIds(
    GeneratedLesson lesson, {
    required String chapterId,
    required String subjectId,
  }) {
    return lesson.copyWith(
      chapterId: chapterId.isNotEmpty ? chapterId : lesson.chapterId,
      subjectId: subjectId.isNotEmpty ? subjectId : lesson.subjectId,
    );
  }

  Future<void> _persistLesson(GeneratedLesson lesson, String topic) async {
    final uid = authService.currentUser?.uid;
    if (uid == null) {
      aiChapterLog('firestore_save', {
        'success': false,
        'error': 'not_signed_in',
      });
      return;
    }
    try {
      final id = await _lessons.enqueue(
        uid: uid,
        topic: topic,
        chapterId: lesson.chapterId,
        subjectId: lesson.subjectId,
        subjectTitle: lesson.subjectName,
      );
      await _lessons.markReady(
        id: id,
        lesson: lesson,
        audioUrl: '',
        videoUrl: '',
        thumbnailUrl: '',
        duration: 0,
        playbackMode: AiLessonPlayback.educational,
      );
      await _lessons.doc(id).set({
        'subject': lesson.subjectName,
        'userId': uid,
        'notes': lesson.notes,
        'memoryTricks': lesson.premium.memoryTricks,
        'revision': lesson.premium.quickRevision,
        'mcqs': lesson.mcqs.map((m) => m.toMap()).toList(),
        'pyqs': lesson.pyqs.map((p) => p.toMap()).toList(),
        'slides': lesson.slides.map((s) => s.toMap()).toList(),
      }, SetOptions(merge: true));
      aiChapterLog('firestore_save', {'success': true, 'id': id});
    } catch (e) {
      aiChapterLog('firestore_save', {'success': false, 'error': '$e'});
    }
  }
}

final AiLearningEngine aiLearningEngine = AiLearningEngine();
