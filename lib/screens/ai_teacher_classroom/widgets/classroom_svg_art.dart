import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/classroom_theme.dart';

/// Lightweight vector (SVG-style) classroom illustrations — no new package.
/// Used as decorative anchors for maps / diagrams / timelines.
class ClassroomSvgArt {
  const ClassroomSvgArt._();

  static Widget mapPin({double size = 28, Color? color}) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MapPinPainter(color ?? ClassroomTheme.accent),
    );
  }

  static Widget flowchartChevron({double size = 22, Color? color}) {
    return CustomPaint(
      size: Size(size, size * 0.7),
      painter: _ChevronPainter(color ?? ClassroomTheme.accent),
    );
  }

  static Widget timelineDot({double size = 14, Color? color, bool active = false}) {
    return CustomPaint(
      size: Size.square(size),
      painter: _TimelineDotPainter(
        color: color ?? ClassroomTheme.accent,
        active: active,
      ),
    );
  }

  static Widget bookGlyph({double size = 36, Color? color}) {
    return CustomPaint(
      size: Size(size * 0.85, size),
      painter: _BookGlyphPainter(color ?? Colors.white),
    );
  }
}

class _MapPinPainter extends CustomPainter {
  _MapPinPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width * 0.5, size.height)
      ..quadraticBezierTo(size.width * 0.1, size.height * 0.55, size.width * 0.5, size.height * 0.12)
      ..quadraticBezierTo(size.width * 0.9, size.height * 0.55, size.width * 0.5, size.height)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.38),
      size.width * 0.16,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(covariant _MapPinPainter oldDelegate) => oldDelegate.color != color;
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.15, size.height * 0.2)
      ..lineTo(size.width * 0.5, size.height * 0.8)
      ..lineTo(size.width * 0.85, size.height * 0.2);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter oldDelegate) => oldDelegate.color != color;
}

class _TimelineDotPainter extends CustomPainter {
  _TimelineDotPainter({required this.color, required this.active});
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    if (active) {
      canvas.drawCircle(
        c,
        size.width * 0.48,
        Paint()..color = color.withValues(alpha: 0.28),
      );
    }
    canvas.drawCircle(c, size.width * 0.32, Paint()..color = color);
    canvas.drawCircle(
      c,
      size.width * 0.14,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(covariant _TimelineDotPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.active != active;
}

class _BookGlyphPainter extends CustomPainter {
  _BookGlyphPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.12, size.height * 0.15, size.width * 0.76, size.height * 0.7),
      const Radius.circular(3),
    );
    canvas.drawRRect(r, paint);
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.15),
      Offset(size.width * 0.5, size.height * 0.85),
      paint,
    );
    for (var i = 0; i < 3; i++) {
      final y = size.height * (0.35 + i * 0.14);
      canvas.drawLine(
        Offset(size.width * 0.2, y),
        Offset(size.width * 0.42, y),
        paint..strokeWidth = 1.2,
      );
      canvas.drawLine(
        Offset(size.width * 0.58, y),
        Offset(size.width * 0.8, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BookGlyphPainter oldDelegate) => oldDelegate.color != color;
}

/// Soft radial glow behind lesson stage for premium glass look.
class SoftGlowPainter extends CustomPainter {
  SoftGlowPainter({this.t = 0});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = 0.55 + 0.15 * math.sin(t * math.pi * 2);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          ClassroomTheme.sky.withValues(alpha: 0.22 * pulse),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide * 0.55));
    canvas.drawCircle(size.center(Offset.zero), size.shortestSide * 0.55, paint);
  }

  @override
  bool shouldRepaint(covariant SoftGlowPainter oldDelegate) => oldDelegate.t != t;
}
