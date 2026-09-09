import 'dart:async';
import 'dart:html' as html;

/// HTMLAudioElement used for AI Teacher Voice on Flutter web.
///
/// Chrome only allows [play] when it is called from a user gesture, or on an
/// element that was already [play]'d during that gesture. [unlockAndPlay]
/// must be invoked from the Voice/Play [onPressed] with no [await] first.
class WebHtmlAudio {
  html.AudioElement? _el;
  StreamSubscription<html.Event>? _endedSub;
  StreamSubscription<html.Event>? _timeSub;
  StreamSubscription<html.Event>? _errorSub;
  bool _playing = false;

  bool get hasSource {
    final src = _el?.src ?? '';
    if (src.isEmpty) return false;
    if (src.contains(_kSilentWavMarker)) return false;
    return true;
  }

  Duration get position {
    final s = _el?.currentTime ?? 0;
    return Duration(milliseconds: (s * 1000).round());
  }

  Duration get duration {
    final s = _el?.duration;
    if (s == null || s.isNaN || s.isInfinite || s <= 0) return Duration.zero;
    return Duration(milliseconds: (s * 1000).round());
  }

  bool get isPlaying => _playing && !(_el?.paused ?? true);

  void Function()? onEnded;
  void Function(Duration position, Duration duration)? onTimeUpdate;
  void Function(String error)? onError;

  html.AudioElement _ensure() {
    if (_el != null) return _el!;
    final el = html.AudioElement()
      ..preload = 'auto'
      ..controls = false
      ..style.display = 'none';
    html.document.body?.append(el);
    _endedSub = el.onEnded.listen((_) {
      _playing = false;
      onEnded?.call();
    });
    _timeSub = el.onTimeUpdate.listen((_) {
      onTimeUpdate?.call(position, duration);
    });
    _errorSub = el.onError.listen((_) {
      _playing = false;
      onError?.call('playback_error');
    });
    _el = el;
    return el;
  }

  void attachUrl(String url) {
    if (url.trim().isEmpty) return;
    final el = _ensure();
    if (el.src == url) return;
    el.src = url;
    el.load();
  }

  void unlockAndPlay() {
    final el = _ensure();
    if ((el.src).isEmpty) {
      el.src = _kSilentWavDataUri;
    }
    _playing = true;
    try {
      final d = el.duration;
      if (d.isFinite && !d.isNaN && d > 0 && el.currentTime >= d - 0.05) {
        el.currentTime = 0;
      }
      el.play().then<void>((_) {}, onError: (Object err, StackTrace _) {
        _playing = false;
        final raw = err.toString();
        final denied = raw.contains('NotAllowedError') ||
            raw.toLowerCase().contains('user gesture') ||
            raw.toLowerCase().contains("didn't interact");
        onError?.call(denied ? 'NotAllowedError' : err.runtimeType.toString());
      });
    } catch (err) {
      _playing = false;
      final raw = err.toString();
      final denied = raw.contains('NotAllowedError') ||
          raw.toLowerCase().contains('user gesture');
      onError?.call(denied ? 'NotAllowedError' : err.runtimeType.toString());
    }
  }

  void pause() {
    _playing = false;
    try {
      _el?.pause();
    } catch (_) {}
  }

  void stop() {
    _playing = false;
    try {
      _el?.pause();
      _el?.currentTime = 0;
    } catch (_) {}
  }

  void seek(Duration position) {
    try {
      _el?.currentTime = (position.inMilliseconds / 1000).clamp(0, 24 * 3600);
    } catch (_) {}
  }

  void setPlaybackRate(double rate) {
    try {
      _el?.playbackRate = rate.clamp(0.5, 2.0);
    } catch (_) {}
  }

  void setMuted(bool muted) {
    try {
      _el?.muted = muted;
    } catch (_) {}
  }

  void dispose() {
    stop();
    _endedSub?.cancel();
    _timeSub?.cancel();
    _errorSub?.cancel();
    _endedSub = null;
    _timeSub = null;
    _errorSub = null;
    _el?.src = '';
    _el?.remove();
    _el = null;
  }
}

// Tiny valid silent WAV so Chrome can unlock the element before blob attach.
const _kSilentWavMarker =
    'UklGRiQAAABXQVZFZm10IBAAAAABAAEAESsAACJWAAACABAAZGF0YQAAAAA=';
const _kSilentWavDataUri = 'data:audio/wav;base64,$_kSilentWavMarker';
