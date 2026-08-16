import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subtitle_timing.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/render_models.dart';

/// Premium educational slide — white stage, dark-blue headings, saffron
/// highlights, large Marathi fonts. Landscape 720p ready. No avatar/cartoon.
/// Board never dumps full narration text (subtitles carry speech).
class EducationalSlidePainter {
  EducationalSlidePainter({
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
  static const _sky = Color(0xFF2F6FED);
  static const _white = Color(0xFFFFFFFF);
  static const _ice = Color(0xFFF7FAFF);
  static const _saffron = Color(0xFFFF9933);
  static const _accent = _saffron;
  static const _keyword = Color(0xFFC45C12);

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
      throw StateError('Failed to encode educational slide PNG');
    }
    return byteData.buffer.asUint8List();
  }

  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Premium white stage with soft navy wash (not flat grey).
    canvas.drawRect(Offset.zero & size, Paint()..color = _white);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(w, h),
          [
            _ice,
            _white,
            const Color(0xFFFFF8F0),
          ],
          const [0, 0.55, 1],
        ),
    );

    // Top navy brand strip.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, 64),
      Paint()..color = _navy,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 64, w, 5),
      Paint()..color = _saffron,
    );

    _paintBrandBar(canvas, w);
    final cardTop = 88.0;
    final cardBottom = h - 118;
    _paintSlideCard(
      canvas,
      Rect.fromLTWH(36, cardTop, w - 72, cardBottom - cardTop),
    );
    _paintSubtitle(canvas, Rect.fromLTWH(36, h - 108, w - 72, 72));
    _paintProgress(canvas, Rect.fromLTWH(36, h - 24, w - 72, 8));
  }

  void _paintBrandBar(Canvas canvas, double w) {
    final brand = TextPainter(
      text: TextSpan(
        children: [
          const TextSpan(
            text: 'MPSC COMBINE AI',
            style: TextStyle(
              color: _white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          TextSpan(
            text: '  ·  ${job.topicName}',
            style: TextStyle(
              color: _white.withValues(alpha: 0.88),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: w * 0.62);
    brand.paint(canvas, const Offset(36, 18));

    final meta = TextPainter(
      text: TextSpan(
        text: 'स्लाइड ${sceneIndex + 1}/$sceneCount  ·  ${job.subjectName}',
        style: TextStyle(
          color: _white.withValues(alpha: 0.8),
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: w * 0.32);
    meta.paint(canvas, Offset(w - meta.width - 36, 20));
  }

  void _paintSlideCard(Canvas canvas, Rect rect) {
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(18));
    canvas.drawRRect(
      r,
      Paint()
        ..color = _white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
    );
    canvas.drawRRect(r, Paint()..color = _white);
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _navy.withValues(alpha: 0.12),
    );

    // Fade/slide reveal of content (simple, stable).
    final reveal = (beat.boardProgress * (0.55 + 0.45 * localProgress))
        .clamp(0.0, 1.0);
    final slideOffset = (1 - Curves.easeOut.transform(reveal)) * 24;

    canvas.save();
    canvas.clipRRect(r);
    canvas.translate(0, slideOffset);
    canvas.saveLayer(
      rect,
      Paint()..color = Color.fromRGBO(255, 255, 255, reveal),
    );

    final pad = rect.deflate(28);
    _paintTitle(canvas, pad);
    final bodyTop = pad.top + 70;
    final body = Rect.fromLTRB(pad.left, bodyTop, pad.right, pad.bottom - 4);

    if (beat.isMcq || beat.isMcqExplain) {
      _paintMcq(canvas, body, reveal);
    } else {
      switch (scene.visualType) {
        case SlideVisualType.flowchart:
          _paintFlowchart(canvas, body, reveal);
          break;
        case SlideVisualType.timeline:
          _paintTimeline(canvas, body, reveal);
          break;
        case SlideVisualType.table:
          _paintTable(canvas, body, reveal);
          break;
        case SlideVisualType.mindmap:
          _paintMindmap(canvas, body, reveal);
          break;
        case SlideVisualType.map:
        case SlideVisualType.graph:
        case SlideVisualType.icons:
        case SlideVisualType.whiteboard:
        case SlideVisualType.image:
        case SlideVisualType.bullets:
          _paintBullets(canvas, body, reveal);
          break;
      }
    }

    canvas.restore();
    canvas.restore();
  }

  void _paintTitle(Canvas canvas, Rect pad) {
    final tp = TextPainter(
      text: TextSpan(
        text: scene.title,
        style: const TextStyle(
          color: _navy,
          fontSize: 40,
          fontWeight: FontWeight.w800,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: pad.width);
    tp.paint(canvas, Offset(pad.left, pad.top));

    // Saffron accent rule under title.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad.left, pad.top + tp.height + 10, 132, 6),
        const Radius.circular(4),
      ),
      Paint()..color = _saffron,
    );
  }

  void _paintBullets(Canvas canvas, Rect body, double reveal) {
    final bullets = scene.bullets.isNotEmpty
        ? scene.bullets
        : scene.handwriting;
    if (bullets.isEmpty) {
      _paintCenteredNote(canvas, body, beat.speakText);
      return;
    }
    final visible = math.max(1, (bullets.length * reveal).ceil());
    var y = body.top;
    for (var i = 0; i < visible && i < bullets.length; i++) {
      final text = bullets[i];
      final highlighted = _containsKeyword(text);
      final row = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '●  ',
              style: TextStyle(
                color: highlighted ? _saffron : _sky,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: text,
              style: TextStyle(
                color: highlighted ? _keyword : _navy,
                fontSize: 30,
                fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: body.width - 8);
      if (y + row.height > body.bottom) break;
      row.paint(canvas, Offset(body.left, y));
      y += row.height + 18;
    }
  }

  void _paintFlowchart(Canvas canvas, Rect body, double reveal) {
    final nodes = scene.flowchart;
    if (nodes.isEmpty) {
      _paintBullets(canvas, body, reveal);
      return;
    }
    final visible = math.max(1, (nodes.length * reveal).ceil());
    final boxH = math.min(92.0, (body.height - 24) / visible - 16);
    var y = body.top;
    for (var i = 0; i < visible; i++) {
      final label = nodes[i].label;
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(body.left + 40, y, body.width - 80, boxH),
        const Radius.circular(16),
      );
      canvas.drawRRect(box, Paint()..color = _ice);
      canvas.drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = _sky,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: _navy,
            fontSize: 30,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
        textAlign: TextAlign.center,
      )..layout(maxWidth: body.width - 120);
      tp.paint(
        canvas,
        Offset(
          body.left + 40 + (body.width - 80 - tp.width) / 2,
          y + (boxH - tp.height) / 2,
        ),
      );
      y += boxH + 8;
      if (i < visible - 1) {
        final cx = body.center.dx;
        canvas.drawLine(
          Offset(cx, y),
          Offset(cx, y + 12),
          Paint()
            ..color = _sky
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
        // Simple arrow head.
        final path = Path()
          ..moveTo(cx - 8, y + 8)
          ..lineTo(cx, y + 16)
          ..lineTo(cx + 8, y + 8);
        canvas.drawPath(path, Paint()..color = _sky);
        y += 20;
      }
    }
  }

  void _paintTimeline(Canvas canvas, Rect body, double reveal) {
    final events = scene.timeline;
    if (events.isEmpty) {
      _paintBullets(canvas, body, reveal);
      return;
    }
    final visible = math.max(1, (events.length * reveal).ceil());
    final lineX = body.left + 28;
    canvas.drawLine(
      Offset(lineX, body.top + 8),
      Offset(lineX, body.bottom - 8),
      Paint()
        ..color = _sky.withValues(alpha: 0.45)
        ..strokeWidth = 4,
    );
    var y = body.top;
    final slot = (body.height - 16) / visible;
    for (var i = 0; i < visible; i++) {
      final e = events[i];
      canvas.drawCircle(Offset(lineX, y + 18), 10, Paint()..color = _accent);
      final tp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '${e.year}  ',
              style: const TextStyle(
                color: _sky,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: e.label,
              style: const TextStyle(
                color: _navy,
                fontSize: 28,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: body.width - 60);
      tp.paint(canvas, Offset(lineX + 28, y));
      y += slot;
    }
  }

  void _paintTable(Canvas canvas, Rect body, double reveal) {
    final headers = scene.tableHeaders;
    final rows = scene.tableRows;
    if (headers.isEmpty && rows.isEmpty) {
      _paintBullets(canvas, body, reveal);
      return;
    }
    final cols = headers.isNotEmpty
        ? headers.length
        : (rows.isNotEmpty ? rows.first.length : 1);
    final colW = body.width / cols;
    final visibleRows = math.max(0, (rows.length * reveal).ceil());

    // Header
    if (headers.isNotEmpty) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(body.left, body.top, body.width, 56),
          const Radius.circular(12),
        ),
        Paint()..color = _navy,
      );
      for (var c = 0; c < cols && c < headers.length; c++) {
        final tp = TextPainter(
          text: TextSpan(
            text: headers[c],
            style: const TextStyle(
              color: _white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: colW - 16);
        tp.paint(canvas, Offset(body.left + c * colW + 8, body.top + 14));
      }
    }

    var y = body.top + (headers.isEmpty ? 0 : 64);
    for (var r = 0; r < visibleRows && r < rows.length; r++) {
      final bg = r.isEven ? _ice : _white;
      canvas.drawRect(
        Rect.fromLTWH(body.left, y, body.width, 52),
        Paint()..color = bg,
      );
      final row = rows[r];
      for (var c = 0; c < cols && c < row.length; c++) {
        final tp = TextPainter(
          text: TextSpan(
            text: row[c],
            style: const TextStyle(
              color: _navy,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: colW - 16);
        tp.paint(canvas, Offset(body.left + c * colW + 8, y + 12));
      }
      y += 52;
      if (y > body.bottom - 40) break;
    }
  }

  void _paintMindmap(Canvas canvas, Rect body, double reveal) {
    final center = scene.title;
    final branches = scene.bullets;
    final cx = body.center.dx;
    final cy = body.top + 70;
    canvas.drawCircle(Offset(cx, cy), 70, Paint()..color = _navy);
    final centerTp = TextPainter(
      text: TextSpan(
        text: center,
        style: const TextStyle(
          color: _white,
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: 120);
    centerTp.paint(
      canvas,
      Offset(cx - centerTp.width / 2, cy - centerTp.height / 2),
    );

    final visible = math.max(1, (branches.length * reveal).ceil());
    for (var i = 0; i < visible && i < branches.length; i++) {
      final angle = -math.pi / 2 + (i + 1) * (math.pi / (visible + 1));
      final tx = cx + math.cos(angle) * 210;
      final ty = cy + 160 + math.sin(angle) * 40 + i * 70;
      canvas.drawLine(
        Offset(cx, cy + 70),
        Offset(tx, ty),
        Paint()
          ..color = _sky.withValues(alpha: 0.7)
          ..strokeWidth = 3,
      );
      final chip = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(tx, ty), width: 220, height: 56),
        const Radius.circular(14),
      );
      canvas.drawRRect(chip, Paint()..color = _ice);
      canvas.drawRRect(
        chip,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _sky
          ..strokeWidth = 2,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: branches[i],
          style: const TextStyle(
            color: _navy,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 200);
      tp.paint(canvas, Offset(tx - tp.width / 2, ty - tp.height / 2));
    }
  }

  void _paintMcq(Canvas canvas, Rect body, double reveal) {
    final mcq = scene.mcq;
    if (mcq == null) {
      _paintBullets(canvas, body, reveal);
      return;
    }
    final q = TextPainter(
      text: TextSpan(
        text: mcq.question,
        style: const TextStyle(
          color: _navy,
          fontSize: 32,
          fontWeight: FontWeight.w800,
          height: 1.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: body.width);
    q.paint(canvas, Offset(body.left, body.top));

    var y = body.top + q.height + 28;
    for (var i = 0; i < mcq.options.length; i++) {
      final correct = beat.isMcqExplain && i == mcq.correctIndex;
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(body.left, y, body.width, 64),
        const Radius.circular(14),
      );
      canvas.drawRRect(
        box,
        Paint()..color = correct ? const Color(0xFFE8FFF1) : _ice,
      );
      canvas.drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = correct ? const Color(0xFF1B9E5A) : _sky.withValues(alpha: 0.4),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1})  ${mcq.options[i]}',
          style: TextStyle(
            color: correct ? const Color(0xFF146C3D) : _navy,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: body.width - 24);
      tp.paint(canvas, Offset(body.left + 16, y + 16));
      y += 76;
      if (y > body.bottom - 40) break;
    }
  }

  void _paintCenteredNote(Canvas canvas, Rect body, String text) {
    // Never dump full narration on the board — keywords / short cue only.
    final keywords = beat.keywords.where((k) => k.trim().isNotEmpty).toList();
    final cue = keywords.isNotEmpty
        ? keywords.take(4).join('  ·  ')
        : (beat.pointerLabel.trim().isNotEmpty
            ? beat.pointerLabel.trim()
            : scene.title);
    final tp = TextPainter(
      text: TextSpan(
        text: cue,
        style: const TextStyle(
          color: _navy,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: body.width);
    tp.paint(
      canvas,
      Offset(
        body.left + (body.width - tp.width) / 2,
        body.top + 36,
      ),
    );
  }

  void _paintSubtitle(Canvas canvas, Rect rect) {
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    canvas.drawRRect(r, Paint()..color = _navy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, rect.top, 8, rect.height),
        const Radius.circular(14),
      ),
      Paint()..color = _saffron,
    );

    final cues = beat.subtitleCues.isNotEmpty
        ? beat.subtitleCues
        : buildSubtitleTimingFromText(beat.speakText);
    final active = activeSubtitleIndex(
      progress: localProgress,
      cues: cues,
      fallbackText: beat.speakText,
    );

    // Subtitles are timed speech captions — not board narration dump.
    String caption;
    if (cues.isEmpty) {
      caption = _shortCaption(beat.speakText);
    } else {
      caption = cues[active.clamp(0, cues.length - 1)].text;
    }

    final tp = TextPainter(
      text: TextSpan(
        text: caption,
        style: const TextStyle(
          color: _white,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: rect.width - 40);
    tp.paint(
      canvas,
      Offset(
        rect.left + (rect.width - tp.width) / 2,
        rect.top + (rect.height - tp.height) / 2,
      ),
    );
  }

  String _shortCaption(String text) {
    final t = text.trim();
    if (t.length <= 110) return t;
    final cut = t.substring(0, 110);
    final danda = cut.lastIndexOf('।');
    final dot = cut.lastIndexOf('.');
    final at = math.max(danda, dot);
    if (at > 40) return cut.substring(0, at + 1);
    return '$cut…';
  }

  void _paintProgress(Canvas canvas, Rect rect) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = _navy.withValues(alpha: 0.12),
    );
    final frac = sceneCount <= 0
        ? 0.0
        : ((sceneIndex + beat.boardProgress.clamp(0.0, 1.0)) / sceneCount)
            .clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, rect.top, rect.width * frac, rect.height),
        const Radius.circular(6),
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.topRight,
          const [_accent, _sky],
        ),
    );
  }

  bool _containsKeyword(String text) {
    for (final k in beat.keywords) {
      if (k.trim().isEmpty) continue;
      if (text.contains(k)) return true;
    }
    return false;
  }
}
