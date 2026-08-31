import 'dart:async';
import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:mpsc_combine_ai/models/ai_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_asset_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_lesson_repository.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/full_lesson_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/teaching_sequence.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_generation_pipeline.dart';

/// Background lesson queue. Max [maxParallel] renders at once.
class AiLessonQueue {
  AiLessonQueue({
    AiLessonRepository? repository,
    VideoGenerationPipeline? pipeline,
    AiLessonAssetService? assets,
    int maxParallel = 2,
  })  : _repo = repository ?? aiLessonRepository,
        _pipeline = pipeline ?? VideoGenerationPipeline(),
        _assets = assets ?? aiLessonAssetService,
        maxParallel = maxParallel < 1 ? 1 : maxParallel;

  final AiLessonRepository _repo;
  final VideoGenerationPipeline _pipeline;
  final AiLessonAssetService _assets;
  final int maxParallel;

  final Queue<String> _waiting = Queue<String>();
  final Set<String> _running = <String>{};
  final Set<String> _queuedIds = <String>{};

  int get runningCount => _running.length;
  int get waitingCount => _waiting.length;

  void submit(String lessonId) {
    final id = lessonId.trim();
    if (id.isEmpty) return;
    if (_running.contains(id) || _queuedIds.contains(id)) return;
    _queuedIds.add(id);
    _waiting.add(id);
    _pump();
  }

  void _pump() {
    while (_running.length < maxParallel && _waiting.isNotEmpty) {
      final id = _waiting.removeFirst();
      _queuedIds.remove(id);
      _running.add(id);
      unawaited(_run(id).whenComplete(() {
        _running.remove(id);
        _pump();
      }));
    }
  }

  Future<void> _run(String id) async {
    final job = await _repo.get(id);
    if (job == null) return;
    if (job.isReady && job.lesson != null) return;

    await _repo.updateProgress(
      id: id,
      status: AiLessonStatus.generating,
      stage: AiLessonStage.preparing,
      progress: 6,
      friendlyMessage: 'धडा तयार होत आहे…',
      logMessage: 'Worker started',
    );

    try {
      final result = await _pipeline.generate(
        topic: job.topic,
        subjectContext: job.subjectTitle.isNotEmpty
            ? job.subjectTitle
            : job.subjectId,
        forceRegenerate: job.videoUrl.isEmpty && job.audioUrl.isEmpty,
        studentUid: job.uid,
        onStage: (stage) {
          unawaited(_onPipelineStage(id, stage));
        },
      );

      await _repo.updateProgress(
        id: id,
        status: AiLessonStatus.generating,
        stage: AiLessonStage.generatingVoice,
        progress: 40,
        friendlyMessage: 'धडा तयार होत आहे…',
        logMessage: 'Synthesizing Marathi narration',
      );

      var audioPath = job.audioUrl;
      var audioSeconds = 0.0;
      try {
        final uploaded = await _uploadNarration(
          lessonId: id,
          lesson: result.lesson,
          topic: job.topic,
        );
        audioPath = uploaded.path;
        audioSeconds = uploaded.duration.inMilliseconds / 1000.0;
      } catch (e) {
        debugPrint('[AiLessonQueue] audio upload: $e');
        await _repo.updateProgress(
          id: id,
          status: AiLessonStatus.generating,
          stage: AiLessonStage.generatingVoice,
          progress: 48,
          friendlyMessage: 'धडा तयार होत आहे…',
          errorMessage: '$e',
          logMessage: 'TTS/audio: $e',
        );
      }

      if (audioPath.trim().isEmpty) {
        await _repo.markFailed(
          id: id,
          technicalError: 'Marathi lecture audio was not generated',
        );
        return;
      }

      await _repo.updateProgress(
        id: id,
        status: AiLessonStatus.generating,
        stage: AiLessonStage.renderingVideo,
        progress: 70,
        friendlyMessage: 'Creating video...',
        logMessage: 'Rendering slides + audio',
      );

      if (kIsWeb) {
        await _repo.doc(id).set({
          'audioUrl': audioPath,
          'duration': audioSeconds,
          'status': AiLessonStatus.generating.wire,
          'lesson': result.lesson.toMap(),
          'script': result.lesson.script,
        }, SetOptions(merge: true));
        return;
      }

      final rendered = await _pipeline.renderMp4(
        lesson: result.lesson,
        topic: job.topic,
      );
      final local = rendered?.videoPath ?? '';
      if (local.isEmpty) {
        await _repo.markFailed(
          id: id,
          technicalError: 'Video rendering failed',
        );
        return;
      }
      final uploaded = await _assets.uploadVideoFile(
        lessonId: id,
        localPath: local,
      );
      if (uploaded == null || uploaded.isEmpty) {
        await _repo.markFailed(
          id: id,
          technicalError: 'Firebase video upload failed',
        );
        return;
      }
      final playback = await _assets.playbackUrl(uploaded);
      final duration = audioSeconds > 1
          ? audioSeconds
          : result.lesson.script.join(' ').length / 12.0;
      await _repo.markReady(
        id: id,
        lesson: result.lesson,
        audioUrl: audioPath,
        videoUrl: uploaded,
        finalVideoUrl: playback,
        thumbnailUrl: job.thumbnailUrl,
        duration: duration,
        playbackMode: AiLessonPlayback.video,
      );
    } catch (e, st) {
      debugPrint('[AiLessonQueue] failed $id: $e\n$st');
      await _repo.markFailed(id: id, technicalError: '$e');
    }
  }

  Future<void> _onPipelineStage(String id, VideoGenerationStage stage) {
    final mapped = _mapStage(stage);
    return _repo.updateProgress(
      id: id,
      status: stage == VideoGenerationStage.failed
          ? AiLessonStatus.failed
          : (stage == VideoGenerationStage.ready
              ? AiLessonStatus.generating
              : AiLessonStatus.generating),
      stage: mapped,
      progress: mapped.progressStart,
      friendlyMessage: mapped.labelEn,
      logMessage: stage.labelEn,
    );
  }

  AiLessonStage _mapStage(VideoGenerationStage stage) {
    switch (stage) {
      case VideoGenerationStage.idle:
      case VideoGenerationStage.understandingTopic:
      case VideoGenerationStage.creatingLesson:
        return AiLessonStage.preparing;
      case VideoGenerationStage.creatingVoice:
        return AiLessonStage.generatingVoice;
      case VideoGenerationStage.preparingSlides:
        return AiLessonStage.creatingScenes;
      case VideoGenerationStage.renderingVideo:
        return AiLessonStage.renderingVideo;
      case VideoGenerationStage.uploading:
        return AiLessonStage.uploading;
      case VideoGenerationStage.ready:
        return AiLessonStage.generatingVoice;
      case VideoGenerationStage.failed:
        return AiLessonStage.preparing;
    }
  }

  Future<({String path, Duration duration})> _uploadNarration({
    required String lessonId,
    required GeneratedLesson lesson,
    required String topic,
  }) async {
    final beats = teachingSequenceFor(lesson);
    final bundle = await fullLessonNarrationService.synthesize(
      beats: beats,
      scriptLines: lesson.script,
      subject: detectMpscTeachingSubject(
        topic,
        hint: lesson.subjectName,
      ),
      topic: topic,
    );
    final isMp3 = bundle.mimeType.contains('mpeg') || bundle.mimeType.contains('mp3');
    final path = await _assets.uploadAudio(
      lessonId: lessonId,
      bytes: bundle.bytes,
      contentType: isMp3 ? 'audio/mpeg' : 'audio/wav',
      ext: isMp3 ? 'mp3' : 'wav',
    );
    return (path: path, duration: bundle.duration);
  }
}

final AiLessonQueue aiLessonQueue = AiLessonQueue();
