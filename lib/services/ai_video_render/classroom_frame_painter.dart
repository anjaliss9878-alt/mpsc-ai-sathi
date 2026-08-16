import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subtitle_timing.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/render_models.dart';

/// Paints one classroom video frame onto a [Canvas] (no static slide dump).
///
/// Draws: stage, teacher avatar, digital blackboard, handwriting reveal,
/// keyword highlight, pointer, flowchart / timeline / table / map animations,
/// zoom pulse, and karaoke subtitles.
class ClassroomFramePainter {
  ClassroomFramePainter({
    required this.job,
    required this.scene,
    required this.beat,
    required this.localProgress,
    required this.sceneIndex,
    required this.sceneCount,
  });

  final AiVideoRenderJob job;
  final RenderScene scene;
  final RenderNarrationBeat beat;
  final double localProgress;
  final int sceneIndex;
  final int sceneCount;

  static const _navy = Color(0xFF0A1F44);
  static const _navyMid = Color(0xFF163A6B);
  static const _orange = Color(0xFFFF6B2B);
  static const _board = Color(0xFF0E3D2C);
  static const _chalk = Color(0xFFF4F7F2);
  static const _ice = Color(0xFFE8F1FF);

  Future<ui.Image> renderImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    paint(canvas, Size(job.targetWidth.toDouble(), job.targetHeight.toDouble()));
    final picture = recorder.endRecording();
    return picture.toImage(job.targetWidth, job.targetHeight);
  }

  Future<List<int>> renderPngBytes() async {
    final image = await renderImage();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) {
      throw StateError('Failed to encode classroom frame PNG');
    }
    return byteData.buffer.asUint8List();
  }

  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Stage background gradient.
    final bg = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, h),
        const [_ice, Color(0xFFF7F9FC), Color(0xFFE7EEF8)],
        const [0, 0.55, 1],
      );
    canvas.drawRect(Offset.zero & size, bg);

    // Soft vignette.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w * 0.5, h * 0.42),
          h * 0.75,
          [
            Colors.transparent,
            _navy.withValues(alpha: 0.08),
          ],
        ),
    );

    _paintHeader(canvas, w);
    _paintTeacher(canvas, Rect.fromLTWH(28, 88, w * 0.28, h * 0.55));
    final boardRect = Rect.fromLTWH(w * 0.32, 78, w * 0.64, h * 0.58);
    _paintBoard(canvas, boardRect);
    _paintSubtitle(canvas, Rect.fromLTWH(40, h - 118, w - 80, 88));
    _paintProgress(canvas, Rect.fromLTWH(40, h - 22, w - 80, 6));
  }

  void _paintHeader(Canvas canvas, double w) {
    final tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'MPSC COMBINE AI  ·  ',
            style: TextStyle(
              color: _navy.withValues(alpha: 0.7),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: job.topicName,
            style: const TextStyle(
              color: _navy,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - 80);
    tp.paint(canvas, const Offset(40, 28));

    final sceneLabel = TextPainter(
      text: TextSpan(
        text: 'दृश्य ${sceneIndex + 1}/$sceneCount  ·  ${scene.title}',
        style: TextStyle(
          color: _navyMid.withValues(alpha: 0.85),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - 80);
    sceneLabel.paint(canvas, const Offset(40, 52));
  }

  void _paintTeacher(Canvas canvas, Rect rect) {
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    canvas.drawRRect(
      r,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _navy.withValues(alpha: 0.1),
    );

    final cx = rect.center.dx;
    final cy = rect.top + rect.height * 0.38;
    final pulse = 1 + 0.03 * math.sin(localProgress * math.pi * 2);
    final headR = rect.width * 0.18 * pulse;

    // Glow while speaking.
    canvas.drawCircle(
      Offset(cx, cy),
      headR * 1.55,
      Paint()..color = _orange.withValues(alpha: 0.12 + 0.1 * localProgress),
    );
    canvas.drawCircle(Offset(cx, cy), headR, Paint()..color = const Color(0xFFFFE0C8));
    canvas.drawCircle(
      Offset(cx, cy),
      headR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _navy.withValues(alpha: 0.25),
    );

    // Eyes
    final eyeY = cy - headR * 0.1;
    canvas.drawCircle(Offset(cx - headR * 0.35, eyeY), 4.5, Paint()..color = _navy);
    canvas.drawCircle(Offset(cx + headR * 0.35, eyeY), 4.5, Paint()..color = _navy);

    // Mouth lip-sync
    final mouthOpen = 2.0 + 7.0 * (0.35 + 0.65 * math.sin(localProgress * math.pi * 6).abs());
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, cy + headR * 0.35),
          width: headR * 0.55,
          height: mouthOpen,
        ),
        const Radius.circular(8),
      ),
      Paint()..color = _navy.withValues(alpha: 0.75),
    );

    // Body
    final body = Path()
      ..moveTo(cx - headR * 1.1, cy + headR * 1.2)
      ..quadraticBezierTo(cx, cy + headR * 1.6, cx + headR * 1.1, cy + headR * 1.2)
      ..lineTo(cx + headR * 1.4, rect.bottom - 24)
      ..lineTo(cx - headR * 1.4, rect.bottom - 24)
      ..close();
    canvas.drawPath(body, Paint()..color = _navy);

    final name = TextPainter(
      text: const TextSpan(
        text: 'मराठी AI Faculty\nSmart Teacher',
        style: TextStyle(
          color: _navy,
          fontSize: 15,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width - 16);
    name.paint(
      canvas,
      Offset(rect.center.dx - name.width / 2, rect.bottom - name.height - 14),
    );
  }

  void _paintBoard(Canvas canvas, Rect rect) {
    final zoom = 1.0 +
        (beat.boardProgress > 0.7
            ? 0.02 * math.sin(localProgress * math.pi)
            : 0.0);
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.scale(zoom);
    canvas.translate(-rect.center.dx, -rect.center.dy);

    final board = RRect.fromRectAndRadius(rect, const Radius.circular(22));
    canvas.drawRRect(board, Paint()..color = _board);
    canvas.drawRRect(
      board,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0xFF245C45),
    );

    // Title chalk
    final title = TextPainter(
      text: TextSpan(
        text: scene.title,
        style: const TextStyle(
          color: _chalk,
          fontSize: 28,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width - 48);
    title.paint(canvas, Offset(rect.left + 24, rect.top + 18));

    // Underline handwriting animation
    final underlineW = (rect.width - 48) * (0.25 + 0.75 * beat.boardProgress.clamp(0.0, 1.0));
    canvas.drawLine(
      Offset(rect.left + 24, rect.top + 54),
      Offset(rect.left + 24 + underlineW, rect.top + 54),
      Paint()
        ..color = _orange
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    final content = Rect.fromLTWH(
      rect.left + 20,
      rect.top + 70,
      rect.width - 40,
      rect.height - 100,
    );

    switch (scene.visualType) {
      case SlideVisualType.flowchart:
        _paintFlowchart(canvas, content);
        break;
      case SlideVisualType.timeline:
        _paintTimeline(canvas, content);
        break;
      case SlideVisualType.table:
        _paintTable(canvas, content);
        break;
      case SlideVisualType.map:
        _paintMap(canvas, content);
        break;
      case SlideVisualType.whiteboard:
        _paintHandwriting(canvas, content);
        break;
      default:
        _paintBullets(canvas, content);
        break;
    }

    _paintPointer(canvas, content);
    canvas.restore();
  }

  void _paintBullets(Canvas canvas, Rect content) {
    final items = scene.bullets.isNotEmpty ? scene.bullets : scene.handwriting;
    if (items.isEmpty) {
      _paintHandwriting(canvas, content);
      return;
    }
    final reveal = (items.length * beat.boardProgress).ceil().clamp(1, items.length);
    var y = content.top;
    for (var i = 0; i < reveal; i++) {
      final active = i == reveal - 1;
      final text = items[i];
      final highlighted = _highlightKeywords(text, beat.keywords, active);
      final tp = TextPainter(
        text: highlighted,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: content.width - 28);
      canvas.drawCircle(
        Offset(content.left + 8, y + 12),
        5,
        Paint()..color = active ? _orange : _chalk.withValues(alpha: 0.7),
      );
      tp.paint(canvas, Offset(content.left + 24, y));
      y += tp.height + 14;
      if (y > content.bottom - 20) break;
    }
  }

  void _paintHandwriting(Canvas canvas, Rect content) {
    final lines = scene.handwriting.isNotEmpty
        ? scene.handwriting
        : scene.bullets;
    if (lines.isEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: beat.speakText,
          style: TextStyle(color: _chalk.withValues(alpha: 0.9), fontSize: 20, height: 1.35),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: content.width);
      tp.paint(canvas, content.topLeft);
      return;
    }
    final reveal = (lines.length * beat.boardProgress.clamp(0.05, 1.0))
        .ceil()
        .clamp(1, lines.length);
    var y = content.top;
    for (var i = 0; i < reveal; i++) {
      final frac = i < reveal - 1
          ? 1.0
          : ((beat.boardProgress * lines.length) - i).clamp(0.15, 1.0);
      final full = lines[i];
      final cut = math.max(1, (full.length * frac).round());
      final shown = full.substring(0, cut.clamp(0, full.length));
      final tp = TextPainter(
        text: _highlightKeywords(shown, beat.keywords, i == reveal - 1),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: content.width);
      tp.paint(canvas, Offset(content.left, y));
      y += tp.height + 16;
    }
  }

  void _paintFlowchart(Canvas canvas, Rect content) {
    final nodes = scene.flowchart;
    if (nodes.isEmpty) {
      _paintBullets(canvas, content);
      return;
    }
    final reveal = (nodes.length * beat.boardProgress.clamp(0.1, 1.0))
        .ceil()
        .clamp(1, nodes.length);
    final boxW = content.width * 0.7;
    final boxH = 46.0;
    final gap = (content.height - reveal * boxH) / (reveal + 1);
    for (var i = 0; i < reveal; i++) {
      final y = content.top + gap * (i + 1) + boxH * i;
      final x = content.left + (content.width - boxW) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, boxW, boxH),
        const Radius.circular(12),
      );
      final active = i == reveal - 1;
      canvas.drawRRect(
        rect,
        Paint()..color = active ? _orange.withValues(alpha: 0.9) : const Color(0xFF1F6B4F),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: nodes[i].label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: boxW - 20);
      tp.paint(
        canvas,
        Offset(x + (boxW - tp.width) / 2, y + (boxH - tp.height) / 2),
      );
      if (i < reveal - 1) {
        final from = Offset(x + boxW / 2, y + boxH);
        final to = Offset(x + boxW / 2, y + boxH + gap);
        canvas.drawLine(
          from,
          to,
          Paint()
            ..color = _chalk
            ..strokeWidth = 3,
        );
      }
    }
  }

  void _paintTimeline(Canvas canvas, Rect content) {
    final events = scene.timeline;
    if (events.isEmpty) {
      _paintBullets(canvas, content);
      return;
    }
    final reveal = (events.length * beat.boardProgress.clamp(0.1, 1.0))
        .ceil()
        .clamp(1, events.length);
    final y = content.center.dy;
    canvas.drawLine(
      Offset(content.left, y),
      Offset(content.left + content.width * beat.boardProgress, y),
      Paint()
        ..color = _chalk
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < reveal; i++) {
      final t = events.length == 1 ? 0.5 : i / (events.length - 1);
      final x = content.left + content.width * t * beat.boardProgress.clamp(0.2, 1.0);
      canvas.drawCircle(Offset(x, y), 8, Paint()..color = _orange);
      final tp = TextPainter(
        text: TextSpan(
          text: '${events[i].year}\n${events[i].label}',
          style: const TextStyle(color: _chalk, fontSize: 14, fontWeight: FontWeight.w600, height: 1.2),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 140);
      tp.paint(canvas, Offset(x - tp.width / 2, y + 16));
    }
  }

  void _paintTable(Canvas canvas, Rect content) {
    final headers = scene.tableHeaders;
    final rows = scene.tableRows;
    if (headers.isEmpty && rows.isEmpty) {
      _paintBullets(canvas, content);
      return;
    }
    final cols = headers.isNotEmpty
        ? headers.length
        : (rows.isNotEmpty ? rows.first.length : 1);
    final colW = content.width / cols;
    final revealRows =
        (rows.length * beat.boardProgress.clamp(0.15, 1.0)).ceil().clamp(0, rows.length);

    void cell(String text, Rect r, {bool header = false, bool active = false}) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.deflate(2), const Radius.circular(8)),
        Paint()
          ..color = header
              ? const Color(0xFF1F6B4F)
              : (active ? _orange.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.08)),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: _chalk,
            fontSize: header ? 15 : 14,
            fontWeight: header ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r.width - 10);
      tp.paint(canvas, Offset(r.left + 6, r.top + 8));
    }

    if (headers.isNotEmpty) {
      for (var c = 0; c < cols; c++) {
        cell(
          headers[c],
          Rect.fromLTWH(content.left + colW * c, content.top, colW, 36),
          header: true,
        );
      }
    }
    for (var r = 0; r < revealRows; r++) {
      for (var c = 0; c < cols && c < rows[r].length; c++) {
        cell(
          rows[r][c],
          Rect.fromLTWH(
            content.left + colW * c,
            content.top + 40 + r * 40,
            colW,
            36,
          ),
          active: r == revealRows - 1,
        );
      }
    }
  }

  void _paintMap(Canvas canvas, Rect content) {
    final regions = scene.mapRegions.isNotEmpty
        ? scene.mapRegions
        : scene.bullets;
    canvas.drawRRect(
      RRect.fromRectAndRadius(content.deflate(8), const Radius.circular(18)),
      Paint()..color = const Color(0xFF184E38),
    );
    final reveal = (regions.length * beat.boardProgress.clamp(0.1, 1.0))
        .ceil()
        .clamp(1, math.max(1, regions.length));
    for (var i = 0; i < reveal; i++) {
      final angle = (i / math.max(1, regions.length)) * math.pi * 2;
      final cx = content.center.dx + math.cos(angle) * content.width * 0.22;
      final cy = content.center.dy + math.sin(angle) * content.height * 0.22;
      canvas.drawCircle(
        Offset(cx, cy),
        28,
        Paint()..color = i == reveal - 1 ? _orange : _chalk.withValues(alpha: 0.25),
      );
      if (i < regions.length) {
        final tp = TextPainter(
          text: TextSpan(
            text: regions[i],
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 90);
        tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
      }
    }
  }

  void _paintPointer(Canvas canvas, Rect content) {
    if (beat.pointerLabel.trim().isEmpty && beat.keywords.isEmpty) return;
    final t = localProgress.clamp(0.0, 1.0);
    final x = content.left + content.width * (0.2 + 0.6 * t);
    final y = content.top + content.height * (0.25 + 0.35 * math.sin(t * math.pi));
    final path = Path()
      ..moveTo(x, y)
      ..lineTo(x + 18, y + 28)
      ..lineTo(x + 8, y + 28)
      ..lineTo(x + 8, y + 48)
      ..lineTo(x - 4, y + 48)
      ..lineTo(x - 4, y + 28)
      ..lineTo(x - 14, y + 28)
      ..close();
    canvas.drawPath(path, Paint()..color = _orange);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white70,
    );
  }

  void _paintSubtitle(Canvas canvas, Rect rect) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(16)),
      Paint()..color = _navy.withValues(alpha: 0.88),
    );
    final cues = beat.subtitleCues.isNotEmpty
        ? beat.subtitleCues
        : buildSubtitleTimingFromText(beat.speakText);
    final idx = activeSubtitleIndex(
      progress: localProgress,
      cues: cues,
      fallbackText: beat.speakText,
    );
    final spans = <InlineSpan>[];
    if (cues.isEmpty) {
      spans.add(TextSpan(
        text: beat.speakText,
        style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.3),
      ));
    } else {
      for (var i = 0; i < cues.length; i++) {
        final active = i == idx;
        spans.add(TextSpan(
          text: '${cues[i].text} ',
          style: TextStyle(
            color: active ? _orange : Colors.white,
            fontSize: active ? 20 : 17,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
            height: 1.3,
          ),
        ));
      }
    }
    if (beat.isMcq) {
      spans.insert(
        0,
        const TextSpan(
          text: 'MCQ · ',
          style: TextStyle(color: _orange, fontWeight: FontWeight.w800, fontSize: 17),
        ),
      );
    }
    if (beat.isMcqExplain) {
      spans.insert(
        0,
        const TextSpan(
          text: 'उत्तर · ',
          style: TextStyle(color: Color(0xFF7CFFB2), fontWeight: FontWeight.w800, fontSize: 17),
        ),
      );
    }
    final tp = TextPainter(
      text: TextSpan(children: spans),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: rect.width - 28);
    tp.paint(canvas, Offset(rect.left + 14, rect.top + 14));
  }

  void _paintProgress(Canvas canvas, Rect rect) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = _navy.withValues(alpha: 0.15),
    );
    final sceneWeight = 1 / math.max(1, sceneCount);
    final base = sceneIndex * sceneWeight;
    final local = scene.totalDuration.inMilliseconds == 0
        ? 0.0
        : (beat.duration.inMilliseconds /
                scene.totalDuration.inMilliseconds) *
            localProgress;
    // Approximate overall progress from scene index + local.
    final p = (base + sceneWeight * (0.3 + 0.7 * beat.boardProgress * (0.5 + 0.5 * local)))
        .clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, rect.top, rect.width * p, rect.height),
        const Radius.circular(8),
      ),
      Paint()..color = _orange,
    );
  }

  TextSpan _highlightKeywords(String text, List<String> keywords, bool activeLine) {
    if (keywords.isEmpty) {
      return TextSpan(
        text: text,
        style: TextStyle(
          color: _chalk.withValues(alpha: activeLine ? 1 : 0.85),
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      );
    }
    final children = <InlineSpan>[];
    var remaining = text;
    while (remaining.isNotEmpty) {
      var hitIndex = -1;
      var hitKey = '';
      final lower = remaining.toLowerCase();
      for (final k in keywords) {
        final kk = k.trim();
        if (kk.isEmpty) continue;
        final at = lower.indexOf(kk.toLowerCase());
        if (at >= 0 && (hitIndex < 0 || at < hitIndex)) {
          hitIndex = at;
          hitKey = remaining.substring(at, at + kk.length);
        }
      }
      if (hitIndex < 0) {
        children.add(TextSpan(
          text: remaining,
          style: TextStyle(
            color: _chalk.withValues(alpha: activeLine ? 1 : 0.85),
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ));
        break;
      }
      if (hitIndex > 0) {
        children.add(TextSpan(
          text: remaining.substring(0, hitIndex),
          style: TextStyle(
            color: _chalk.withValues(alpha: activeLine ? 1 : 0.85),
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ));
      }
      children.add(TextSpan(
        text: hitKey,
        style: const TextStyle(
          color: _orange,
          fontSize: 21,
          fontWeight: FontWeight.w800,
          height: 1.35,
          backgroundColor: Color(0x33FF6B2B),
        ),
      ));
      remaining = remaining.substring(hitIndex + hitKey.length);
    }
    return TextSpan(children: children);
  }
}
