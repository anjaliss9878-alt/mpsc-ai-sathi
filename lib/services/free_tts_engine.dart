import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Free / browser TTS for AI Classroom development and Cloud TTS fallback.
///
/// Uses `flutter_tts`, which maps to the Web Speech API (`speechSynthesis`) on
/// Flutter web and to platform engines on mobile/desktop. No API key required.
class FreeTtsEngine {
  FreeTtsEngine() {
    _tts.setStartHandler(() {
      // Progress ticks start from speakAndWait.
    });
    _tts.setCompletionHandler(_completeSpeak);
    _tts.setCancelHandler(_completeSpeak);
    _tts.setErrorHandler((msg) {
      debugPrint('FreeTtsEngine error: $msg');
      _completeSpeak();
    });
    _tts.setPauseHandler(() {});
    _tts.setContinueHandler(() {});
  }

  final FlutterTts _tts = FlutterTts();

  Completer<void>? _done;
  String? _lastText;
  bool _ready = false;
  String? _preferredVoiceName;
  Timer? _progressTimer;
  bool _disposed = false;

  /// Optional 0.0–1.0 progress callback (estimated for free TTS).
  void Function(double progress)? onProgress;

  Future<void> _ensureReady() async {
    if (_ready || _disposed) return;
    try {
      await _tts.awaitSpeakCompletion(true);
      // Prefer a natural female voice when the engine exposes a catalog.
      try {
        final raw = await _tts.getVoices;
        if (raw is List) {
          final voices = raw
              .whereType<Map>()
              .map((m) => m.map((k, v) => MapEntry('$k', '$v')))
              .toList();
          _preferredVoiceName = _pickFemaleVoice(voices);
          if (_preferredVoiceName != null) {
            await _tts.setVoice({'name': _preferredVoiceName!});
          }
        }
      } catch (e) {
        debugPrint('FreeTtsEngine voice catalog unavailable: $e');
      }
      _ready = true;
    } catch (e) {
      debugPrint('FreeTtsEngine init failed: $e');
      _ready = true; // Avoid retry loops; speak may still work.
    }
  }

  /// Prefer a natural female voice; fall back to any matching locale voice.
  String? _pickFemaleVoice(List<Map<String, String>> voices) {
    if (voices.isEmpty) return null;

    String nameOf(Map<String, String> v) =>
        (v['name'] ?? v['voiceURI'] ?? '').toLowerCase();
    String localeOf(Map<String, String> v) =>
        (v['locale'] ?? v['lang'] ?? '').toLowerCase();

    bool looksFemale(Map<String, String> v) {
      final n = nameOf(v);
      return n.contains('female') ||
          n.contains('woman') ||
          n.contains('samantha') ||
          n.contains('zira') ||
          n.contains('karen') ||
          n.contains('moira') ||
          n.contains('veena') ||
          n.contains('heera') ||
          n.contains('google uk english female') ||
          n.contains('microsoft aria') ||
          n.contains('microsoft jenny');
    }

    // Prefer Indian / Marathi female voices for MPSC teaching.
    for (final v in voices) {
      final loc = localeOf(v);
      if (looksFemale(v) &&
          (loc.contains('in') || loc.contains('mr') || loc.contains('hi'))) {
        return v['name'] ?? v['voiceURI'];
      }
    }
    for (final v in voices) {
      if (looksFemale(v)) return v['name'] ?? v['voiceURI'];
    }
    for (final v in voices) {
      final loc = localeOf(v);
      if (loc.startsWith('mr') || loc.contains('mr-in')) {
        return v['name'] ?? v['voiceURI'];
      }
    }
    for (final v in voices) {
      final loc = localeOf(v);
      if (loc.contains('en-in') || loc.contains('en_in')) {
        return v['name'] ?? v['voiceURI'];
      }
    }
    return voices.first['name'] ?? voices.first['voiceURI'];
  }

  Future<void> _applyLanguage(String text) async {
    final isMarathi = RegExp(r'[\u0900-\u097F]').hasMatch(text);
    try {
      await _tts.setLanguage(isMarathi ? 'mr-IN' : 'en-IN');
    } catch (_) {
      try {
        await _tts.setLanguage(isMarathi ? 'hi-IN' : 'en-US');
      } catch (_) {}
    }
    if (_preferredVoiceName != null) {
      try {
        await _tts.setVoice({'name': _preferredVoiceName!});
      } catch (_) {}
    }
  }

  /// Maps classroom speed (0.5–1.5, teaching default 0.9) onto flutter_tts rate.
  double _mapRate(double speed) {
    // flutter_tts: ~0.5 is natural on most mobile engines; web uses similar scale.
    return (0.5 * speed.clamp(0.5, 1.5)).clamp(0.25, 0.9);
  }

  /// Speak [text] and complete when the utterance finishes (or is stopped).
  Future<void> speakAndWait(
    String text, {
    double speed = 0.9,
    bool muted = false,
  }) async {
    if (_disposed) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await stop();
    if (_disposed) return;

    await _ensureReady();
    _lastText = trimmed;
    _done = Completer<void>();

    try {
      await _applyLanguage(trimmed);
      await _tts.setSpeechRate(_mapRate(speed));
      await _tts.setPitch(1.0);
      await _tts.setVolume(muted ? 0.0 : 1.0);
    } catch (e) {
      debugPrint('FreeTtsEngine configure failed: $e');
    }

    _startEstimatedProgress(trimmed, speed);

    try {
      final result = await _tts.speak(trimmed);
      // Some platforms return 1 on success; others return null / true.
      if (result == 0 || result == false) {
        debugPrint('FreeTtsEngine speak returned failure: $result');
        _completeSpeak();
      }
    } catch (e) {
      debugPrint('FreeTtsEngine speak failed: $e');
      _completeSpeak();
    }

    final pending = _done;
    if (pending != null) {
      await pending.future;
    }
  }

  void _startEstimatedProgress(String text, double speed) {
    _progressTimer?.cancel();
    onProgress?.call(0);
    // ~14 chars/sec at teaching pace; clamp so short lines still animate.
    final estMs =
        ((text.length / 14.0) * 1000.0 / speed.clamp(0.5, 1.5)).round().clamp(
              1200,
              180000,
            );
    final started = DateTime.now();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final p = (elapsed / estMs).clamp(0.0, 0.98);
      onProgress?.call(p);
      if (elapsed >= estMs) {
        _progressTimer?.cancel();
      }
    });
  }

  void _completeSpeak() {
    _progressTimer?.cancel();
    _progressTimer = null;
    onProgress?.call(1);
    final pending = _done;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
    _done = null;
  }

  Future<void> pause() async {
    if (_disposed) return;
    try {
      await _tts.pause();
    } catch (e) {
      debugPrint('FreeTtsEngine pause failed: $e');
    }
    _progressTimer?.cancel();
  }

  Future<void> resume() async {
    if (_disposed) return;
    final text = _lastText;
    if (text == null) return;
    try {
      // Native pause/continue where supported; elsewhere restarts utterance.
      final result = await _tts.speak(text);
      if (result == 0 || result == false) {
        debugPrint('FreeTtsEngine resume speak failed: $result');
      }
    } catch (e) {
      debugPrint('FreeTtsEngine resume failed: $e');
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    try {
      await _tts.stop();
    } catch (_) {}
    _completeSpeak();
  }

  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    try {
      await _tts.setVolume(volume.clamp(0.0, 1.0));
    } catch (_) {}
  }

  Future<void> setSpeed(double speed) async {
    if (_disposed) return;
    try {
      await _tts.setSpeechRate(_mapRate(speed));
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _progressTimer?.cancel();
    try {
      await _tts.stop();
    } catch (_) {}
    _completeSpeak();
  }
}
