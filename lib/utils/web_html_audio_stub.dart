/// VM / non-web stub. Web implementation uses an HTMLAudioElement so Chrome
/// can start playback inside the Voice/Play click (user gesture).
class WebHtmlAudio {
  bool get hasSource => false;
  Duration get position => Duration.zero;
  Duration get duration => Duration.zero;
  bool get isPlaying => false;

  void Function()? onEnded;
  void Function(Duration position, Duration duration)? onTimeUpdate;
  void Function(String error)? onError;

  void attachUrl(String url) {}

  /// Must run synchronously in the Voice/Play click stack.
  void unlockAndPlay() {}

  void pause() {}

  void stop() {}

  void seek(Duration position) {}

  void setPlaybackRate(double rate) {}

  void setMuted(bool muted) {}

  void dispose() {}
}
