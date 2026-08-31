import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/chapter_lesson_loader.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_completeness.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_generation_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lecture_lesson_sanitizer.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/teaching_sequence.dart';
import 'package:mpsc_combine_ai/services/personalized_multi_rag_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/verified_content_retrieval.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_lesson_cache_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_lesson_job_status.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_storage_cache_service.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/ai_video_render_engine.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/lesson_render_job_builder.dart';

/// Staged Topic → verified notes → Gemini script → slides → voice → MP4.
///
/// UI keeps using these stages (no classroom redesign). API wire names live on
/// [VideoLessonJobStatus].
enum VideoGenerationStage {
  idle,
  understandingTopic,
  creatingLesson,
  preparingSlides,
  creatingVoice,
  renderingVideo,
  uploading,
  ready,
  failed,
}

extension VideoGenerationStageX on VideoGenerationStage {
  String get labelMr => 'धडा तयार होत आहे…';

  String get labelEn => 'धडा तयार होत आहे…';

  /// Production job status string (queued / generating_* / completed / failed).
  String get apiStatus => toJobStatus.apiName;

  VideoLessonJobStatus get toJobStatus {
    switch (this) {
      case VideoGenerationStage.idle:
      case VideoGenerationStage.understandingTopic:
        return VideoLessonJobStatus.queued;
      case VideoGenerationStage.creatingLesson:
        return VideoLessonJobStatus.generatingScript;
      case VideoGenerationStage.creatingVoice:
        return VideoLessonJobStatus.generatingAudio;
      case VideoGenerationStage.preparingSlides:
        return VideoLessonJobStatus.generatingSlides;
      case VideoGenerationStage.renderingVideo:
      case VideoGenerationStage.uploading:
        return VideoLessonJobStatus.renderingVideo;
      case VideoGenerationStage.ready:
        return VideoLessonJobStatus.completed;
      case VideoGenerationStage.failed:
        return VideoLessonJobStatus.failed;
    }
  }

  double get progressFraction {
    switch (this) {
      case VideoGenerationStage.idle:
      case VideoGenerationStage.failed:
        return 0;
      case VideoGenerationStage.understandingTopic:
        return 0.08;
      case VideoGenerationStage.creatingLesson:
        return 0.28;
      case VideoGenerationStage.preparingSlides:
        return 0.48;
      case VideoGenerationStage.creatingVoice:
        return 0.64;
      case VideoGenerationStage.renderingVideo:
        return 0.84;
      case VideoGenerationStage.uploading:
        return 0.93;
      case VideoGenerationStage.ready:
        return 1;
    }
  }

  bool get isBusy =>
      this != VideoGenerationStage.idle &&
      this != VideoGenerationStage.ready &&
      this != VideoGenerationStage.failed;
}

/// Result of Topic → dynamic educational video lesson.
class VideoGenerationResult {
  const VideoGenerationResult({
    required this.lesson,
    required this.fromCache,
    required this.beats,
    this.videoPath,
    this.videoAssetKey,
    this.videoUrl,
    this.videoMimeType = 'video/mp4',
    this.hasRenderedVideo = false,
    this.educationalPlayback = false,
    this.jobStatus = VideoLessonJobStatus.completed,
    this.usedVerifiedNotes = false,
  });

  final GeneratedLesson lesson;
  final bool fromCache;
  final List<TeachingBeat> beats;
  final String? videoPath;
  final String? videoAssetKey;
  final String? videoUrl;
  final String videoMimeType;
  final bool hasRenderedVideo;

  /// In-app educational slide player (Web / encode unavailable). Not a placeholder MP4.
  final bool educationalPlayback;
  final VideoLessonJobStatus jobStatus;

  /// Internal: true when lesson was grounded in published Firestore notes.
  final bool usedVerifiedNotes;
}

/// Dynamic Topic → verified notes → Gemini → slides → Marathi TTS → MP4.
///
/// Works for ANY student topic that has published Firestore notes.
/// No hardcoded topic names. Cache completed videos locally + Firebase Storage.
class VideoGenerationPipeline {
  VideoGenerationPipeline({
    LessonGenerationService? generation,
    VideoLessonCacheService? videoCache,
    AiVideoRenderEngine? renderEngine,
    VerifiedContentRetrieval? contentRetrieval,
    VideoStorageCacheService? storageCache,
  })  : _generation = generation ?? lessonGenerationService,
        _videoCache = videoCache ?? videoLessonCacheService,
        _renderEngine = renderEngine ?? aiVideoRenderEngine,
        _contentRetrieval = contentRetrieval ?? verifiedContentRetrieval,
        _storageCache = storageCache ?? videoStorageCacheService;

  final LessonGenerationService _generation;
  final VideoLessonCacheService _videoCache;
  final AiVideoRenderEngine _renderEngine;
  final VerifiedContentRetrieval _contentRetrieval;
  final VideoStorageCacheService _storageCache;

  static const Duration _scriptTimeout = Duration(seconds: 180);
  static const Duration _renderTimeout = Duration(minutes: 12);

  Future<VideoGenerationResult> generate({
    required String topic,
    String? subjectContext,
    MpscTeachingSubject? teachingSubject,
    void Function(VideoGenerationStage stage)? onStage,
    void Function(VideoLessonJobStatus status)? onJobStatus,
    bool forceRegenerate = false,
    bool topicOnly = true,
    bool skipQualityRetry = true,
    String studentUid = '',
  }) async {
    final trimmed = topic.trim();
    if (trimmed.isEmpty) {
      throw const LessonGenerationException(
        'कृपया विषय लिहा.\n(Please enter a topic.)',
      );
    }

    void stage(VideoGenerationStage s) {
      onStage?.call(s);
      onJobStatus?.call(s.toJobStatus);
      debugPrint(
        '[VideoPipeline] stage=${s.name} api=${s.apiStatus} topic="$trimmed"',
      );
    }

    try {
      stage(VideoGenerationStage.understandingTopic);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // ── Fast path: local completed video cache ───────────────────────
      if (!forceRegenerate) {
        final cached = await _videoCache.read(trimmed);
        if (cached != null &&
            cached.lesson.slides.length >= kMinEduSlides &&
            cached.hasRenderedVideo &&
            (cached.videoPath ?? '').isNotEmpty) {
          stage(VideoGenerationStage.ready);
          return VideoGenerationResult(
            lesson: cached.lesson,
            fromCache: true,
            beats: teachingSequenceFor(cached.lesson),
            videoPath: cached.videoPath,
            videoMimeType: cached.videoMimeType,
            hasRenderedVideo: true,
            educationalPlayback: false,
            jobStatus: VideoLessonJobStatus.completed,
            usedVerifiedNotes: cached.lesson.isVerifiedNotes,
          );
        }

        // Firebase Storage cache (shared across devices when available).
        final remote = await _storageCache.read(trimmed);
        if (remote != null &&
            remote.localPath != null &&
            remote.localPath!.isNotEmpty) {
          final lesson = cached?.lesson;
          if (lesson != null && lesson.slides.length >= kMinEduSlides) {
            await _videoCache.writeVideo(
              topic: trimmed,
              lesson: lesson,
              videoPath: remote.localPath!,
            );
            stage(VideoGenerationStage.ready);
            return VideoGenerationResult(
              lesson: lesson,
              fromCache: true,
              beats: teachingSequenceFor(lesson),
              videoPath: remote.localPath,
              videoUrl: remote.downloadUrl,
              hasRenderedVideo: true,
              educationalPlayback: false,
              jobStatus: VideoLessonJobStatus.completed,
              usedVerifiedNotes: lesson.isVerifiedNotes,
            );
          }
        }

        if (cached != null && cached.lesson.slides.length >= kMinEduSlides) {
          return _finishFromLesson(
            lesson: cached.lesson,
            topic: trimmed,
            fromCache: true,
            stage: stage,
            usedVerifiedNotes: cached.lesson.isVerifiedNotes,
          );
        }
      }

      // ── Gemini topic lesson (optional verified-notes enrichment) ─────
      stage(VideoGenerationStage.creatingLesson);
      VerifiedTopicSource? verified;
      if (!topicOnly) {
        verified = await _contentRetrieval.tryRetrieve(
          topic: trimmed,
          subjectHint: subjectContext,
        );
        if (verified != null && studentUid.isNotEmpty) {
          final extra = await personalizedMultiRagService.lessonNotesSnippet(
            uid: studentUid,
            requesterUid: studentUid,
            topic: trimmed,
            subjectId: verified.chapter.subjectId,
            chapterId: verified.chapter.id,
          );
          if (extra.isNotEmpty) {
            verified = verified.copyWith(
              notesText: '${verified.notesText}\n\n$extra',
            );
          }
        }
      }

      late GeneratedLesson lesson;
      var usedVerifiedNotes = false;

      if (verified != null) {
        debugPrint(
          '[VideoPipeline] using verified notes '
          'chapter="${verified.chapter.title}" score=${verified.matchScore}',
        );
        usedVerifiedNotes = true;
        final source = verified.toChapterLessonSource();
        lesson = await _generation
            .generateChapterLesson(source: source)
            .timeout(_scriptTimeout);
        lesson = lesson.copyWith(
          question: trimmed,
          topicName: lesson.topicName.trim().isEmpty
              ? verified.chapter.title
              : lesson.topicName,
          subjectName: verified.subjectTitle,
          chapterId: verified.chapter.id,
          subjectId: verified.chapter.subjectId,
          sourceKind: LessonSourceKind.verifiedNotes,
        );
        lesson = await _qualityGate(
          lesson: lesson,
          topic: trimmed,
          subjectContext: verified.subjectTitle,
          verifiedSource: source,
          verifiedChapterTitle: verified.chapter.title,
          verifiedChapterId: verified.chapter.id,
          verifiedSubjectId: verified.chapter.subjectId,
          skipRetry: skipQualityRetry,
        );
      } else {
        // Never show "notes not found" to students — continue with AI lesson.
        debugPrint(
          '[VideoPipeline] no verified notes for "$trimmed" — '
          'dynamic AI lesson fallback (internal label: aiGenerated)',
        );
        lesson = await _generation
            .generateLesson(
              question: trimmed,
              subjectContext: subjectContext,
              teachingSubject: teachingSubject ??
                  tryDetectMpscTeachingSubject(
                    trimmed,
                    hint: subjectContext,
                  ),
            )
            .timeout(_scriptTimeout);
        lesson = lesson.copyWith(
          question: trimmed,
          topicName:
              lesson.topicName.trim().isEmpty ? trimmed : lesson.topicName,
          subjectName: lesson.subjectName.trim().isEmpty
              ? (subjectContext?.trim().isNotEmpty == true
                  ? subjectContext!.trim()
                  : 'MPSC Combine')
              : lesson.subjectName,
          sourceKind: LessonSourceKind.aiGenerated,
        );
        lesson = await _qualityGate(
          lesson: lesson,
          topic: trimmed,
          subjectContext: subjectContext,
          verifiedSource: null,
          verifiedChapterTitle: trimmed,
          verifiedChapterId: '',
          verifiedSubjectId: '',
          skipRetry: skipQualityRetry,
        );
      }

      if (lesson.slides.length < kMinEduSlides) {
        debugPrint(
          '[VideoPipeline] incomplete lesson (${lesson.slides.length} slides)',
        );
        throw const LessonGenerationException(
          'AI धडा तयार करता आला नाही. कृपया पुन्हा प्रयत्न करा.',
        );
      }

      await _videoCache.writeLesson(trimmed, lesson);

      return _finishFromLesson(
        lesson: lesson,
        topic: trimmed,
        fromCache: false,
        stage: stage,
        usedVerifiedNotes: usedVerifiedNotes || lesson.isVerifiedNotes,
      );
    } on TimeoutException catch (e) {
      stage(VideoGenerationStage.failed);
      debugPrint('[VideoPipeline] timeout: $e');
      throw const LessonGenerationException(
        'व्हिडिओ तयार करण्यासाठी वेळ संपला. कृपया पुन्हा प्रयत्न करा.\n'
        '(Video generation timed out. Please retry.)',
      );
    } catch (e) {
      stage(VideoGenerationStage.failed);
      rethrow;
    }
  }

  Future<GeneratedLesson> _qualityGate({
    required GeneratedLesson lesson,
    required String topic,
    String? subjectContext,
    ChapterLessonSource? verifiedSource,
    required String verifiedChapterTitle,
    required String verifiedChapterId,
    required String verifiedSubjectId,
    bool skipRetry = true,
  }) async {
    var current = lessonCompleteness.sanitizeBoardText(lesson);
    if (skipRetry) return current;
    var quality = lessonCompleteness.analyze(current);
    debugPrint(
      '[VideoPipeline] quality ok=${quality.ok} slides=${quality.slideCount} '
      'mains=${quality.mainExplanationCount} sectionMcqs=${quality.sectionMcqCount} '
      'source=${current.sourceKind.name} gaps=${quality.gaps.length}',
    );

    if (!quality.ok || current.slides.length < kMinEduSlides) {
      try {
        GeneratedLesson retry;
        if (verifiedSource != null) {
          retry = await _generation
              .regenerateChapterLessonForQuality(
                source: verifiedSource,
                qualityRepairInstruction:
                    lessonCompleteness.retryInstruction(quality),
              )
              .timeout(_scriptTimeout);
          retry = retry.copyWith(
            question: topic,
            topicName: verifiedChapterTitle,
            subjectName: verifiedSource.subjectTitle,
            chapterId: verifiedChapterId,
            subjectId: verifiedSubjectId,
            sourceKind: LessonSourceKind.verifiedNotes,
          );
        } else {
          retry = await _generation
              .generateLesson(
                question: topic,
                subjectContext:
                    '${subjectContext ?? ''}\n${lessonCompleteness.retryInstruction(quality)}',
                teachingSubject: detectMpscTeachingSubject(
                  topic,
                  hint: subjectContext,
                ),
              )
              .timeout(_scriptTimeout);
          retry = retry.copyWith(
            question: topic,
            sourceKind: LessonSourceKind.aiGenerated,
          );
        }
        final repaired = lessonCompleteness.sanitizeBoardText(retry);
        final retryQuality = lessonCompleteness.analyze(repaired);
        debugPrint(
          '[VideoPipeline] quality-retry ok=${retryQuality.ok} '
          'slides=${retryQuality.slideCount} gaps=${retryQuality.gaps.length}',
        );
        if (retryQuality.ok ||
            repaired.slides.length > current.slides.length ||
            retryQuality.gaps.length < quality.gaps.length) {
          current = repaired;
          quality = retryQuality;
        }
      } catch (e) {
        debugPrint('Gemini quality retry skipped: $e');
      }
    }

    if (!quality.ok) {
      debugPrint(
        '[VideoPipeline] proceeding with residual quality gaps: '
        '${quality.gaps.join(' | ')}',
      );
    }
    return current;
  }

  Future<VideoGenerationResult> _finishFromLesson({
    required GeneratedLesson lesson,
    required String topic,
    required bool fromCache,
    required void Function(VideoGenerationStage stage) stage,
    bool usedVerifiedNotes = false,
  }) async {
    final clean = sanitizeLectureLesson(lesson);
    stage(VideoGenerationStage.preparingSlides);
    if (clean.slides.isEmpty) {
      throw const LessonGenerationException(
        'स्लाइड्स तयार झाल्या नाहीत. व्हिडिओ सुरू करता येणार नाही.\n'
        '(Slides were not prepared. Cannot start video.)',
      );
    }

    final beats = teachingSequenceFor(clean);

    // Audio-first: never block the student on FFmpeg. MP4 continues in the
    // lesson queue after playback can already start.
    stage(VideoGenerationStage.ready);
    return VideoGenerationResult(
      lesson: clean,
      fromCache: fromCache,
      beats: beats,
      hasRenderedVideo: false,
      educationalPlayback: true,
      jobStatus: VideoLessonJobStatus.completed,
      usedVerifiedNotes: usedVerifiedNotes || clean.isVerifiedNotes,
    );
  }

  /// Native-only MP4 mux (slides + continuous narration). Web returns null.
  Future<VideoGenerationResult?> renderMp4({
    required GeneratedLesson lesson,
    required String topic,
    bool forceRegenerate = false,
  }) async {
    if (!await _renderEngine.canEncode) return null;
    final clean = sanitizeLectureLesson(lesson);
    final renderJob = _renderEngine.jobFromLesson(clean);
    try {
      final result = await _renderEngine
          .render(
            renderJob,
            force: forceRegenerate,
            sourceLesson: clean,
          )
          .timeout(_renderTimeout);
      return VideoGenerationResult(
        lesson: clean,
        fromCache: result.fromCache,
        beats: teachingSequenceFor(clean),
        videoPath: result.filePath,
        videoMimeType: result.mimeType,
        hasRenderedVideo: true,
        educationalPlayback: false,
        jobStatus: VideoLessonJobStatus.completed,
        usedVerifiedNotes: clean.isVerifiedNotes,
      );
    } catch (e) {
      debugPrint('Background MP4 render skipped: $e');
      return null;
    }
  }
}
