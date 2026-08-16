import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/ai_video_render_engine.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/render_models.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/sansad_premium_lesson.dart';

/// Desktop entry point that renders the real संसद MP4 then exits.
///
///   flutter run -d windows -t lib/tool_render_sansad_main.dart --dart-define-from-file=dart_defines.json
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('Starting संसद premium MP4 render…');
  final job = buildSansadPremiumVideoJob();
  debugPrint('Target duration: ${job.totalDuration.inSeconds}s');

  final engine = AiVideoRenderEngine();
  try {
    final result = await engine.render(
      job,
      force: true,
      onProgress: (phase, p) {
        debugPrint('render $phase ${(p * 100).toStringAsFixed(0)}%');
      },
    );
    debugPrint('RENDERED_OK ${result.filePath}');
    // Copy path marker for the PowerShell wrapper.
    final marker = File('build/sansad_render_path.txt');
    await marker.parent.create(recursive: true);
    await marker.writeAsString(result.filePath);
    exit(0);
  } catch (e, st) {
    debugPrint('RENDERED_FAIL $e');
    debugPrint('$st');
    exit(1);
  }
}
