import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'free_tts_engine.dart';
import 'google_cloud_tts_service.dart';
import 'ai_video_render/gemini_tts_synthesizer.dart';
import 'package:mpsc_combine_ai/utils/audio_blob_url.dart';

/// Playback state for AI Classroom narration (Google Cloud TTS or free TTS).
enum LessonAudioState {
  idle,
  loading,
  buffering,
  playing,
  paused,
  stopped,
  error,
}

enum _AudioBackend { none, googleCloud, gemini, free, continuous }

/// Play / Pause / Resume / Stop / Seek / Speed with subtitle progress sync.
///
/// **Primary:** Google Cloud Text-to-Speech when credentials are configured
/// (`TTS_SERVICE_ACCOUNT_PATH` / `GOOGLE_TTS_API_KEY` / etc.).
/// **Fallback:** free browser / Flutter TTS (Web Speech API on web).
/// On auth/quota/network exhaustion, falls back to free TTS and never crashes
/// the lesson — [speakAndWait] swallows voice errors after logging.
///
/// Session model: [stop] bumps [speakGeneration] so in-flight [speakAndWait]
/// exits. [speakAndWait] itself also claims a generation after halting any
/// prior clip — [stop] must not be double-applied inside [speakAndWait] or
/// the new session token is invalidated immediately.
class LessonAudioPlayer {
  LessonAudioPlayer({
    GoogleCloudTtsService? tts,
    FreeTtsEngine? freeTts,
    GeminiTtsSynthesizer? geminiTts,
  })  : _tts = tts ?? googleCloudTtsService,
        _freeTts = freeTts ?? FreeTtsEngine(),
        _geminiTts = geminiTts ?? GeminiTtsSynthesizer() {
    _freeTts.onProgress = (p) {
      if (_activeBackend == _AudioBackend.free &&
          !_progressController.isClosed) {
        _progressController.add(p.clamp(0.0, 1.0));
      }
    };
  }

  final GoogleCloudTtsService _tts;
  final FreeTtsEngine _freeTts;
  final GeminiTtsSynthesizer _geminiTts;
  final AudioPlayer _player = AudioPlayer();

  LessonAudioState _state = LessonAudioState.idle;
  String? _lastError;
  String _currentText = '';
  double _speed = GoogleCloudTtsService.defaultSpeakingRate;
  bool _muted = false;
  double _volumeBeforeMute = 1.0;
  Duration _duration = Duration.zero;
  Completer<void>? _segmentDone;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _positionSub;

  /// Sticky: after auth/quota failure, skip Cloud TTS for this session.
  bool _cloudTtsDisabledForSession = false;
  bool _geminiTtsDisabledForSession = false;
  _AudioBackend _activeBackend = _AudioBackend.none;

  /// Speaking rate baked into the current Cloud TTS clip (for mid-clip speed).
  double _synthesizedRate = GoogleCloudTtsService.defaultSpeakingRate;

  /// Soft-pause gate — blocks starting/continuing audio until [resume].
  bool _paused = false;

  /// In-flight prefetch for the next teaching paragraph (one at a time).
  Future<void>? _prefetchFuture;
  String? _prefetchText;

  /// Bumped by [stop] (and at the start of each [speakAndWait]) so late
  /// callbacks from a cancelled session are ignored.
  int _speakGeneration = 0;
  bool _disposed = false;
  String? _blobUrl;
  bool _continuousReady = false;

  final _stateController = StreamController<LessonAudioState>.broadcast();
  final _progressController = StreamController<double>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  LessonAudioState get state => _state;
  String? get lastError => _lastError;
  String get currentText => _currentText;
  double get speed => _speed;
  bool get muted => _muted;
  bool get isPlaying => _state == LessonAudioState.playing;
  bool get isPaused => _state == LessonAudioState.paused;
  bool get isLoading =>
      _state == LessonAudioState.loading ||
      _state == LessonAudioState.buffering;
  Duration get position => _player.position;
  Duration get duration => _duration;

  /// Current playback session token — useful for tests / UI guards.
  int get speakGeneration => _speakGeneration;

  /// Whether this player will attempt Google Cloud TTS before free TTS.
  bool get cloudTtsAttemptEnabled =>
      _tts.isEnabled && !_cloudTtsDisabledForSession;

  Stream<LessonAudioState> get stateStream => _stateController.stream;

  /// 0.0–1.0 of current clip — drives subtitle word highlight.
  Stream<double> get progressStream => _progressController.stream;
  Stream<String> get errorStream => _errorController.stream;

  Future<void> setSpeed(double speed) async {
    if (_disposed) return;
    _speed = speed.clamp(0.5, 1.5);
    try {
      if (_activeBackend == _AudioBackend.free) {
        await _freeTts.setSpeed(_speed);
      } else if (_activeBackend == _AudioBackend.googleCloud) {
        // Cloud clips are synthesized at [_synthesizedRate]; time-stretch the
        // already-decoded buffer so Speed changes apply immediately.
        final base =
            _synthesizedRate <= 0 ? 1.0 : _synthesizedRate.clamp(0.5, 1.5);
        await _player.setSpeed((_speed / base).clamp(0.5, 2.0));
      } else {
        await _player.setSpeed(_speed);
      }
    } catch (_) {}
  }

  Future<void> setMuted(bool muted) async {
    if (_disposed) return;
    _muted = muted;
    try {
      if (_activeBackend == _AudioBackend.free) {
        await _freeTts.setVolume(muted ? 0 : 1);
        return;
      }
      if (muted) {
        _volumeBeforeMute = _player.volume;
        await _player.setVolume(0);
      } else {
        await _player.setVolume(_volumeBeforeMute <= 0 ? 1 : _volumeBeforeMute);
      }
    } catch (_) {}
  }

  /// Seek within the current clip (0.0–1.0). No-op for free TTS / unknown duration.
  Future<void> seekFraction(double fraction) async {
    if (_disposed) return;
    if (_activeBackend == _AudioBackend.free) return;
    final total = _duration;
    if (total <= Duration.zero) {
      final d = _player.duration;
      if (d == null || d <= Duration.zero) return;
      _duration = d;
    }
    final target = Duration(
      milliseconds:
          (_duration.inMilliseconds * fraction.clamp(0.0, 1.0)).round(),
    );
    try {
      await _player.seek(target);
      _progressController.add(fraction.clamp(0.0, 1.0));
    } catch (e) {
      final msg = 'Seek failed: $e';
      _lastError = msg;
      _errorController.add(msg);
    }
  }

  Future<void> skipBy(Duration delta) async {
    if (_disposed) return;
    if (_activeBackend == _AudioBackend.free) return;
    var total = _duration;
    if (total <= Duration.zero) {
      total = _player.duration ?? Duration.zero;
      _duration = total;
    }
    if (total <= Duration.zero) return;
    var next = _player.position + delta;
    if (next < Duration.zero) next = Duration.zero;
    if (next > total) next = total;
    try {
      await _player.seek(next);
      _progressController.add((next.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0));
    } catch (_) {}
  }

  Future<void> seekTo(Duration position) async {
    if (_disposed) return;
    var total = _duration;
    if (total <= Duration.zero) {
      total = _player.duration ?? Duration.zero;
      _duration = total;
    }
    var next = position;
    if (next < Duration.zero) next = Duration.zero;
    if (total > Duration.zero && next > total) next = total;
    try {
      await _player.seek(next);
      if (total > Duration.zero && !_progressController.isClosed) {
        _progressController.add((next.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0));
      }
    } catch (_) {}
  }

  /// Loads one full-lesson WAV/MP3 into the player and waits until it is buffered.
  /// Does not start playback. Call [playContinuous] after this returns.
  Future<Duration> preloadContinuous(
    Uint8List bytes, {
    String mimeType = 'audio/wav',
  }) async {
    if (_disposed) return Duration.zero;
    _paused = false;
    try {
      await _freeTts.stop();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
    _releaseBlob();
    _continuousReady = false;
    _activeBackend = _AudioBackend.continuous;

    AudioSource source;
    if (kIsWeb) {
      _blobUrl = createAudioBlobUrl(bytes, mimeType);
      if (_blobUrl != null && _blobUrl!.isNotEmpty) {
        source = AudioSource.uri(Uri.parse(_blobUrl!));
      } else {
        source = AudioSource.uri(
          Uri.dataFromBytes(bytes, mimeType: mimeType),
        );
      }
    } else {
      source = AudioSource.uri(
        Uri.dataFromBytes(bytes, mimeType: mimeType),
      );
    }
    await _player.setAudioSource(source);
    try {
      await _player.setSpeed(_speed);
    } catch (_) {}
    if (_muted) {
      try {
        await _player.setVolume(0);
      } catch (_) {}
    }
    final gen = _speakGeneration;
    final ready = await _waitUntilBuffered(
      timeout: const Duration(seconds: 20),
      gen: gen,
    );
    if (!ready || gen != _speakGeneration || _disposed) {
      _continuousReady = false;
      return Duration.zero;
    }
    await _bindProgress();
    _duration = _player.duration ?? Duration.zero;
    _continuousReady = true;
    _setState(LessonAudioState.idle);
    if (!_progressController.isClosed) {
      _progressController.add(0);
    }
    return _duration;
  }

  /// Plays the preloaded full-lesson file from [from] until the end or Stop.
  Future<void> playContinuous({Duration from = Duration.zero}) async {
    if (_disposed) return;
    if (!_continuousReady) {
      throw StateError('preloadContinuous must complete before playContinuous');
    }
    _paused = false;
    final gen = ++_speakGeneration;
    _activeBackend = _AudioBackend.continuous;
    _segmentDone = Completer<void>();
    await _bindProgress();
    _setState(LessonAudioState.playing);
    await seekTo(from);
    try {
      await _player.setSpeed(_speed);
    } catch (_) {}
    if (_muted) {
      try {
        await _player.setVolume(0);
      } catch (_) {}
    }
    await _player.play();
    await _waitUntilCompleteOrCancelled(gen);
    if (gen == _speakGeneration && !_paused && !_disposed) {
      _setState(LessonAudioState.idle);
    }
  }

  Future<void> _waitUntilCompleteOrCancelled(int gen) async {
    var sawPlayback = _player.processingState == ProcessingState.ready ||
        _player.processingState == ProcessingState.buffering ||
        _player.processingState == ProcessingState.loading;
    while (gen == _speakGeneration && !_disposed) {
      if (_paused) {
        await _waitWhilePaused(gen);
        if (gen != _speakGeneration || _disposed) return;
        try {
          await _player.play();
          _setState(LessonAudioState.playing);
        } catch (_) {}
        sawPlayback = true;
      }
      final ps = _player.processingState;
      if (ps == ProcessingState.ready ||
          ps == ProcessingState.buffering ||
          ps == ProcessingState.loading) {
        sawPlayback = true;
      }
      if (sawPlayback &&
          (ps == ProcessingState.completed ||
              (_segmentDone?.isCompleted ?? false))) {
        return;
      }
      final pending = _segmentDone;
      if (pending == null) return;
      await Future.any([
        pending.future,
        Future<void>.delayed(const Duration(milliseconds: 80)),
      ]);
    }
  }

  bool get hasContinuousSource => _continuousReady;

  void _releaseBlob() {
    revokeAudioBlobUrl(_blobUrl);
    _blobUrl = null;
  }

  /// Warm the disk/memory cache for the next paragraph without playing.
  /// Only applies when Cloud TTS is enabled; free TTS has no MP3 cache.
  void prefetch(String text) {
    if (_disposed) return;
    if (!cloudTtsAttemptEnabled) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_prefetchText == trimmed && _prefetchFuture != null) return;

    _prefetchText = trimmed;
    _prefetchFuture = () async {
      try {
        final chunks = GoogleCloudTtsService.chunkForApi(trimmed);
        for (final chunk in chunks) {
          final hit = await _tts.readCache(chunk, speakingRate: _speed);
          if (hit != null) continue;
          await _tts.synthesize(chunk, speakingRate: _speed);
        }
      } catch (_) {
        // Prefetch failures are non-fatal; speakAndWait will retry / fall back.
      }
    }();
  }

  /// Speak [text] until finished. Never throws — voice errors are logged and
  /// the lesson continues (optionally via free TTS fallback).
  Future<void> speakAndWait(String text) async {
    if (_disposed) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // Cancel any prior clip first — without consuming this session's token.
    // (Calling [stop] here would bump generation twice and orphan this speak.)
    _paused = false;
    await _haltPlayback(emitIdle: false);
    if (_disposed) return;

    final gen = ++_speakGeneration;

    _currentText = trimmed;
    _lastError = null;
    _duration = Duration.zero;
    _synthesizedRate = _speed;
    _setState(LessonAudioState.loading);
    _progressController.add(0);

    try {
      if (_geminiTts.isConfigured && !_geminiTtsDisabledForSession) {
        final used = await _tryGemini(trimmed, gen);
        if (used || gen != _speakGeneration || _disposed) return;
      }
      if (cloudTtsAttemptEnabled) {
        final used = await _tryGoogleCloud(trimmed, gen);
        if (used || gen != _speakGeneration || _disposed) return;
      }

      await _speakFree(trimmed, gen);
    } catch (e, st) {
      // Absolute last resort — never crash the classroom.
      if (gen != _speakGeneration || _disposed) return;
      debugPrint('LessonAudioPlayer speakAndWait swallowed error: $e\n$st');
      _lastError = 'TTS unavailable: $e';
      if (!_errorController.isClosed) {
        _errorController.add(_lastError!);
      }
      // Soft error state then idle so UI can continue the lesson.
      _setState(LessonAudioState.error);
    } finally {
      if (gen == _speakGeneration && !_disposed) {
        await _unbindProgress();
        _segmentDone = null;
        _activeBackend = _AudioBackend.none;
        // Never leave loading/buffering stuck after a speak ends.
        if (_state == LessonAudioState.loading ||
            _state == LessonAudioState.buffering ||
            _state == LessonAudioState.playing ||
            _state == LessonAudioState.error) {
          _setState(LessonAudioState.idle);
        } else if (_state == LessonAudioState.stopped) {
          // Keep stopped only when an explicit stop(emitIdle: false) won the race;
          // otherwise normalize to idle for the next Play.
          _setState(LessonAudioState.idle);
        }
        // If paused, leave paused so Resume can continue the classroom loop.
        if (!_progressController.isClosed && _state != LessonAudioState.paused) {
          _progressController.add(0);
        }
      }
    }
  }

  /// Gemini Marathi TTS first. Returns true if audio played.
  Future<bool> _tryGemini(String trimmed, int gen) async {
    try {
      _setState(LessonAudioState.buffering);
      final chunks = GoogleCloudTtsService.chunkForApi(trimmed, maxChars: 480);
      if (chunks.isEmpty) return false;
      _activeBackend = _AudioBackend.gemini;
      for (final chunk in chunks) {
        if (gen != _speakGeneration || _disposed) return true;
        await _waitWhilePaused(gen);
        if (gen != _speakGeneration || _disposed) return true;
        final wav = await _geminiTts.synthesizeMarathiFacultyWithRetry(chunk);
        if (gen != _speakGeneration || _disposed) return true;
        if (wav.length < 256) return false;
        await _playClipBytes(
          wav,
          gen: gen,
          mimeType: 'audio/wav',
        );
        if (gen != _speakGeneration || _disposed) return true;
      }
      return true;
    } catch (e) {
      debugPrint('Gemini TTS failed: $e');
      _geminiTtsDisabledForSession = true;
      _lastError = '$e';
      return false;
    }
  }

  /// Returns true if Cloud TTS played successfully; false to try free TTS.
  Future<bool> _tryGoogleCloud(String trimmed, int gen) async {
    try {
      if (_prefetchText == trimmed && _prefetchFuture != null) {
        _setState(LessonAudioState.buffering);
        await _prefetchFuture;
        if (gen != _speakGeneration || _disposed) return true;
      }

      _setState(LessonAudioState.buffering);
      final chunks = GoogleCloudTtsService.chunkForApi(trimmed);
      if (chunks.isEmpty) return false;

      _activeBackend = _AudioBackend.googleCloud;
      for (var i = 0; i < chunks.length; i++) {
        if (gen != _speakGeneration || _disposed) return true;
        await _waitWhilePaused(gen);
        if (gen != _speakGeneration || _disposed) return true;

        final clip = await _tts.synthesize(chunks[i], speakingRate: _speed);
        if (gen != _speakGeneration || _disposed) return true;
        _synthesizedRate = _speed;

        if (clip.bytes.length < 256) {
          debugPrint(
            'Google Cloud TTS buffer too small; falling back to free TTS.',
          );
          return false;
        }

        await _playClipBytes(clip.bytes, filePath: clip.filePath, gen: gen);
        if (gen != _speakGeneration || _disposed) return true;
      }
      return true;
    } on GoogleCloudTtsException catch (e) {
      if (gen != _speakGeneration || _disposed) return true;
      debugPrint('Google Cloud TTS failed: ${e.displayMessage}');
      if (GoogleCloudTtsService.isFallbackException(e)) {
        _cloudTtsDisabledForSession = true;
      }
      // Soft-notify UI but do not stop the lesson — fall back to free TTS.
      _lastError = e.displayMessage;
      if (!_errorController.isClosed) {
        _errorController.add(e.displayMessage);
      }
      return false;
    } catch (e) {
      if (gen != _speakGeneration || _disposed) return true;
      debugPrint('Google Cloud TTS unexpected error, falling back: $e');
      return false;
    }
  }

  Future<void> _speakFree(String trimmed, int gen) async {
    if (gen != _speakGeneration || _disposed) return;
    _activeBackend = _AudioBackend.free;
    _setState(LessonAudioState.loading);
    try {
      await _waitWhilePaused(gen);
      if (gen != _speakGeneration || _disposed) return;
      _setState(LessonAudioState.playing);
      await _freeTts.speakAndWait(
        trimmed,
        speed: _speed,
        muted: _muted,
      );
    } catch (e) {
      debugPrint('Free TTS failed (continuing lesson): $e');
      _lastError = 'Free TTS failed: $e';
      if (!_errorController.isClosed) {
        _errorController.add(_lastError!);
      }
      // Do not rethrow — classroom must continue.
    }
  }

  Future<void> _playClipBytes(
    Uint8List bytes, {
    String? filePath,
    required int gen,
    String mimeType = 'audio/mpeg',
  }) async {
    if (_disposed || gen != _speakGeneration) return;
    try {
      if (!kIsWeb && filePath != null) {
        await _player.setFilePath(filePath);
      } else {
        await _player.setAudioSource(
          AudioSource.uri(
            Uri.dataFromBytes(bytes, mimeType: mimeType),
          ),
        );
      }
    } catch (_) {
      if (_disposed || gen != _speakGeneration) return;
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.dataFromBytes(bytes, mimeType: mimeType),
        ),
      );
    }

    if (gen != _speakGeneration || _disposed) return;

    // Speaking rate is already applied in Cloud TTS audioConfig; player stays
    // at 1.0 unless the user changes Speed mid-clip (see [setSpeed]).
    await _player.setSpeed(1.0);
    if (_muted) await _player.setVolume(0);

    final ready = await _waitUntilBuffered(
      timeout: const Duration(seconds: 12),
      gen: gen,
    );
    if (!ready || gen != _speakGeneration || _disposed) {
      if (gen == _speakGeneration && !_disposed) {
        throw const GoogleCloudTtsException(
          message: 'Audio buffer did not become ready before playback.',
        );
      }
      return;
    }

    await _waitWhilePaused(gen);
    if (gen != _speakGeneration || _disposed) return;

    _segmentDone = Completer<void>();
    await _bindProgress();
    await _player.play();
    if (gen != _speakGeneration || _disposed) return;
    if (_paused) {
      await _player.pause();
      _setState(LessonAudioState.paused);
      await _waitWhilePaused(gen);
      if (gen != _speakGeneration || _disposed) return;
      await _player.play();
      if (gen != _speakGeneration || _disposed) return;
    }
    _setState(LessonAudioState.playing);
    await _segmentDone!.future;
  }

  /// Ensures just_audio has loaded the source before we call play().
  Future<bool> _waitUntilBuffered({
    required Duration timeout,
    required int gen,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (gen != _speakGeneration || _disposed) return false;
      final ps = _player.processingState;
      if (ps == ProcessingState.ready ||
          ps == ProcessingState.buffering ||
          ps == ProcessingState.completed) {
        final d = _player.duration;
        if (d != null && d > Duration.zero) {
          _duration = d;
          return true;
        }
        if (ps == ProcessingState.ready) return true;
      }
      await Future.delayed(const Duration(milliseconds: 40));
    }
    if (gen != _speakGeneration || _disposed) return false;
    return _player.processingState != ProcessingState.idle;
  }

  /// Parks the speak loop while soft-paused so Stop still interrupts via gen.
  Future<void> _waitWhilePaused(int gen) async {
    if (!_paused) return;
    if (gen == _speakGeneration && !_disposed) {
      _setState(LessonAudioState.paused);
    }
    while (_paused && gen == _speakGeneration && !_disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> pause() async {
    if (_disposed) return;
    _paused = true;
    // Always reflect paused immediately — including during loading/buffering —
    // so the classroom Stop/Pause UI never fights a stuck "playing" state.
    if (_state == LessonAudioState.playing ||
        _state == LessonAudioState.loading ||
        _state == LessonAudioState.buffering) {
      try {
      if (_activeBackend == _AudioBackend.free) {
        await _freeTts.pause();
      } else if (_activeBackend != _AudioBackend.none) {
        await _player.pause();
      }
      } catch (e) {
        debugPrint('LessonAudioPlayer pause failed: $e');
      }
      _setState(LessonAudioState.paused);
      return;
    }
    if (_state != LessonAudioState.paused) {
      _setState(LessonAudioState.paused);
    }
  }

  Future<void> resume() async {
    if (_disposed) return;
    if (!_paused && _state != LessonAudioState.paused) return;
    _paused = false;
    try {
      if (_activeBackend == _AudioBackend.free) {
        await _freeTts.resume();
        _setState(LessonAudioState.playing);
      } else if (_activeBackend != _AudioBackend.none) {
        await _player.play();
        _setState(LessonAudioState.playing);
      } else if (_state == LessonAudioState.paused) {
        _setState(LessonAudioState.idle);
      }
    } catch (e) {
      debugPrint('LessonAudioPlayer resume failed: $e');
    }
  }

  /// Cancels the current speak session and stops the audio engine immediately.
  ///
  /// UI-facing state flips to idle/stopped *before* awaiting engine teardown so
  /// Stop never appears stuck behind a long TTS cancel.
  Future<void> stop({bool emitIdle = true}) async {
    if (_disposed) return;
    _speakGeneration++;
    _paused = false;
    final next = emitIdle ? LessonAudioState.idle : LessonAudioState.stopped;
    _setState(next);
    if (!_progressController.isClosed) {
      _progressController.add(0);
    }
    await _haltPlayback(emitIdle: emitIdle);
  }

  /// Waits [duration] unless Stop/new speak cancels this session.
  /// Used for intentional inter-paragraph silence without freezing controls.
  Future<void> waitWhileSessionActive(Duration duration) async {
    if (_disposed) return;
    final gen = _speakGeneration;
    final end = DateTime.now().add(duration);
    while (DateTime.now().isBefore(end)) {
      if (_disposed || gen != _speakGeneration) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Stops the underlying player without claiming a new speak generation.
  Future<void> _haltPlayback({required bool emitIdle}) async {
    if (_disposed) return;
    try {
      await _freeTts.stop();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
    final pending = _segmentDone;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
    _segmentDone = null;
    _activeBackend = _AudioBackend.none;
    // Preserve an immediate idle/stopped written by [stop]; otherwise publish.
    final next = emitIdle ? LessonAudioState.idle : LessonAudioState.stopped;
    if (_state != next) {
      _setState(next);
    }
    if (!_progressController.isClosed) {
      _progressController.add(0);
    }
  }

  Future<void> _bindProgress() async {
    await _unbindProgress();
    if (_disposed) return;
    _duration = _player.duration ?? Duration.zero;

    _durationSub = _player.durationStream.listen((d) {
      if (d != null) _duration = d;
    });
    _positionSub = _player.positionStream.listen((pos) {
      final total = _duration.inMilliseconds;
      if (total <= 0) {
        if (!_progressController.isClosed) _progressController.add(0);
        return;
      }
      if (!_progressController.isClosed) {
        _progressController.add((pos.inMilliseconds / total).clamp(0.0, 1.0));
      }
    });
    _stateSub = _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        final pending = _segmentDone;
        if (pending != null && !pending.isCompleted) {
          pending.complete();
        }
      }
    });
  }

  Future<void> _unbindProgress() async {
    await _stateSub?.cancel();
    await _durationSub?.cancel();
    await _positionSub?.cancel();
    _stateSub = null;
    _durationSub = null;
    _positionSub = null;
  }

  void _setState(LessonAudioState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _speakGeneration++;
    _paused = false;
    try {
      await _freeTts.dispose();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
    final pending = _segmentDone;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
    _segmentDone = null;
    await _unbindProgress();
    _releaseBlob();
    _continuousReady = false;
    try {
      await _player.dispose();
    } catch (_) {}
    await _stateController.close();
    await _progressController.close();
    await _errorController.close();
  }
}
