import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/services/ai_teacher_system/faculty_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/full_lesson_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_cache_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/educational_slide_painter.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/ffmpeg_encoder_io.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/lesson_render_job_builder.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/render_models.dart';
import 'package:mpsc_combine_ai/services/elevenlabs_tts_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Production AI video engine: educational slides + ElevenLabs TTS + FFmpeg → MP4.
///
/// Landscape 1280×720 @ 30 FPS. Low RAM via few keyframes + timed concat encode.
class AiVideoRenderEngine {
  AiVideoRenderEngine({
    ElevenLabsTtsService? elevenLabs,
    FfmpegVideoEncoder? encoder,
    LessonCacheService? cache,
    Directory? videosDirectory,
    Directory? workRootDirectory,
    http.Client? httpClient,
  })  : _eleven = elevenLabs ??
            (httpClient != null
                ? ElevenLabsTtsService(client: httpClient)
                : elevenLabsTtsService),
        _encoder = encoder ?? FfmpegVideoEncoder(),
        _cache = cache ?? lessonCacheService,
        _videosDirectoryOverride = videosDirectory,
        _workRootDirectoryOverride = workRootDirectory;

  final ElevenLabsTtsService _eleven;
  final FfmpegVideoEncoder _encoder;
  final LessonCacheService _cache;
  final Directory? _videosDirectoryOverride;
  final Directory? _workRootDirectoryOverride;

  /// Unique reveal frames per beat (kept tiny for low RAM).
  static const int keyframesPerBeat = 3;

  Future<bool> get canEncode async => _encoder.isAvailable;

  /// Build a render job from a fully prepared Gemini lesson (any topic).
  AiVideoRenderJob jobFromLesson(GeneratedLesson lesson) {
    assertLessonReadyForVideo(lesson);
    return buildRenderJobFromLesson(lesson);
  }

  String _cacheKeyFor(AiVideoRenderJob job) {
    return _cache.keyFor(question: 'dynvideo:${job.topicName.trim().toLowerCase()}');
  }

  Future<String?> _cachedVideoPath(AiVideoRenderJob job) async {
    try {
      final dir = await _videosDir();
      for (final ext in const ['mp4', 'webm']) {
        final f = File(p.join(dir.path, '${_cacheKeyFor(job)}.$ext'));
        if (await f.exists() && await f.length() > 10000) return f.path;
      }
    } catch (_) {}
    return null;
  }

  Future<Directory> _videosDir() async {
    final override = _videosDirectoryOverride;
    if (override != null) {
      if (!await override.exists()) await override.create(recursive: true);
      return override;
    }
    try {
      final root = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(root.path, 'ai_rendered_videos'));
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (_) {
      final dir = Directory(
        p.join(Directory.current.path, 'build', 'ai_rendered_videos'),
      );
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
  }

  Future<Directory> _workDir(String key) async {
    Directory root;
    final override = _workRootDirectoryOverride;
    if (override != null) {
      root = override;
    } else {
      try {
        root = await getTemporaryDirectory();
      } catch (_) {
        root = Directory(p.join(Directory.systemTemp.path, 'mpsc_ai_video'));
      }
    }
    final dir = Directory(p.join(root.path, 'ai_video_work', key));
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
    await dir.create(recursive: true);
    return dir;
  }

  Future<AiVideoRenderResult> render(
    AiVideoRenderJob job, {
    void Function(AiVideoRenderPhase phase, double progress)? onProgress,
    bool force = false,
    GeneratedLesson? sourceLesson,
  }) async {
    void phase(AiVideoRenderPhase p, [double progress = 0]) {
      onProgress?.call(p, progress);
    }

    if (job.scenes.isEmpty) {
      throw StateError('Cannot render: no scenes prepared.');
    }

    phase(AiVideoRenderPhase.preparing, 0.02);
    if (!force) {
      final cached = await _cachedVideoPath(job);
      if (cached != null) {
        phase(AiVideoRenderPhase.done, 1);
        return AiVideoRenderResult(
          filePath: cached,
          mimeType: cached.endsWith('.webm') ? 'video/webm' : 'video/mp4',
          duration: job.totalDuration,
          fromCache: true,
        );
      }
    }

    if (!await _encoder.isAvailable) {
      throw StateError(
        'FFmpeg not available. Install to .tools/ffmpeg/ffmpeg.exe',
      );
    }
    if (!_eleven.isConfigured) {
      throw StateError(
        'ElevenLabs API key missing. Set ELEVENLABS_API_KEY in dart_defines.json.',
      );
    }

    phase(AiVideoRenderPhase.scripting, 0.05);
    final key = _cacheKeyFor(job);
    final work = await _workDir(key);

    phase(AiVideoRenderPhase.synthesizingVoice, 0.08);
    final bundle = await _buildContinuousAudio(job);
    phase(AiVideoRenderPhase.synthesizingVoice, 0.32);
    final timedJob = _applyAudioTimeline(job, bundle);

    phase(AiVideoRenderPhase.composingFrames, 0.35);
    final timedSlides = await _composeTimedSlides(
      timedJob,
      work,
      onProgress: (p) =>
          phase(AiVideoRenderPhase.composingFrames, 0.35 + 0.3 * p),
    );

    final ext = bundle.mimeType.contains('mpeg') ? 'mp3' : 'wav';
    final audioPath = p.join(work.path, 'narration.$ext');
    await File(audioPath).writeAsBytes(bundle.bytes, flush: true);

    phase(AiVideoRenderPhase.encodingVideo, 0.68);
    final videos = await _videosDir();
    final outPath = p.join(videos.path, '$key.mp4');

    await _encoder.encodeTimedSlides(
      workDir: work.path,
      slides: timedSlides,
      audioPath: audioPath,
      outputPath: outPath,
      fps: timedJob.fps,
      onProgress: (p) =>
          phase(AiVideoRenderPhase.encodingVideo, 0.68 + 0.28 * p),
    );

    phase(AiVideoRenderPhase.finalizing, 0.97);
    if (sourceLesson != null) {
      await _cache.write(
        _cache.keyFor(question: timedJob.topicName),
        sourceLesson,
      );
    }

    phase(AiVideoRenderPhase.done, 1);
    return AiVideoRenderResult(
      filePath: outPath,
      mimeType: 'video/mp4',
      duration: timedJob.totalDuration,
      fromCache: false,
    );
  }

  Future<LessonAudioBundle> _buildContinuousAudio(AiVideoRenderJob job) async {
    final lines = <String>[
      for (final scene in job.scenes)
        for (final beat in scene.beats)
          facultyNarration(beat.speakText),
    ].where((s) => s.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      throw StateError('No TTS narration was prepared');
    }
    return FullLessonNarrationService(elevenLabs: _eleven).synthesize(
      scriptLines: lines,
      topic: job.topicName,
      subject: detectMpscTeachingSubject(
        job.topicName,
        hint: job.subjectName,
      ),
    );
  }

  AiVideoRenderJob _applyAudioTimeline(
    AiVideoRenderJob job,
    LessonAudioBundle bundle,
  ) {
    var i = 0;
    final scenes = <RenderScene>[];
    for (final scene in job.scenes) {
      final beats = <RenderNarrationBeat>[];
      for (final beat in scene.beats) {
        var d = beat.duration;
        if (i < bundle.spans.length) {
          final next = bundle.spans[i].end - bundle.spans[i].start;
          if (next > Duration.zero) d = next;
        }
        i++;
        beats.add(
          RenderNarrationBeat(
            speakText: beat.speakText,
            duration: d,
            boardProgress: beat.boardProgress,
            keywords: beat.keywords,
            subtitleCues: beat.subtitleCues,
            isMcq: beat.isMcq,
            isMcqExplain: beat.isMcqExplain,
            pointerLabel: beat.pointerLabel,
          ),
        );
      }
      scenes.add(
        RenderScene(
          id: scene.id,
          title: scene.title,
          visualType: scene.visualType,
          beats: beats,
          bullets: scene.bullets,
          handwriting: scene.handwriting,
          flowchart: scene.flowchart,
          timeline: scene.timeline,
          tableHeaders: scene.tableHeaders,
          tableRows: scene.tableRows,
          mapRegions: scene.mapRegions,
          mcq: scene.mcq,
        ),
      );
    }
    return AiVideoRenderJob(
      topicName: job.topicName,
      subjectName: job.subjectName,
      scenes: scenes,
      targetWidth: job.targetWidth,
      targetHeight: job.targetHeight,
      fps: job.fps,
    );
  }

  /// Paints a few reveal keyframes per beat and assigns hold durations.
  Future<List<({String path, double seconds})>> _composeTimedSlides(
    AiVideoRenderJob job,
    Directory work, {
    void Function(double progress)? onProgress,
  }) async {
    final frameDir = Directory(p.join(work.path, 'frames'));
    await frameDir.create(recursive: true);
    final timed = <({String path, double seconds})>[];
    var totalBeats = 0;
    for (final s in job.scenes) {
      totalBeats += s.beats.length;
    }
    var done = 0;
    var sceneIndex = 0;
    for (final scene in job.scenes) {
      for (final beat in scene.beats) {
        final unique = keyframesPerBeat;
        final sliceSeconds =
            beat.duration.inMilliseconds / 1000.0 / unique;
        for (var k = 0; k < unique; k++) {
          final local = unique == 1 ? 1.0 : k / (unique - 1);
          final board =
              (beat.boardProgress * (0.35 + 0.65 * local)).clamp(0.0, 1.0);
          final painter = EducationalSlidePainter(
            job: job,
            scene: scene,
            beat: RenderNarrationBeat(
              speakText: beat.speakText,
              duration: beat.duration,
              boardProgress: board,
              keywords: beat.keywords,
              subtitleCues: beat.subtitleCues,
              isMcq: beat.isMcq,
              isMcqExplain: beat.isMcqExplain,
              pointerLabel: beat.pointerLabel,
            ),
            localProgress: local,
            sceneIndex: sceneIndex,
            sceneCount: job.scenes.length,
          );
          final bytes = await painter.renderPngBytes();
          final path = p.join(
            frameDir.path,
            's${sceneIndex}_b${done}_k$k.png',
          );
          await File(path).writeAsBytes(bytes, flush: true);
          timed.add((path: path, seconds: sliceSeconds.clamp(0.4, 12.0)));
          await Future<void>.delayed(Duration.zero);
        }
        done++;
        onProgress?.call(done / totalBeats);
      }
      sceneIndex++;
    }
    return timed;
  }
}

final AiVideoRenderEngine aiVideoRenderEngine = AiVideoRenderEngine();
