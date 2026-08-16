import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Visual state of the AI Teacher avatar, reflecting the real AI Teacher
/// pipeline: [listening] while the student is asking a question,
/// [thinking] while Gemini is generating the lesson, [speaking] while the
/// generated script is being narrated (Text-to-Speech) with lip-sync/hand
/// gestures animating, and [idle] otherwise.
enum TeacherAvatarState { idle, thinking, speaking, listening }

/// Layered 2D AI Teacher avatar — blink, idle head motion, lip-sync,
/// teaching hand gestures, and a content pointer. Driven by Flutter
/// AnimationControllers (no per-frame setState). Ready to swap for a
/// rendered avatar later without touching surrounding layout.
class ClassroomAvatar extends StatefulWidget {
  const ClassroomAvatar({
    super.key,
    required this.state,
    this.size = 260,
    this.isSpeaking = false,
    this.speechProgress = 0,
    this.pointerLabel,
    this.lookTowardContent = true,
  });

  final TeacherAvatarState state;
  final double size;

  /// Explicit speaking flag (audio playing). Falls back to [state] == speaking.
  final bool isSpeaking;

  /// 0–1 karaoke / narration progress — modulates lip-sync intensity.
  final double speechProgress;

  /// Active board keyword / pointer target label (shown near the pointer).
  final String? pointerLabel;

  /// When true, head subtly looks toward the content stage (right).
  final bool lookTowardContent;

  @override
  State<ClassroomAvatar> createState() => _ClassroomAvatarState();
}

class _ClassroomAvatarState extends State<ClassroomAvatar>
    with TickerProviderStateMixin {
  /// Slow idle / breathe / head sway (always on when ticker enabled).
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  /// Blink cycle — short close then open.
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  /// Lip sync while narrating.
  late final AnimationController _lips = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  /// Periodic teaching hand gestures.
  late final AnimationController _gesture = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// Pointer bob / aim toward content.
  late final AnimationController _pointer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  Duration _nextBlinkIn = const Duration(milliseconds: 2800);
  Duration _blinkAccum = Duration.zero;
  Duration? _lastTick;

  bool get _speaking =>
      widget.isSpeaking || widget.state == TeacherAvatarState.speaking;

  @override
  void initState() {
    super.initState();
    _idle.repeat();
    _syncSpeechControllers();
    _idle.addListener(_onIdleTick);
  }

  @override
  void didUpdateWidget(covariant ClassroomAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        oldWidget.isSpeaking != widget.isSpeaking) {
      _syncSpeechControllers();
    }
  }

  void _syncSpeechControllers() {
    if (_speaking) {
      if (!_lips.isAnimating) _lips.repeat(reverse: true);
      if (!_gesture.isAnimating) _gesture.repeat(reverse: true);
      if (!_pointer.isAnimating) _pointer.repeat(reverse: true);
    } else {
      _lips
        ..stop()
        ..value = 0;
      _gesture
        ..stop()
        ..value = 0.15;
      if (widget.pointerLabel != null && widget.pointerLabel!.trim().isNotEmpty) {
        if (!_pointer.isAnimating) _pointer.repeat(reverse: true);
      } else {
        _pointer
          ..stop()
          ..value = 0;
      }
    }
  }

  void _onIdleTick() {
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    if (_lastTick != null) {
      _blinkAccum += now - _lastTick!;
      if (_blinkAccum >= _nextBlinkIn && !_blink.isAnimating) {
        _blinkAccum = Duration.zero;
        _nextBlinkIn = Duration(milliseconds: 2200 + math.Random().nextInt(2400));
        _blink.forward(from: 0).then((_) {
          if (mounted) _blink.reverse();
        });
      }
    }
    _lastTick = now;
  }

  @override
  void dispose() {
    _idle.removeListener(_onIdleTick);
    _idle.dispose();
    _blink.dispose();
    _lips.dispose();
    _gesture.dispose();
    _pointer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Controllers auto-pause when an ancestor disables TickerMode.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_idle, _blink, _lips, _gesture, _pointer]),
        builder: (context, _) {
          final t = _idle.value;
          return SizedBox(
            width: widget.size,
            height: widget.size * 1.15,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                ..._buildRings(t),
                _buildFigure(t),
                if (widget.state == TeacherAvatarState.listening) _buildMicBadge(t),
                if (widget.state == TeacherAvatarState.thinking) _buildThinkingBadge(t),
                if (_showPointer) _buildPointerOverlay(),
              ],
            ),
          );
        },
      ),
    );
  }

  bool get _showPointer {
    final label = widget.pointerLabel?.trim() ?? '';
    return _speaking || label.isNotEmpty;
  }

  List<Widget> _buildRings(double t) {
    switch (widget.state) {
      case TeacherAvatarState.listening:
        return [
          _pulseRing(progress: t, color: AppColors.orange),
          _pulseRing(progress: (t + 0.5) % 1.0, color: AppColors.orange),
        ];
      case TeacherAvatarState.speaking:
        return [_pulseRing(progress: t, color: AppColors.navyLight, maxScale: 1.14)];
      case TeacherAvatarState.thinking:
        return [_pulseRing(progress: t, color: AppColors.textSecondary, maxScale: 1.08)];
      case TeacherAvatarState.idle:
        return [];
    }
  }

  Widget _pulseRing({
    required double progress,
    required Color color,
    double maxScale = 1.3,
  }) {
    final scale = 1.0 + (maxScale - 1.0) * progress;
    final opacity = (1.0 - progress).clamp(0.0, 1.0);
    return Transform.scale(
      scale: scale,
      child: Container(
        width: widget.size * 0.82,
        height: widget.size * 0.82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: opacity * 0.55), width: 2.5),
        ),
      ),
    );
  }

  Widget _buildFigure(double t) {
    final breathe = 1.0 + 0.018 * math.sin(t * 2 * math.pi);
    final headYaw = widget.lookTowardContent
        ? 0.06 + 0.04 * math.sin(t * 2 * math.pi)
        : 0.02 * math.sin(t * 2 * math.pi);
    final headPitch = 0.03 * math.sin(t * 2 * math.pi + 0.8);
    final lookNudge = widget.lookTowardContent ? widget.size * 0.012 : 0.0;

    return Transform.scale(
      scale: breathe,
      child: SizedBox(
        width: widget.size,
        height: widget.size * 1.05,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              bottom: 0,
              child: Container(
                width: widget.size * 0.72,
                height: widget.size * 0.46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.navyLight, AppColors.navy],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(widget.size * 0.36),
                    topRight: Radius.circular(widget.size * 0.36),
                  ),
                ),
              ),
            ),
            _buildHand(isLeft: true),
            _buildHand(isLeft: false),
            Positioned(
              bottom: widget.size * 0.36,
              child: Transform.translate(
                offset: Offset(lookNudge, headPitch * widget.size * 0.08),
                child: Transform.rotate(
                  angle: headYaw * 0.35 + headPitch * 0.2,
                  child: _buildHead(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHead() {
    final eyeClose = Curves.easeInOut.transform(_blink.value);
    final eyeH = (widget.size * 0.028) * (1.0 - eyeClose * 0.92) + 1.2;

    return Container(
      width: widget.size * 0.5,
      height: widget.size * 0.5,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [AppColors.navyLight, AppColors.navy, AppColors.navyDark],
          stops: [0.0, 0.65, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.35),
            blurRadius: 26,
            spreadRadius: 3,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.school_rounded,
            size: widget.size * 0.18,
            color: Colors.white.withValues(alpha: 0.28),
          ),
          // Eyes
          Positioned(
            top: widget.size * 0.16,
            left: widget.size * 0.12,
            child: _eye(eyeH),
          ),
          Positioned(
            top: widget.size * 0.16,
            right: widget.size * 0.12,
            child: _eye(eyeH),
          ),
          // Mouth / lip-sync
          Positioned(
            bottom: widget.size * 0.1,
            child: _buildMouth(),
          ),
        ],
      ),
    );
  }

  Widget _eye(double height) {
    return Container(
      width: widget.size * 0.055,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(widget.size * 0.03),
      ),
    );
  }

  Widget _buildMouth() {
    final progressBoost = 0.55 + 0.45 * widget.speechProgress.clamp(0.0, 1.0);
    final lipWave = _speaking
        ? (0.25 + 0.75 * ((math.sin(_lips.value * math.pi * 2) + 1) / 2)) * progressBoost
        : 0.08;
    return Container(
      width: widget.size * 0.12,
      height: (widget.size * 0.05) * lipWave + 2,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(widget.size * 0.03),
      ),
    );
  }

  Widget _buildHand({required bool isLeft}) {
    // Teaching gestures: left explains (lift), right points toward content.
    final g = _speaking ? _gesture.value : 0.12;
    final phase = isLeft ? g : (1 - g);
    final lift = _speaking ? (0.35 + 0.65 * phase) : 0.08;
    final dy = -widget.size * 0.14 * lift;
    final angle = (isLeft ? -1 : 1) * (0.12 + 0.32 * lift);
    final outward = _speaking && !isLeft ? widget.size * 0.03 * phase : 0.0;

    return Positioned(
      bottom: widget.size * 0.16,
      left: isLeft ? widget.size * 0.02 : null,
      right: isLeft ? null : widget.size * 0.02,
      child: Transform.translate(
        offset: Offset(isLeft ? -outward : outward, dy),
        child: Transform.rotate(
          angle: angle,
          child: Container(
            width: widget.size * 0.13,
            height: widget.size * 0.13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.navyLight,
              border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
              boxShadow: _speaking
                  ? [
                      BoxShadow(
                        color: AppColors.orangeLight.withValues(alpha: 0.25 * lift),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            child: !isLeft && _speaking
                ? Icon(
                    Icons.front_hand_rounded,
                    size: widget.size * 0.07,
                    color: Colors.white.withValues(alpha: 0.55),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildPointerOverlay() {
    final bob = 4.0 * math.sin(_pointer.value * math.pi * 2);
    final label = widget.pointerLabel?.trim();
    return Positioned(
      right: -widget.size * 0.02,
      top: widget.size * 0.22 + bob,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.rotate(
            angle: -0.55,
            child: Icon(
              Icons.near_me_rounded,
              color: AppColors.orangeLight,
              size: widget.size * 0.14,
              shadows: [
                Shadow(
                  color: AppColors.orangeLight.withValues(alpha: 0.55),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
          if (label != null && label.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              constraints: BoxConstraints(maxWidth: widget.size * 0.55),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.orangeLight.withValues(alpha: 0.5)),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.size * 0.045,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMicBadge(double t) {
    final scale = 1.0 + 0.12 * ((math.sin(t * 2 * math.pi) + 1) / 2);
    return Positioned(
      right: widget.size * 0.02,
      bottom: widget.size * 0.28,
      child: Transform.scale(
        scale: scale,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.orange,
            boxShadow: [
              BoxShadow(color: AppColors.orange.withValues(alpha: 0.5), blurRadius: 12),
            ],
          ),
          child: const Icon(Icons.mic_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildThinkingBadge(double t) {
    return Positioned(
      right: widget.size * 0.02,
      bottom: widget.size * 0.28,
      child: Transform.rotate(
        angle: t * 2 * math.pi,
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.textSecondary,
            boxShadow: [
              BoxShadow(color: AppColors.textSecondary.withValues(alpha: 0.5), blurRadius: 12),
            ],
          ),
          child: const Icon(Icons.autorenew_rounded, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

/// Small text + dot indicator shown under the avatar reflecting its
/// current state — keeps the state legible even for a static screenshot.
class ClassroomAvatarStatusLabel extends StatelessWidget {
  const ClassroomAvatarStatusLabel({super.key, required this.state});

  final TeacherAvatarState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      TeacherAvatarState.idle => ('AI Teacher is ready', AppColors.textSecondary),
      TeacherAvatarState.thinking => ('Preparing your lesson…', AppColors.textSecondary),
      TeacherAvatarState.speaking => ('AI Teacher is speaking…', AppColors.navy),
      TeacherAvatarState.listening => ('Listening to you…', AppColors.orange),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}
