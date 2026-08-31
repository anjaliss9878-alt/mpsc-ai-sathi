import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';

/// Production AI Classroom job stored at `ai_lessons/{id}`.
///
/// [audioUrl], [videoUrl], and [thumbnailUrl] hold Firebase Storage *paths*
/// (never signed HTTPS URLs). Players resolve them with getDownloadURL.
class AiLesson {
  const AiLesson({
    required this.id,
    required this.uid,
    required this.topic,
    this.chapterId = '',
    this.subjectId = '',
    this.subjectTitle = '',
    this.examId = '',
    this.targetGroup = '',
    this.topicId = '',
    this.status = AiLessonStatus.queued,
    this.stage = AiLessonStage.preparing,
    this.progress = 0,
    this.script = const [],
    this.pdfPath = '',
    this.audioUrl = '',
    this.videoUrl = '',
    this.finalVideoUrl = '',
    this.thumbnailUrl = '',
    this.duration = 0,
    this.errorMessage = '',
    this.friendlyMessage = '',
    this.playbackMode = AiLessonPlayback.educational,
    this.logs = const [],
    this.lesson,
    this.createdAt,
    this.updatedAt,
    this.etaSeconds = 45,
  });

  final String id;
  final String uid;
  final String topic;
  final String chapterId;
  final String subjectId;
  final String subjectTitle;
  final String examId;
  final String targetGroup;
  final String topicId;
  final AiLessonStatus status;
  final AiLessonStage stage;
  final int progress;
  final List<String> script;
  final String pdfPath;
  final String audioUrl;
  final String videoUrl;
  /// Verified playback URL or Storage path for the muxed MP4. Never show in UI.
  final String finalVideoUrl;
  final String thumbnailUrl;
  final double duration;
  final String errorMessage;
  final String friendlyMessage;
  final AiLessonPlayback playbackMode;
  final List<AiLessonLog> logs;
  final GeneratedLesson? lesson;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int etaSeconds;

  bool get isQueued => status == AiLessonStatus.queued;
  bool get isGenerating => status == AiLessonStatus.generating;
  bool get isReady => status == AiLessonStatus.ready;
  bool get isFailed => status == AiLessonStatus.failed;
  bool get isActive => isQueued || isGenerating;
  bool get hasVideo =>
      videoUrl.trim().isNotEmpty || finalVideoUrl.trim().isNotEmpty;
  bool get hasAudio => audioUrl.trim().isNotEmpty;
  bool get isPlayable => isReady && hasAudio && hasVideo;

  factory AiLesson.fromMap(Map<String, dynamic> map, String id) {
    final rawLesson = map['lesson'];
    return AiLesson(
      id: id,
      uid: map['uid'] as String? ?? '',
      topic: map['topic'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      subjectId: map['subjectId'] as String? ?? '',
      subjectTitle: map['subjectTitle'] as String? ?? '',
      examId: map['examId'] as String? ?? '',
      targetGroup: map['targetGroup'] as String? ?? '',
      topicId: map['topicId'] as String? ?? '',
      status: AiLessonStatusX.parse(map['status'] as String?),
      stage: AiLessonStageX.parse(map['stage'] as String?),
      progress: (map['progress'] as num?)?.round().clamp(0, 100) ?? 0,
      script: (map['script'] as List?)
              ?.map((e) => '$e')
              .where((s) => s.trim().isNotEmpty)
              .toList() ??
          const [],
      pdfPath: map['pdfPath'] as String? ?? '',
      audioUrl: map['audioUrl'] as String? ?? map['audioPath'] as String? ?? '',
      videoUrl: map['videoUrl'] as String? ?? map['videoPath'] as String? ?? '',
      finalVideoUrl: map['finalVideoUrl'] as String? ?? '',
      thumbnailUrl:
          map['thumbnailUrl'] as String? ?? map['thumbnailPath'] as String? ?? '',
      duration: (map['duration'] as num?)?.toDouble() ?? 0,
      errorMessage: map['errorMessage'] as String? ?? '',
      friendlyMessage: map['friendlyMessage'] as String? ?? '',
      playbackMode: AiLessonPlaybackX.parse(map['playbackMode'] as String?),
      logs: (map['logs'] as List?)
              ?.whereType<Map>()
              .map((e) => AiLessonLog.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      lesson: rawLesson is Map
          ? GeneratedLesson.fromMap(Map<String, dynamic>.from(rawLesson), id)
          : null,
      createdAt: _readTime(map['createdAt']),
      updatedAt: _readTime(map['updatedAt']),
      etaSeconds: (map['etaSeconds'] as num?)?.round() ?? 0,
    );
  }

  Map<String, dynamic> toMap({bool includeTimestamps = false}) {
    return {
      'uid': uid,
      'topic': topic,
      'chapterId': chapterId,
      'subjectId': subjectId,
      'subjectTitle': subjectTitle,
      'examId': examId,
      'targetGroup': targetGroup,
      'topicId': topicId,
      'status': status.wire,
      'stage': stage.wire,
      'progress': progress.clamp(0, 100),
      'script': script,
      'pdfPath': pdfPath,
      'audioUrl': audioUrl,
      'videoUrl': videoUrl,
      'finalVideoUrl': finalVideoUrl,
      'thumbnailUrl': thumbnailUrl,
      'duration': duration,
      'errorMessage': errorMessage,
      'friendlyMessage': friendlyMessage,
      'playbackMode': playbackMode.wire,
      'logs': logs.map((e) => e.toMap()).toList(),
      if (lesson != null) 'lesson': lesson!.toMap(),
      'etaSeconds': etaSeconds,
      if (includeTimestamps) ...{
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      },
    };
  }

  static DateTime? _readTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

class AiLessonLog {
  const AiLessonLog({
    required this.at,
    required this.stage,
    required this.message,
  });

  final DateTime at;
  final String stage;
  final String message;

  Map<String, dynamic> toMap() => {
        'at': at.toIso8601String(),
        'stage': stage,
        'message': message,
      };

  factory AiLessonLog.fromMap(Map<String, dynamic> map) {
    return AiLessonLog(
      at: DateTime.tryParse(map['at'] as String? ?? '') ?? DateTime.now(),
      stage: map['stage'] as String? ?? '',
      message: map['message'] as String? ?? '',
    );
  }
}

enum AiLessonStatus { queued, generating, ready, failed }

extension AiLessonStatusX on AiLessonStatus {
  String get wire {
    switch (this) {
      case AiLessonStatus.queued:
        return 'queued';
      case AiLessonStatus.generating:
        return 'generating';
      case AiLessonStatus.ready:
        return 'ready';
      case AiLessonStatus.failed:
        return 'failed';
    }
  }

  static AiLessonStatus parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'generating':
      case 'generating_script':
      case 'generating_audio':
      case 'generating_slides':
      case 'rendering_video':
        return AiLessonStatus.generating;
      case 'ready':
      case 'completed':
        return AiLessonStatus.ready;
      case 'failed':
        return AiLessonStatus.failed;
      default:
        return AiLessonStatus.queued;
    }
  }
}

enum AiLessonStage {
  preparing,
  generatingVoice,
  creatingScenes,
  renderingVideo,
  uploading,
  ready,
}

extension AiLessonStageX on AiLessonStage {
  String get wire {
    switch (this) {
      case AiLessonStage.preparing:
        return 'preparing';
      case AiLessonStage.generatingVoice:
        return 'generating_voice';
      case AiLessonStage.creatingScenes:
        return 'creating_scenes';
      case AiLessonStage.renderingVideo:
        return 'rendering_video';
      case AiLessonStage.uploading:
        return 'uploading';
      case AiLessonStage.ready:
        return 'ready';
    }
  }

  String get labelEn => 'धडा तयार होत आहे…';

  String get labelMr => 'धडा तयार होत आहे…';

  int get progressStart {
    switch (this) {
      case AiLessonStage.preparing:
        return 5;
      case AiLessonStage.generatingVoice:
        return 22;
      case AiLessonStage.creatingScenes:
        return 48;
      case AiLessonStage.renderingVideo:
        return 68;
      case AiLessonStage.uploading:
        return 88;
      case AiLessonStage.ready:
        return 100;
    }
  }

  int get etaSeconds {
    switch (this) {
      case AiLessonStage.preparing:
        return 12;
      case AiLessonStage.generatingVoice:
        return 20;
      case AiLessonStage.creatingScenes:
        return 18;
      case AiLessonStage.renderingVideo:
        return 25;
      case AiLessonStage.uploading:
        return 8;
      case AiLessonStage.ready:
        return 0;
    }
  }

  static AiLessonStage parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'generating_voice':
      case 'generating_audio':
      case 'creating_voice':
        return AiLessonStage.generatingVoice;
      case 'creating_scenes':
      case 'generating_slides':
      case 'preparing_slides':
        return AiLessonStage.creatingScenes;
      case 'rendering_video':
        return AiLessonStage.renderingVideo;
      case 'uploading':
        return AiLessonStage.uploading;
      case 'ready':
      case 'completed':
        return AiLessonStage.ready;
      default:
        return AiLessonStage.preparing;
    }
  }
}

enum AiLessonPlayback { video, educational }

extension AiLessonPlaybackX on AiLessonPlayback {
  String get wire => this == AiLessonPlayback.video ? 'video' : 'educational';

  static AiLessonPlayback parse(String? raw) {
    return (raw ?? '').trim().toLowerCase() == 'video'
        ? AiLessonPlayback.video
        : AiLessonPlayback.educational;
  }
}

/// Student-visible copy. Never includes stack traces, HTTP, or Storage URLs.
String studentFacingLessonMessage(Object error) {
  final s = error.toString().toLowerCase();
  if (s.contains('429') ||
      s.contains('retry') ||
      s.contains('unavailable') ||
      s.contains('rate limit')) {
    return 'Retrying automatically';
  }
  if (s.contains('timeout') ||
      s.contains('render') ||
      s.contains('ffmpeg') ||
      s.contains('encode')) {
    return 'Video is being prepared';
  }
  if (s.contains('tts') ||
      s.contains('voice') ||
      s.contains('audio') ||
      s.contains('speech')) {
    return 'Voice generation is taking longer than expected';
  }
  return 'Lesson will be available shortly';
}
