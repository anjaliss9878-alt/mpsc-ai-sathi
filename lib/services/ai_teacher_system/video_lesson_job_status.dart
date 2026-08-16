/// Production API statuses for the AI Video Lesson Engine job lifecycle.
enum VideoLessonJobStatus {
  queued,
  generatingScript,
  generatingAudio,
  generatingSlides,
  renderingVideo,
  completed,
  failed,
}

extension VideoLessonJobStatusX on VideoLessonJobStatus {
  /// Wire / log / Firestore-friendly status string.
  String get apiName {
    switch (this) {
      case VideoLessonJobStatus.queued:
        return 'queued';
      case VideoLessonJobStatus.generatingScript:
        return 'generating_script';
      case VideoLessonJobStatus.generatingAudio:
        return 'generating_audio';
      case VideoLessonJobStatus.generatingSlides:
        return 'generating_slides';
      case VideoLessonJobStatus.renderingVideo:
        return 'rendering_video';
      case VideoLessonJobStatus.completed:
        return 'completed';
      case VideoLessonJobStatus.failed:
        return 'failed';
    }
  }
}
