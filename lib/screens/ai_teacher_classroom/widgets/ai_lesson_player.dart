import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/classroom_theme.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/classroom_avatar.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/slide_visuals.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Modern NotebookLM-style AI Lesson Player — responsive 16:9 presentation
/// canvas with in-player subtitles and YouTube-style controls.
///
/// Reusable for every subject/chapter (driven only by [GeneratedSlide] data).
class AiLessonPlayer extends StatefulWidget {
  const AiLessonPlayer({
    super.key,
    required this.slides,
    required this.slideIndex,
    required this.revealCount,
    required this.state,
    required this.isPlaying,
    required this.progress,
    required this.subtitle,
    required this.speed,
    required this.muted,
    required this.onPlayPause,
    required this.onReplay,
    required this.onStop,
    required this.onSpeedChanged,
    required this.onMuteChanged,
    this.onSeek,
    this.onNext,
    this.onPrevious,
    this.onSkipBack,
    this.onSkipForward,
    this.subtitleHighlight = 0,
    this.keywords = const [],
    this.activeBulletIndex,
    this.zoom = false,
    this.topicName = '',
    this.listenable,
    this.embedded = false,
    this.bookmarked = false,
    this.onBookmarkToggle,
    this.activeKeyword = '',
    this.memoryTrickText = '',
    this.showMemoryTrick = false,
    this.conceptTransition = false,
    this.showAvatar = false,
    this.controlsEnabled = true,
  });

  final List<GeneratedSlide> slides;
  final int slideIndex;
  final int revealCount;
  final TeacherAvatarState state;
  final bool isPlaying;
  final double progress;
  final String? subtitle;
  /// 0.0–1.0 progress through the current spoken subtitle (word highlight).
  final double subtitleHighlight;
  /// Keywords from the current scene — emphasized in karaoke subtitles.
  final List<String> keywords;
  final int? activeBulletIndex;
  final double speed;
  final bool muted;
  final VoidCallback onPlayPause;
  final VoidCallback onReplay;
  final VoidCallback onStop;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<bool> onMuteChanged;
  /// Seek within the current narration clip (0.0–1.0). Same progress bar UI.
  final ValueChanged<double>? onSeek;
  /// Skip to the next teaching beat / scene.
  final VoidCallback? onNext;
  /// Jump back to the previous teaching beat / scene.
  final VoidCallback? onPrevious;
  final VoidCallback? onSkipBack;
  final VoidCallback? onSkipForward;
  final bool zoom;
  final String topicName;
  final bool bookmarked;
  final VoidCallback? onBookmarkToggle;

  /// Keyword currently being spoken — board chips zoom/highlight on it.
  final String activeKeyword;

  /// Memory-trick card text (visual teaching aid).
  final String memoryTrickText;
  final bool showMemoryTrick;

  /// Soft wipe between Smart Faculty stages (not a slide flip).
  final bool conceptTransition;

  /// Talking avatar overlay. Off by default for premium educational videos.
  final bool showAvatar;

  /// When false, transport buttons are disabled (preview / no owner).
  final bool controlsEnabled;

  /// When provided, fullscreen route rebuilds from the underlay player
  /// configuration each time this listenable notifies.
  final ValueNotifier<int>? listenable;

  /// When true, shows exit-fullscreen instead of enter-fullscreen.
  final bool embedded;

  static const speeds = <double>[0.75, 0.9, 1.0, 1.25, 1.5];

  @override
  State<AiLessonPlayer> createState() => _AiLessonPlayerState();
}

class _AiLessonPlayerState extends State<AiLessonPlayer> {
  bool _controlsVisible = true;

  void _toggleControls() => setState(() => _controlsVisible = !_controlsVisible);

  Future<void> _openFullscreen() async {
    final listenable = widget.listenable;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (context, animation, secondary) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Center(
                  child: listenable == null
                      ? _buildEmbeddedClone()
                      : ValueListenableBuilder<int>(
                          valueListenable: listenable,
                          builder: (context, _, _) {
                            // Parent rebuilds this player via snapshot on the
                            // same route tree by reconstructing from live props
                            // passed into the original widget — we re-read
                            // through a Builder that mounts a fresh player
                            // using the latest widget configuration from the
                            // underlay. Since the underlay's widget may have
                            // updated, we grab it via the snapshot if set.
                            return _FullscreenLivePlayer(source: widget);
                          },
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmbeddedClone() {
    return AiLessonPlayer(
      slides: widget.slides,
      slideIndex: widget.slideIndex,
      revealCount: widget.revealCount,
      state: widget.state,
      isPlaying: widget.isPlaying,
      progress: widget.progress,
      subtitle: widget.subtitle,
      subtitleHighlight: widget.subtitleHighlight,
      keywords: widget.keywords,
      activeBulletIndex: widget.activeBulletIndex,
      speed: widget.speed,
      muted: widget.muted,
      onPlayPause: widget.onPlayPause,
      onReplay: widget.onReplay,
      onStop: widget.onStop,
      onSpeedChanged: widget.onSpeedChanged,
      onMuteChanged: widget.onMuteChanged,
      onSeek: widget.onSeek,
      onNext: widget.onNext,
      onPrevious: widget.onPrevious,
      onSkipBack: widget.onSkipBack,
      onSkipForward: widget.onSkipForward,
      zoom: widget.zoom,
      topicName: widget.topicName,
      bookmarked: widget.bookmarked,
      onBookmarkToggle: widget.onBookmarkToggle,
      activeKeyword: widget.activeKeyword,
      memoryTrickText: widget.memoryTrickText,
      showMemoryTrick: widget.showMemoryTrick,
      conceptTransition: widget.conceptTransition,
      showAvatar: widget.showAvatar,
      embedded: true,
      controlsEnabled: widget.controlsEnabled,
    );
  }

  String _speedLabel(double s) {
    if ((s - 0.9).abs() < 0.02) return '0.9x';
    if (s == 1.0) return '1x';
    if (s == 0.75) return '0.75x';
    if (s == 1.25) return '1.25x';
    if (s == 1.5) return '1.5x';
    return '${s}x';
  }

  void _cycleSpeed() {
    if (!widget.controlsEnabled) return;
    final speeds = AiLessonPlayer.speeds;
    final i = speeds.indexWhere((s) => (s - widget.speed).abs() < 0.02);
    final next = speeds[(i < 0 ? 0 : i + 1) % speeds.length];
    widget.onSpeedChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    // Keep the control bar always hittable — never bury it under a
    // full-surface InkWell / AbsorbPointer (that made Stop look "stuck").
    try {
      final canvas = AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.embedded ? 0 : 18),
          child: Material(
            color: ClassroomTheme.navy,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Decorative atmosphere — never participates in hit testing.
                const IgnorePointer(
                  child: CustomPaint(painter: _PlayerAtmospherePainter()),
                ),
                // Content tap toggles chrome opacity only; does not cover the
                // control bar (bottom inset) and never uses AbsorbPointer.
                Positioned.fill(
                  bottom: 72,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleControls,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _controlsVisible || widget.isPlaying ? 1 : 0.92,
                      child: _safeCanvasBody(),
                    ),
                  ),
                ),
                // Optional avatar — disabled for premium educational video mode.
                if (widget.showAvatar &&
                    widget.slides.isNotEmpty &&
                    widget.state != TeacherAvatarState.thinking &&
                    widget.state != TeacherAvatarState.listening)
                  Positioned(
                    left: 8,
                    bottom: 78,
                    child: IgnorePointer(
                      child: _TeacherAvatarLayer(
                        state: widget.state,
                        isSpeaking: widget.isPlaying,
                        speechProgress: widget.subtitleHighlight,
                        pointerLabel: _activePointerLabel(),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 150,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.5),
                            Colors.black.withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if ((widget.subtitle ?? '').trim().isNotEmpty)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 74,
                    // Subtitles are visual only — never block Stop / Play taps.
                    child: IgnorePointer(
                      child: _InPlayerSubtitle(
                        text: widget.subtitle!.trim(),
                        highlight: widget.subtitleHighlight,
                        keywords: widget.keywords,
                      ),
                    ),
                  ),
                Positioned(
                  left: 12,
                  top: 10,
                  right: 12,
                  child: Row(
                    children: [
                      _Chip(
                        icon: Icons.auto_awesome_rounded,
                        label: widget.topicName.trim().isEmpty
                            ? 'AI Lesson'
                            : widget.topicName,
                      ),
                      const Spacer(),
                      if (widget.onBookmarkToggle != null)
                        IconButton(
                          tooltip: widget.bookmarked
                              ? 'Remove bookmark'
                              : 'Bookmark scene',
                          onPressed: widget.onBookmarkToggle,
                          icon: Icon(
                            widget.bookmarked
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            color: widget.bookmarked
                                ? ClassroomTheme.accent
                                : Colors.white,
                            size: 22,
                          ),
                        ),
                      if (widget.slides.isNotEmpty)
                        _Chip(
                          icon: Icons.layers_rounded,
                          label:
                              '${widget.slideIndex.clamp(0, widget.slides.length - 1) + 1}/${widget.slides.length}',
                        ),
                    ],
                  ),
                ),
                // Control bar always stacked last so it wins hit tests.
                // Never wrap in AbsorbPointer / full-surface InkWell.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: Colors.transparent,
                    child: _YouTubeControls(
                      isPlaying: widget.isPlaying,
                      progress: widget.progress,
                      muted: widget.muted,
                      speedLabel: _speedLabel(widget.speed),
                      controlsEnabled: widget.controlsEnabled,
                      onPlayPause: widget.onPlayPause,
                      onReplay: widget.onReplay,
                      onStop: widget.onStop,
                      onPrevious: widget.onPrevious,
                      onNext: widget.onNext,
                      onSkipBack: widget.onSkipBack,
                      onSkipForward: widget.onSkipForward,
                      onSpeedTap: _cycleSpeed,
                      onMuteToggle: () => widget.onMuteChanged(!widget.muted),
                      onSeek: widget.controlsEnabled ? widget.onSeek : null,
                      onFullscreen: widget.embedded
                          ? () => Navigator.of(context).maybePop()
                          : _openFullscreen,
                      exitFullscreen: widget.embedded,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (widget.embedded) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width,
            maxHeight: MediaQuery.sizeOf(context).height,
          ),
          child: canvas,
        );
      }
      return canvas;
    } catch (e, st) {
      debugPrint('AiLessonPlayer build failed: $e\n$st');
      return _PlayerErrorPanel(
        topicName: widget.topicName,
        onPlayPause: widget.onPlayPause,
        onStop: widget.onStop,
      );
    }
  }

  /// Never let a scene build exception white-screen the classroom.
  Widget _safeCanvasBody() {
    try {
      return _buildCanvasBody();
    } catch (e, st) {
      debugPrint('AiLessonPlayer canvas body failed: $e\n$st');
      return const _StatusCanvas(
        icon: Icons.error_outline_rounded,
        title: 'स्लाइड सध्या दाखवता आली नाही',
        subtitle: 'खालील नियंत्रण वापरून धडा सुरू ठेवा',
      );
    }
  }

  String? _activePointerLabel() {
    if (widget.slides.isEmpty) return null;
    final index = widget.slideIndex.clamp(0, widget.slides.length - 1);
    final slide = widget.slides[index];
    if (slide.pointerPath.isNotEmpty && widget.revealCount >= 1) {
      final i = (widget.revealCount - 1).clamp(0, slide.pointerPath.length - 1);
      return slide.pointerPath[i];
    }
    if (widget.keywords.isNotEmpty) {
      final i = (widget.subtitleHighlight.clamp(0.0, 0.999) * widget.keywords.length)
          .floor()
          .clamp(0, widget.keywords.length - 1);
      return widget.keywords[i];
    }
    if (slide.keywords.isNotEmpty && widget.revealCount >= 1) {
      final i = (widget.revealCount - 1).clamp(0, slide.keywords.length - 1);
      return slide.keywords[i];
    }
    return null;
  }

  Widget _buildCanvasBody() {
    if (widget.state == TeacherAvatarState.thinking) {
      final topic = widget.topicName.trim();
      return _StatusCanvas(
        icon: Icons.auto_awesome_rounded,
        title: 'धडा तयार होत आहे…',
        subtitle: topic.isEmpty ? '' : topic,
        showLoader: true,
      );
    }
    if (widget.state == TeacherAvatarState.listening) {
      return const _StatusCanvas(
        icon: Icons.mic_rounded,
        title: 'शंका विचारा',
        subtitle: 'विचारल्यावर हाच धडा सुरू राहील',
      );
    }
    if (widget.slides.isEmpty) {
      return _StatusCanvas(
        icon: Icons.play_circle_outline_rounded,
        title: widget.topicName.trim().isEmpty ? 'AI Lesson Player' : widget.topicName,
        subtitle: 'Play दाबा आणि धडा सुरू करा',
      );
    }

    final index = widget.slideIndex.clamp(0, widget.slides.length - 1);
    final slide = widget.slides[index];

    // Key ONLY on scene index — never remount on revealCount (that caused
    // the slideshow flicker). Progressive draws happen inside SceneEngine.
    return AnimatedSwitcher(
      duration: Duration(
        milliseconds: widget.conceptTransition ? 640 : 420,
      ),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: widget.conceptTransition
                  ? const Offset(0.06, 0)
                  : const Offset(0.02, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: Padding(
        key: ValueKey('canvas_scene_$index'),
        padding: const EdgeInsets.fromLTRB(20, 44, 20, 96),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      slide.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SceneBadge(sceneType: slide.sceneType),
                ],
              ),
              if ((widget.subtitle ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: EdgeInsets.only(left: widget.showAvatar ? 72 : 0),
                  child: _SpokenSentenceBoard(
                    text: widget.subtitle!.trim(),
                    speechProgress: widget.subtitleHighlight,
                    isSpeaking: widget.isPlaying,
                    keywords: widget.keywords,
                    activeKeyword: widget.activeKeyword,
                  ),
                ),
              ],
              if (widget.showMemoryTrick &&
                  widget.memoryTrickText.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: EdgeInsets.only(left: widget.showAvatar ? 72 : 0),
                  child: _MemoryTrickCard(text: widget.memoryTrickText.trim()),
                ),
              ],
              const SizedBox(height: 14),
              // Leave room on the left only when the teacher avatar overlay is on.
              Padding(
                padding: EdgeInsets.only(left: widget.showAvatar ? 72 : 0),
                child: SlideVisualContent(
                  slide: slide,
                  revealCount: widget.revealCount,
                  zoom: widget.zoom || widget.activeKeyword.isNotEmpty,
                  activeBulletIndex: widget.activeBulletIndex,
                  speechProgress: widget.subtitleHighlight,
                  isSpeaking: widget.isPlaying,
                  narratedKeywords: widget.keywords,
                  activeKeyword: widget.activeKeyword,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sentence currently being taught — appears word-by-word with keyword zoom.
class _SpokenSentenceBoard extends StatelessWidget {
  const _SpokenSentenceBoard({
    required this.text,
    required this.speechProgress,
    required this.isSpeaking,
    required this.keywords,
    required this.activeKeyword,
  });

  final String text;
  final double speechProgress;
  final bool isSpeaking;
  final List<String> keywords;
  final String activeKeyword;

  bool _matchesKeyword(String word) {
    final bare =
        word.replaceAll(RegExp(r'[^\w\u0900-\u097F]+'), '').toLowerCase();
    if (bare.isEmpty) return false;
    final hot = activeKeyword.trim().toLowerCase();
    if (hot.isNotEmpty && (bare.contains(hot) || hot.contains(bare))) {
      return true;
    }
    for (final k in keywords) {
      final t = k.trim().toLowerCase();
      if (t.isEmpty) continue;
      if (bare.contains(t) || t.contains(bare)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final words =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const SizedBox.shrink();
    final active = isSpeaking
        ? (speechProgress.clamp(0.0, 0.999) * words.length)
            .floor()
            .clamp(0, words.length - 1)
        : words.length - 1;
    final revealed = isSpeaking ? active + 1 : words.length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Wrap(
        spacing: 5,
        runSpacing: 4,
        children: [
          for (var i = 0; i < words.length; i++)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: i < revealed ? 1 : 0.18,
              child: AnimatedScale(
                scale: () {
                  final isHot = i == active && isSpeaking;
                  final isKey = _matchesKeyword(words[i]);
                  if (isHot && isKey) return 1.14;
                  if (isHot) return 1.06;
                  return 1.0;
                }(),
                duration: const Duration(milliseconds: 180),
                child: Text(
                  words[i],
                  style: TextStyle(
                    color: i == active && isSpeaking
                        ? ClassroomTheme.accent
                        : Colors.white.withValues(alpha: 0.95),
                    fontSize: _matchesKeyword(words[i]) ? 15.5 : 14.5,
                    height: 1.4,
                    fontWeight: i == active && isSpeaking
                        ? FontWeight.w900
                        : FontWeight.w600,
                    backgroundColor: i == active &&
                            isSpeaking &&
                            _matchesKeyword(words[i])
                        ? ClassroomTheme.accent.withValues(alpha: 0.28)
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MemoryTrickCard extends StatelessWidget {
  const _MemoryTrickCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: 1),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              ClassroomTheme.accent.withValues(alpha: 0.35),
              Colors.white.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ClassroomTheme.accent.withValues(alpha: 0.7)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.psychology_alt_rounded,
                color: ClassroomTheme.accent, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'स्मरण युक्ती',
                    style: TextStyle(
                      color: ClassroomTheme.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact teacher figure overlaid on the lesson canvas.
class _TeacherAvatarLayer extends StatelessWidget {
  const _TeacherAvatarLayer({
    required this.state,
    required this.isSpeaking,
    required this.speechProgress,
    this.pointerLabel,
  });

  final TeacherAvatarState state;
  final bool isSpeaking;
  final double speechProgress;
  final String? pointerLabel;

  @override
  Widget build(BuildContext context) {
    return ClassroomAvatar(
      state: isSpeaking ? TeacherAvatarState.speaking : state,
      size: 108,
      isSpeaking: isSpeaking,
      speechProgress: speechProgress,
      pointerLabel: pointerLabel,
      lookTowardContent: true,
    );
  }
}

/// Rebuilds the fullscreen player from the underlay player's latest config
/// when [AiLessonPlayer.listenable] ticks. The underlay Element keeps the
/// source widget configuration up to date via normal parent setState.
class _FullscreenLivePlayer extends StatelessWidget {
  const _FullscreenLivePlayer({required this.source});

  final AiLessonPlayer source;

  @override
  Widget build(BuildContext context) {
    // Walk up to find the underlay AiLessonPlayer element and clone its
    // current widget configuration for a live fullscreen view.
    AiLessonPlayer? live;
    void visitor(Element element) {
      if (element.widget is AiLessonPlayer) {
        final w = element.widget as AiLessonPlayer;
        if (!w.embedded) live = w;
      }
      element.visitChildren(visitor);
    }

    final root = context.findRootAncestorStateOfType<NavigatorState>()?.context;
    if (root != null) {
      root.visitChildElements(visitor);
    }
    final cfg = live ?? source;
    return AiLessonPlayer(
      slides: cfg.slides,
      slideIndex: cfg.slideIndex,
      revealCount: cfg.revealCount,
      state: cfg.state,
      isPlaying: cfg.isPlaying,
      progress: cfg.progress,
      subtitle: cfg.subtitle,
      subtitleHighlight: cfg.subtitleHighlight,
      keywords: cfg.keywords,
      activeBulletIndex: cfg.activeBulletIndex,
      speed: cfg.speed,
      muted: cfg.muted,
      onPlayPause: cfg.onPlayPause,
      onReplay: cfg.onReplay,
      onStop: cfg.onStop,
      onSpeedChanged: cfg.onSpeedChanged,
      onMuteChanged: cfg.onMuteChanged,
      onSeek: cfg.onSeek,
      onNext: cfg.onNext,
      onPrevious: cfg.onPrevious,
      onSkipBack: cfg.onSkipBack,
      onSkipForward: cfg.onSkipForward,
      zoom: cfg.zoom,
      topicName: cfg.topicName,
      bookmarked: cfg.bookmarked,
      onBookmarkToggle: cfg.onBookmarkToggle,
      activeKeyword: cfg.activeKeyword,
      memoryTrickText: cfg.memoryTrickText,
      showMemoryTrick: cfg.showMemoryTrick,
      conceptTransition: cfg.conceptTransition,
      showAvatar: cfg.showAvatar,
      embedded: true,
      controlsEnabled: cfg.controlsEnabled,
    );
  }
}

class _InPlayerSubtitle extends StatefulWidget {
  const _InPlayerSubtitle({
    required this.text,
    required this.highlight,
    this.keywords = const [],
  });

  final String text;
  final double highlight;
  final List<String> keywords;

  @override
  State<_InPlayerSubtitle> createState() => _InPlayerSubtitleState();
}

class _InPlayerSubtitleState extends State<_InPlayerSubtitle> {
  final _scroll = ScrollController();

  bool _isKeyword(String word) {
    final bare = word.replaceAll(RegExp(r'[^\w\u0900-\u097F]+'), '');
    for (final k in widget.keywords) {
      if (k.trim().isEmpty) continue;
      if (bare.contains(k.trim()) || k.trim().contains(bare)) return true;
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant _InPlayerSubtitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlight != widget.highlight || oldWidget.text != widget.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final max = _scroll.position.maxScrollExtent;
        _scroll.animateTo(
          (max * widget.highlight.clamp(0.0, 1.0)).clamp(0.0, max),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words =
        widget.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final activeIndex = words.isEmpty
        ? -1
        : (widget.highlight.clamp(0.0, 1.0) * words.length)
            .floor()
            .clamp(0, words.length - 1);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 96),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ClassroomTheme.glassDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: words.isEmpty
                ? Text(
                    widget.text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : SingleChildScrollView(
                    controller: _scroll,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          for (var i = 0; i < words.length; i++) ...[
                            if (i > 0) const TextSpan(text: ' '),
                            TextSpan(
                              text: words[i],
                              style: TextStyle(
                                color: i == activeIndex && widget.highlight > 0
                                    ? ClassroomTheme.accent
                                    : (i <= activeIndex && widget.highlight > 0
                                        ? Colors.white
                                        : Colors.white70),
                                fontSize: _isKeyword(words[i]) ? 16 : 15,
                                height: 1.4,
                                fontWeight: i == activeIndex && widget.highlight > 0
                                    ? FontWeight.w900
                                    : (_isKeyword(words[i])
                                        ? FontWeight.w800
                                        : FontWeight.w600),
                                backgroundColor:
                                    i == activeIndex && widget.highlight > 0
                                        ? ClassroomTheme.accent
                                            .withValues(alpha: 0.28)
                                        : (_isKeyword(words[i])
                                            ? ClassroomTheme.keyword
                                                .withValues(alpha: 0.22)
                                            : null),
                              ),
                            ),
                          ],
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _YouTubeControls extends StatelessWidget {
  const _YouTubeControls({
    required this.isPlaying,
    required this.progress,
    required this.muted,
    required this.speedLabel,
    required this.onPlayPause,
    required this.onReplay,
    required this.onStop,
    required this.onSpeedTap,
    required this.onMuteToggle,
    required this.onFullscreen,
    required this.exitFullscreen,
    this.controlsEnabled = true,
    this.onSeek,
    this.onNext,
    this.onPrevious,
    this.onSkipBack,
    this.onSkipForward,
  });

  final bool isPlaying;
  final double progress;
  final bool muted;
  final String speedLabel;
  final bool controlsEnabled;
  final VoidCallback onPlayPause;
  final VoidCallback onReplay;
  final VoidCallback onStop;
  final VoidCallback onSpeedTap;
  final VoidCallback onMuteToggle;
  final VoidCallback onFullscreen;
  final bool exitFullscreen;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onSkipBack;
  final VoidCallback? onSkipForward;

  void _handleSeekTap(Offset local, double width) {
    if (onSeek == null || width <= 0) return;
    onSeek!((local.dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: onSeek == null
                    ? null
                    : (d) => _handleSeekTap(d.localPosition, constraints.maxWidth),
                onHorizontalDragUpdate: onSeek == null
                    ? null
                    : (d) =>
                        _handleSeekTap(d.localPosition, constraints.maxWidth),
                child: SizedBox(
                  height: 16,
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        color: AppColors.orange,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous',
                onPressed: controlsEnabled ? onPrevious : null,
                icon: const Icon(
                  Icons.skip_previous_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              IconButton(
                tooltip: 'Back 10s',
                onPressed: controlsEnabled ? onSkipBack : null,
                icon: const Icon(
                  Icons.replay_10_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              IconButton(
                tooltip: isPlaying ? 'Pause' : 'Play / Resume',
                onPressed: controlsEnabled ? onPlayPause : null,
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              IconButton(
                tooltip: 'Forward 10s',
                onPressed: controlsEnabled ? onSkipForward : null,
                icon: const Icon(
                  Icons.forward_10_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              IconButton(
                tooltip: 'Stop',
                onPressed: controlsEnabled ? onStop : null,
                icon: const Icon(Icons.stop_rounded, color: Colors.white, size: 24),
              ),
              IconButton(
                tooltip: 'Next',
                onPressed: controlsEnabled ? onNext : null,
                icon: const Icon(
                  Icons.skip_next_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              IconButton(
                tooltip: 'Replay',
                onPressed: controlsEnabled ? onReplay : null,
                icon: const Icon(Icons.replay_rounded, color: Colors.white, size: 22),
              ),
              IconButton(
                tooltip: muted ? 'Unmute' : 'Volume',
                onPressed: controlsEnabled ? onMuteToggle : null,
                icon: Icon(
                  muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: controlsEnabled ? onSpeedTap : null,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(40, 36),
                ),
                child: Text(
                  speedLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
              IconButton(
                tooltip: exitFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                onPressed: controlsEnabled ? onFullscreen : null,
                icon: Icon(
                  exitFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fallback panel when the player itself fails to build — avoids a white screen.
class _PlayerErrorPanel extends StatelessWidget {
  const _PlayerErrorPanel({
    required this.topicName,
    required this.onPlayPause,
    required this.onStop,
  });

  final String topicName;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Material(
        color: ClassroomTheme.navy,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 40),
            const SizedBox(height: 12),
            Text(
              topicName.trim().isEmpty ? 'AI Lesson Player' : topicName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Something went wrong loading this scene.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Play / Resume',
                  onPressed: onPlayPause,
                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                ),
                IconButton(
                  tooltip: 'Stop',
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_rounded, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white70),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SceneBadge extends StatelessWidget {
  const _SceneBadge({required this.sceneType});

  final LessonSceneType sceneType;

  @override
  Widget build(BuildContext context) {
    final label = switch (sceneType) {
      LessonSceneType.title => 'Title',
      LessonSceneType.introduction => 'Intro',
      LessonSceneType.mainExplanation => 'Explain',
      LessonSceneType.importantPoints => 'Points',
      LessonSceneType.examples => 'Example',
      LessonSceneType.diagram => 'Diagram',
      LessonSceneType.summary => 'Summary',
      LessonSceneType.quiz => 'Quiz',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.orangeLight,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusCanvas extends StatelessWidget {
  const _StatusCanvas({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.showLoader = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool showLoader;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    ClassroomTheme.sky.withValues(alpha: 0.35),
                    ClassroomTheme.accent.withValues(alpha: 0.25),
                  ],
                ),
                border: Border.all(color: Colors.white24),
              ),
              child: Icon(icon, size: 40, color: Colors.white),
            ),
            if (showLoader) ...[
              const SizedBox(height: 16),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: ClassroomTheme.accent,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerAtmospherePainter extends CustomPainter {
  const _PlayerAtmospherePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0B1224), Color(0xFF132447), Color(0xFF1A3358)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.orange.withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.85, size.height * 0.2),
          radius: size.width * 0.45,
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
