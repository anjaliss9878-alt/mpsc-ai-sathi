import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/faculty_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/full_lesson_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subtitle_timing.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/teaching_sequence.dart';
import 'package:mpsc_combine_ai/services/lesson_audio_player.dart';

/// Result of an interactive scene MCQ (wait → answer → explain).
class SceneMcqResult {
  const SceneMcqResult({
    required this.selectedIndex,
    required this.mcq,
  });

  final int selectedIndex;
  final GeneratedMcq mcq;

  String get explanation => mcq.explanationFor(selectedIndex);
  bool get isCorrect => selectedIndex == mcq.correctIndex;
}

/// Soft RAM budget for the Video Classroom Engine on 4 GB devices.
class ClassroomMemoryGuard {
  ClassroomMemoryGuard._();

  static const double defaultPlaybackSpeed = 1.0;

  static void trimLessonCaches() {}
}

/// Production Video Classroom Engine.
///
/// Pipeline: **Lesson → Scene → Animation → Voice → Interaction**
///
/// Plays one continuous ElevenLabs Marathi lecture file and syncs slides
/// to character/beat timestamps. Never synthesizes sentence-by-sentence TTS.
class VideoClassroomEngine extends ChangeNotifier {
  VideoClassroomEngine({
    LessonAudioPlayer? audio,
    this.onAskSceneMcq,
    this.onOfferFullQuiz,
    this.onProgressCheckpoint,
    this.onScrollToPremium,
  }) : _audio = audio ?? LessonAudioPlayer() {
    _progressSub = _audio.progressStream.listen((p) {
      if (_disposed) return;
      if (_lessonAudio != null) {
        _syncContinuousFromProgress(p);
      } else {
        _speechProgress = p;
        _syncPointerFromSpeech();
        _syncActiveKeywordFromSpeech();
      }
      notifyListeners();
    });
  }

  final LessonAudioPlayer _audio;

  /// Show one MCQ after a scene; wait until the student answers.
  /// Return null if the sheet is dismissed without an answer.
  Future<SceneMcqResult?> Function(GeneratedMcq mcq)? onAskSceneMcq;

  /// Optional end-of-lesson full quiz offer.
  Future<void> Function()? onOfferFullQuiz;

  /// Persist progress (fire-and-forget from the engine's perspective).
  void Function(
    int sceneIndex, {
    bool completed,
    int quizScore,
    int quizTotal,
  })? onProgressCheckpoint;

  VoidCallback? onScrollToPremium;

  StreamSubscription<double>? _progressSub;

  GeneratedLesson _lesson = welcomeLesson;
  List<TeachingBeat> _beats = const [];
  GeneratedLesson? _beatsForLesson;

  int _slideIndex = 0;
  int _beatIndex = 0;
  int _revealCount = 1;
  int? _activeBulletIndex;
  bool _zoomPulse = false;
  bool _isPlaying = false;
  bool _isPaused = false;
  double _playbackSpeed = ClassroomMemoryGuard.defaultPlaybackSpeed;
  bool _muted = false;
  double _speechProgress = 0;
  int _playSessionId = 0;
  int _pointerStep = 0;
  PremiumSpotlight _premiumSpotlight = PremiumSpotlight.none;
  String _premiumSpotlightText = '';
  String? _caption =
      'Press Play to start the lesson, or ask a question below to generate a new one.';
  TeachingBeatKind? _beatKind;
  String _activeKeyword = '';
  bool _conceptTransition = false;
  bool _disposed = false;
  LessonAudioBundle? _lessonAudio;

  // ── Public state ─────────────────────────────────────────────────────────

  GeneratedLesson get lesson => _lesson;
  List<TeachingBeat> get beats => _ensureBeats();
  int get slideIndex => _slideIndex;
  int get beatIndex => _beatIndex;
  int get segmentIndex => _beatIndex;
  int get revealCount => _revealCount;
  int? get activeBulletIndex => _activeBulletIndex;
  bool get zoomPulse => _zoomPulse;
  bool get isPlaying => _isPlaying;
  bool get isPaused => _isPaused;
  double get playbackSpeed => _playbackSpeed;
  bool get muted => _muted;
  double get speechProgress => _speechProgress;
  int get pointerStep => _pointerStep;
  PremiumSpotlight get premiumSpotlight => _premiumSpotlight;
  String get premiumSpotlightText => _premiumSpotlightText;
  String? get caption => _caption;
  TeachingBeatKind? get beatKind => _beatKind;
  String get activeKeyword => _activeKeyword;
  bool get conceptTransition => _conceptTransition;
  bool get showMemoryTrick =>
      _premiumSpotlight == PremiumSpotlight.memoryTrick ||
      _beatKind == TeachingBeatKind.memoryTrick;
  LessonAudioPlayer get audio => _audio;
  int get playSessionId => _playSessionId;
  bool get hasContinuousAudio => _lessonAudio != null;

  List<String> get currentKeywords {
    final b = beats;
    if (_beatIndex >= 0 && _beatIndex < b.length) {
      final k = b[_beatIndex].keywords;
      if (k.isNotEmpty) return k;
    }
    if (_lesson.slides.isEmpty) return const [];
    final i = _slideIndex.clamp(0, _lesson.slides.length - 1);
    return _lesson.slides[i].keywords;
  }

  List<SubtitleCue> get currentSubtitleCues {
    final spoken = _caption ?? '';
    if (_lesson.slides.isEmpty) {
      return buildSubtitleTimingFromText(spoken);
    }
    final slide = _lesson.slides[_slideIndex.clamp(0, _lesson.slides.length - 1)];
    return slide.resolvedSubtitleTiming(spoken);
  }

  double get progress {
    final audio = _lessonAudio;
    if (audio != null) {
      final total = _audio.duration > Duration.zero ? _audio.duration : audio.duration;
      if (total <= Duration.zero) return 0;
      return (_audio.position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    }
    final b = beats;
    if (b.isEmpty) return 0;
    return (_beatIndex / b.length).clamp(0.0, 1.0);
  }

  GeneratedSlide? get currentSlide {
    if (_lesson.slides.isEmpty) return null;
    return _lesson.slides[_slideIndex.clamp(0, _lesson.slides.length - 1)];
  }

  // ── Lesson binding ───────────────────────────────────────────────────────

  void setLesson(
    GeneratedLesson lesson, {
    int startBeat = 0,
    int startSlide = 0,
  }) {
    ClassroomMemoryGuard.trimLessonCaches();
    _lessonAudio = null;
    _lesson = lesson;
    _beatsForLesson = null;
    _ensureBeats();
    _beatIndex = startBeat.clamp(0, beats.isEmpty ? 0 : beats.length - 1);
    _slideIndex = startSlide.clamp(
      0,
      lesson.slides.isEmpty ? 0 : lesson.slides.length - 1,
    );
    _revealCount = 1;
    _activeBulletIndex = null;
    _speechProgress = 0;
    _pointerStep = 0;
    _premiumSpotlight = PremiumSpotlight.none;
    _premiumSpotlightText = '';
    if (beats.isNotEmpty) {
      _applyBeatVisuals(_beatIndex, notify: false);
    }
    notifyListeners();
  }

  /// Preload one continuous lecture file, then [play] will use it (no per-line TTS).
  Future<void> attachContinuousAudio(LessonAudioBundle bundle) async {
    if (_disposed) return;
    var next = bundle;
    final actual = await _audio.preloadContinuous(
      next.bytes,
      mimeType: next.mimeType,
    );
    if (_disposed) return;
    if (actual > Duration.zero) next = next.withDuration(actual);
    _lessonAudio = next;
    notifyListeners();
  }

  List<TeachingBeat> _ensureBeats() {
    if (!identical(_beatsForLesson, _lesson)) {
      _beatsForLesson = _lesson;
      _beats = teachingSequenceFor(_lesson);
    }
    return _beats;
  }

  // ── Transport ────────────────────────────────────────────────────────────

  void play() {
    if (_disposed) return;
    final b = beats;
    if (b.isEmpty) return;
    if (_lessonAudio != null) {
      if (_beatIndex >= b.length) _beatIndex = 0;
      _startContinuous(from: _spanStart(_beatIndex));
      return;
    }
    _isPlaying = false;
    _isPaused = false;
    _caption =
        'एकात्मिक मराठी आवाज तयार झाला नाही. कृपया पुन्हा Generate AI Lesson दाबा.';
    notifyListeners();
  }

  void pause() {
    if (_disposed) return;
    unawaited(_audio.pause());
    _isPlaying = false;
    _isPaused = true;
    _zoomPulse = false;
    notifyListeners();
  }

  void resume() {
    if (_disposed) return;
    if (_lessonAudio != null && _isPaused) {
      unawaited(_audio.resume());
      _isPlaying = true;
      _isPaused = false;
      notifyListeners();
      return;
    }
    if (_isPaused && (_audio.isPaused || _audio.isLoading)) {
      unawaited(_audio.resume());
      _isPlaying = true;
      _isPaused = false;
      notifyListeners();
      return;
    }
    if (_isPaused) {
      _isPlaying = true;
      _isPaused = false;
      notifyListeners();
      return;
    }
    play();
  }

  void stop() {
    if (_disposed) return;
    _bumpSession();
    unawaited(_audio.stop(emitIdle: true));
    _isPlaying = false;
    _isPaused = false;
    _zoomPulse = false;
    _speechProgress = 0;
    notifyListeners();
  }

  void togglePlayPause() {
    if (_isPlaying) {
      pause();
    } else {
      resume();
    }
  }

  void next() {
    final b = beats;
    if (b.isEmpty) return;
    final n = (_beatIndex + 1).clamp(0, b.length - 1);
    if (n == _beatIndex && _beatIndex >= b.length - 1) {
      stop();
      return;
    }
    jumpToBeat(n, autoPlay: true);
  }

  void previous() {
    final b = beats;
    if (b.isEmpty) return;
    final p = (_beatIndex - 1).clamp(0, b.length - 1);
    jumpToBeat(p, autoPlay: _isPlaying || _isPaused);
  }

  void replay() {
    _beatIndex = 0;
    _slideIndex = 0;
    _revealCount = 1;
    _isPaused = false;
    _speechProgress = 0;
    _activeBulletIndex = null;
    notifyListeners();
    play();
  }

  /// Re-explain the current scene from its first beat (Explain Again).
  void explainAgain() {
    final b = beats;
    if (b.isEmpty) {
      replay();
      return;
    }
    final start = firstBeatIndexForSlide(b, _slideIndex);
    jumpToBeat(start, autoPlay: true);
  }

  /// Jump to the first Example beat in the lesson (or examples scene).
  void giveAnotherExampleFocus() {
    final b = beats;
    if (b.isEmpty) return;
    final exampleBeat = b.indexWhere((x) => x.kind == TeachingBeatKind.example);
    if (exampleBeat >= 0) {
      jumpToBeat(exampleBeat, autoPlay: true);
      return;
    }
    final exampleSlide = _lesson.slides.indexWhere(
      (s) => s.sceneType == LessonSceneType.examples,
    );
    if (exampleSlide >= 0) {
      jumpToSlide(exampleSlide, autoPlay: true);
      return;
    }
    explainAgain();
  }

  /// Show an extra example on the board without a second TTS request.
  Future<void> speakAlternateExample(String exampleText) async {
    if (_disposed) return;
    final text = facultyNarration(exampleText);
    if (text.isEmpty) return;
    _caption = text;
    _beatKind = TeachingBeatKind.example;
    notifyListeners();
  }

  void skipSeconds(int seconds) {
    unawaited(_audio.skipBy(Duration(seconds: seconds)));
  }

  Future<void> setSpeed(double speed) async {
    _playbackSpeed = speed.clamp(0.5, 1.5);
    await _audio.setSpeed(_playbackSpeed);
    notifyListeners();
  }

  Future<void> setMuted(bool muted) async {
    _muted = muted;
    await _audio.setMuted(muted);
    notifyListeners();
  }

  void seekFraction(double fraction) {
    final f = fraction.clamp(0.0, 1.0);
    final audio = _lessonAudio;
    if (audio != null) {
      final total = _audio.duration > Duration.zero ? _audio.duration : audio.duration;
      if (total > Duration.zero) {
        unawaited(_audio.seekTo(
          Duration(milliseconds: (f * total.inMilliseconds).round()),
        ));
      }
      return;
    }
    if (_audio.isPlaying || _audio.isPaused || _audio.isLoading) {
      unawaited(_audio.seekFraction(f));
      return;
    }
    final b = beats;
    if (b.isEmpty) return;
    final target = b.length == 1
        ? 0
        : (f * (b.length - 1)).round().clamp(0, b.length - 1);
    if (_isPlaying || _isPaused) {
      jumpToBeat(target, autoPlay: true);
    } else {
      _applyBeatVisuals(target);
    }
  }

  void jumpToBeat(int beatIndex, {required bool autoPlay}) {
    final b = beats;
    if (b.isEmpty) return;
    final i = beatIndex.clamp(0, b.length - 1);
    if (_lessonAudio == null) {
      _applyBeatVisuals(i);
      _isPlaying = false;
      _isPaused = false;
      _caption =
          'एकात्मिक मराठी आवाज तयार झाला नाही. कृपया पुन्हा Generate AI Lesson दाबा.';
      notifyListeners();
      return;
    }
    _applyBeatVisuals(i, resetSpeechProgress: false);
    final from = _spanStart(i);
    if (!autoPlay) {
      unawaited(_audio.seekTo(from));
      unawaited(_audio.pause());
      _isPlaying = false;
      _isPaused = false;
      notifyListeners();
      return;
    }
    if (_isPlaying && !_isPaused) {
      unawaited(_audio.seekTo(from));
      return;
    }
    if (_isPaused) {
      unawaited(_audio.seekTo(from));
      resume();
      return;
    }
    _startContinuous(from: from);
  }

  void jumpToSlide(int slideIndex, {bool autoPlay = true}) {
    final i = firstBeatIndexForSlide(beats, slideIndex);
    jumpToBeat(i, autoPlay: autoPlay);
  }

  void setCaption(String? caption) {
    _caption = caption;
    notifyListeners();
  }

  /// Caption-only echo — classroom voice is the continuous ElevenLabs file.
  Future<void> speakOnce(String text) async {
    if (_disposed) return;
    final spoken = facultyNarration(text);
    if (spoken.isEmpty) return;
    _caption = spoken;
    notifyListeners();
  }

  // ── Internals ────────────────────────────────────────────────────────────

  void _bumpSession() => _playSessionId++;

  void _applyBeatVisuals(
    int beatIndex, {
    bool notify = true,
    bool resetSpeechProgress = true,
  }) {
    final b = beats;
    if (b.isEmpty) return;
    final i = beatIndex.clamp(0, b.length - 1);
    final beat = b[i];
    _beatIndex = i;
    _slideIndex = _lesson.slides.isEmpty
        ? 0
        : beat.slideIndex.clamp(0, _lesson.slides.length - 1);
    _caption = beat.speakText;
    _beatKind = beat.kind;
    _revealCount = beat.revealCount;
    _activeBulletIndex = beat.activeBulletIndex;
    _premiumSpotlight = beat.spotlight;
    _premiumSpotlightText = beat.spotlightText;
    if (resetSpeechProgress) _speechProgress = 0;
    _zoomPulse = false;
    _syncPointerFromSpeech();
    if (notify) notifyListeners();
  }

  Duration _spanStart(int beatIndex) {
    final spans = _lessonAudio?.spans;
    if (spans == null || spans.isEmpty) return Duration.zero;
    return spans[beatIndex.clamp(0, spans.length - 1)].start;
  }

  void _startContinuous({required Duration from}) {
    _bumpSession();
    final sessionId = _playSessionId;
    _isPlaying = true;
    _isPaused = false;
    notifyListeners();
    unawaited(_runContinuous(sessionId, from: from));
  }

  Future<void> _runContinuous(int sessionId, {required Duration from}) async {
    try {
      await _audio.setSpeed(_playbackSpeed);
      await _audio.setMuted(_muted);
      await _audio.playContinuous(from: from);
    } catch (e) {
      debugPrint('VideoClassroomEngine continuous play: $e');
    }
    if (sessionId != _playSessionId || _disposed) return;
    await _finishLesson();
  }

  void _syncContinuousFromProgress(double fileProgress) {
    final bundle = _lessonAudio;
    if (bundle == null || bundle.spans.isEmpty) return;
    final total = _audio.duration > Duration.zero ? _audio.duration : bundle.duration;
    final pos = total <= Duration.zero
        ? Duration.zero
        : Duration(
            milliseconds: (fileProgress * total.inMilliseconds).round(),
          );
    var idx = 0;
    for (var i = 0; i < bundle.spans.length; i++) {
      final span = bundle.spans[i];
      if (pos < span.end || i == bundle.spans.length - 1) {
        idx = i;
        break;
      }
    }
    final span = bundle.spans[idx];
    final spanMs = (span.end - span.start).inMilliseconds;
    final local = spanMs <= 0
        ? 1.0
        : ((pos - span.start).inMilliseconds / spanMs).clamp(0.0, 1.0);
    if (idx != _beatIndex) {
      _applyBeatVisuals(idx, notify: false, resetSpeechProgress: false);
    }
    _speechProgress = local;
    final slide = currentSlide;
    if (slide != null && slide.animationSteps > 1) {
      final b = beats;
      final target = (idx >= 0 && idx < b.length)
          ? b[idx].revealCount.clamp(1, slide.animationSteps)
          : slide.animationSteps;
      _revealCount = (1 + (local.clamp(0.0, 0.999) * target).floor())
          .clamp(1, target);
    }
    _syncPointerFromSpeech();
    _syncActiveKeywordFromSpeech();
  }

  Future<void> _finishLesson({bool offerQuiz = true}) async {
    final b = beats;
    _beatIndex = b.length;
    _isPlaying = false;
    _activeBulletIndex = null;
    _caption = _lesson.premium.quickRevision.trim().isNotEmpty
        ? _lesson.premium.quickRevision
        : (_lesson.summary.trim().isNotEmpty
            ? _lesson.summary
            : 'Lesson complete! Check PYQ, Quiz and Notes below.');
    _zoomPulse = false;
    notifyListeners();
    onProgressCheckpoint?.call(
      (_lesson.slides.length - 1).clamp(0, 9999),
      completed: true,
    );
    onScrollToPremium?.call();
    if (offerQuiz) {
      await onOfferFullQuiz?.call();
    }
  }

  void _syncPointerFromSpeech() {
    final slide = currentSlide;
    if (slide == null || slide.pointerPath.isEmpty) {
      _pointerStep = 0;
      return;
    }
    final n = slide.pointerPath.length;
    _pointerStep =
        (_speechProgress.clamp(0.0, 0.999) * n).floor().clamp(0, n - 1);
  }

  void _syncActiveKeywordFromSpeech() {
    final keys = currentKeywords;
    final spoken = (_caption ?? '').trim();
    if (keys.isEmpty || spoken.isEmpty) {
      _activeKeyword = '';
      return;
    }
    final words = spoken
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      _activeKeyword = '';
      return;
    }
    final idx = (_speechProgress.clamp(0.0, 0.999) * words.length)
        .floor()
        .clamp(0, words.length - 1);
    final window = words
        .sublist(0, idx + 1)
        .join(' ')
        .toLowerCase();
    for (final k in keys) {
      final t = k.trim().toLowerCase();
      if (t.isEmpty) continue;
      if (window.contains(t)) {
        _activeKeyword = k;
        return;
      }
    }
    // Fallback: rotate keywords with speech progress.
    _activeKeyword = keys[
        (_speechProgress.clamp(0.0, 0.999) * keys.length)
            .floor()
            .clamp(0, keys.length - 1)];
  }

  /// Synthesize a quick check MCQ when Gemini omitted [GeneratedSlide.sectionQuestion].
  GeneratedMcq resolveSceneMcq(GeneratedSlide slide) {
    if (slide.sectionQuestion != null) return slide.sectionQuestion!;
    if (_lesson.mcqs.isNotEmpty) {
      final idx = slide.sceneType.index % _lesson.mcqs.length;
      return _lesson.mcqs[idx];
    }
    final key = slide.keywords.isNotEmpty
        ? slide.keywords.first
        : (slide.bullets.isNotEmpty ? slide.bullets.first : slide.title);
    final marathi = RegExp(r'[\u0900-\u097F]').hasMatch(key + slide.title);
    if (marathi) {
      return GeneratedMcq(
        question: '${slide.title} — मुख्य मुद्दा कोणता?',
        options: [
          key,
          'वरीलपैकी नाही',
          'संपूर्णपणे चुकीचे',
          'केवळ उदाहरण',
        ],
        correctIndex: 0,
        explanation: slide.explanation.trim().isNotEmpty
            ? slide.explanation
            : 'योग्य उत्तर: $key. ही संकल्पना धड्यातील मुख्य मुद्दा आहे.',
      );
    }
    return GeneratedMcq(
      question: '${slide.title} — what is the key idea?',
      options: [
        key,
        'None of the above',
        'Completely unrelated',
        'Only an example',
      ],
      correctIndex: 0,
      explanation: slide.explanation.trim().isNotEmpty
          ? slide.explanation
          : 'Correct: $key. That is the core idea of this scene.',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _bumpSession();
    unawaited(_progressSub?.cancel());
    unawaited(_audio.dispose());
    super.dispose();
  }
}
