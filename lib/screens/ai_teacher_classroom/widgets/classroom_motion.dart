import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Shared entrance / highlight helpers for classroom scene layers.
/// Prefer Transform/Opacity over setState; dispose owned controllers.
class ClassroomReveal extends StatelessWidget {
  const ClassroomReveal({
    super.key,
    required this.visible,
    required this.child,
    this.highlight = false,
    this.slideFrom = const Offset(0.04, 0.06),
    this.duration = const Duration(milliseconds: 380),
    this.delayMs = 0,
  });

  final bool visible;
  final bool highlight;
  final Widget child;
  final Offset slideFrom;
  final Duration duration;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // Key only on visibility so highlight toggles do not remount / flicker.
      key: ValueKey('reveal_${visible}_$delayMs'),
      tween: Tween(begin: 0, end: visible ? 1 : 0),
      duration: duration + Duration(milliseconds: delayMs),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final opacity = visible ? (0.18 + 0.82 * t) : 0.18;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(
              slideFrom.dx * 24 * (1 - t),
              slideFrom.dy * 18 * (1 - t),
            ),
            child: Transform.scale(
              scale: 0.96 + 0.04 * t,
              child: child,
            ),
          ),
        );
      },
      child: highlight ? KeywordGlow(active: true, child: child) : child,
    );
  }
}

/// Soft pulsing glow around narrated keywords / active rows.
class KeywordGlow extends StatefulWidget {
  const KeywordGlow({
    super.key,
    required this.child,
    this.active = false,
    this.color,
  });

  final Widget child;
  final bool active;
  final Color? color;

  @override
  State<KeywordGlow> createState() => _KeywordGlowState();
}

class _KeywordGlowState extends State<KeywordGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant KeywordGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    final color = widget.color ?? AppColors.orangeLight;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final pulse = 0.35 + 0.45 * _c.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: pulse * 0.55),
                blurRadius: 10 + 8 * _c.value,
                spreadRadius: 0.5 + 1.5 * _c.value,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Pulsing map pin / location marker while a region is being spoken.
class MapLocationPulse extends StatefulWidget {
  const MapLocationPulse({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<MapLocationPulse> createState() => _MapLocationPulseState();
}

class _MapLocationPulseState extends State<MapLocationPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant MapLocationPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final s = 1.0 + 0.08 * math.sin(_c.value * math.pi);
        return Transform.scale(scale: s, child: child);
      },
      child: widget.child,
    );
  }
}

/// Draws a connector path progressively (diagram edges).
class PathDrawPainter extends CustomPainter {
  PathDrawPainter({
    required this.progress,
    required this.color,
    this.strokeWidth = 2.2,
  });

  final double progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * 0.5, 0)
      ..lineTo(size.width * 0.5, size.height);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    canvas.drawPath(metric.extractPath(0, metric.length * p), paint);
  }

  @override
  bool shouldRepaint(covariant PathDrawPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
