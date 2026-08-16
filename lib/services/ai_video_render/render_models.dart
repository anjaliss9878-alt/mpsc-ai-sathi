import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subtitle_timing.dart';

/// One timed teaching beat inside a rendered AI video.
class RenderNarrationBeat {
  const RenderNarrationBeat({
    required this.speakText,
    required this.duration,
    required this.boardProgress,
    this.keywords = const [],
    this.subtitleCues = const [],
    this.isMcq = false,
    this.isMcqExplain = false,
    this.pointerLabel = '',
  });

  final String speakText;
  final Duration duration;

  /// 0–1 how much of the board graphic is revealed during this beat.
  final double boardProgress;
  final List<String> keywords;
  final List<SubtitleCue> subtitleCues;
  final bool isMcq;
  final bool isMcqExplain;
  final String pointerLabel;
}

/// One animated classroom scene for the video encoder.
class RenderScene {
  const RenderScene({
    required this.id,
    required this.title,
    required this.visualType,
    required this.beats,
    this.bullets = const [],
    this.handwriting = const [],
    this.flowchart = const [],
    this.timeline = const [],
    this.tableHeaders = const [],
    this.tableRows = const [],
    this.mapRegions = const [],
    this.mcq,
  });

  final String id;
  final String title;
  final SlideVisualType visualType;
  final List<RenderNarrationBeat> beats;
  final List<String> bullets;
  final List<String> handwriting;
  final List<FlowNode> flowchart;
  final List<TimelineEvent> timeline;
  final List<String> tableHeaders;
  final List<List<String>> tableRows;
  final List<String> mapRegions;
  final GeneratedMcq? mcq;

  Duration get totalDuration => beats.fold<Duration>(
        Duration.zero,
        (sum, b) => sum + b.duration,
      );
}

/// Full render job: scenes + metadata for a playable MP4/WebM.
class AiVideoRenderJob {
  const AiVideoRenderJob({
    required this.topicName,
    required this.subjectName,
    required this.scenes,
    this.targetWidth = 1280,
    this.targetHeight = 720,
    this.fps = 30,
  });

  final String topicName;
  final String subjectName;
  final List<RenderScene> scenes;
  final int targetWidth;
  final int targetHeight;
  final int fps;

  Duration get totalDuration => scenes.fold<Duration>(
        Duration.zero,
        (sum, s) => sum + s.totalDuration,
      );
}

/// Output of a successful encode.
class AiVideoRenderResult {
  const AiVideoRenderResult({
    required this.filePath,
    required this.mimeType,
    required this.duration,
    required this.fromCache,
    this.assetKey,
    this.bytes,
  });

  /// Absolute path on IO platforms, or blob/asset URI marker on web.
  final String filePath;
  final String mimeType;
  final Duration duration;
  final bool fromCache;

  /// Optional Flutter asset key when shipping a prebuilt lesson.
  final String? assetKey;

  /// Optional in-memory bytes (web / small caches).
  final List<int>? bytes;
}

/// Progress events while encoding a real video file.
enum AiVideoRenderPhase {
  preparing,
  scripting,
  synthesizingVoice,
  composingFrames,
  encodingVideo,
  finalizing,
  done,
  failed,
}
