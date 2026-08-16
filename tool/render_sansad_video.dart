import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/services/ai_video_render/ai_video_render_engine_io.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/render_models.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/sansad_premium_lesson.dart';
import 'package:mpsc_combine_ai/services/elevenlabs_tts_service.dart';

/// Renders the premium ~2-minute संसद MP4 (Canvas + ElevenLabs + FFmpeg).
///
/// Clears TestWidgetsFlutterBinding's mock HttpOverrides so ElevenLabs can
/// reach the network, then injects a real [http.Client].
///
///   flutter test tool/render_sansad_video.dart --dart-define-from-file=dart_defines.json
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('render संसद 2-minute premium MP4', () async {
    final job = buildSansadPremiumVideoJob();
    expect(job.scenes.length, 8);
    expect(job.totalDuration.inSeconds, greaterThanOrEqualTo(100));
    expect(job.totalDuration.inSeconds, lessThanOrEqualTo(135));

    // Undo the test binding mock so package:http uses a real socket client.
    HttpOverrides.global = null;
    final realClient = http.Client();
    addTearDown(realClient.close);

    final eleven = ElevenLabsTtsService(client: realClient);
    final videosDir = Directory('build/ai_rendered_videos');
    final workRoot = Directory('build/ai_video_work_root');
    await videosDir.create(recursive: true);
    await workRoot.create(recursive: true);
    final engine = AiVideoRenderEngine(
      elevenLabs: eleven,
      httpClient: realClient,
      videosDirectory: videosDir,
      workRootDirectory: workRoot,
    );
    final can = await engine.canEncode;
    expect(can, isTrue, reason: 'FFmpeg required at .tools/ffmpeg/ffmpeg.exe');

    AiVideoRenderPhase last = AiVideoRenderPhase.preparing;
    final result = await engine.render(
      job,
      force: true,
      onProgress: (phase, p) {
        // ignore: avoid_print
        print('phase=$phase progress=${p.toStringAsFixed(2)}');
        last = phase;
      },
    );

    expect(last, AiVideoRenderPhase.done);
    expect(File(result.filePath).existsSync(), isTrue);
    expect(await File(result.filePath).length(), greaterThan(50 * 1024));
    // ignore: avoid_print
    print('RENDERED_OK ${result.filePath}');

    final asset = File('assets/rendered_videos/sansad_2min.mp4');
    if (asset.existsSync()) {
      // ignore: avoid_print
      print('ASSET_OK ${asset.path} bytes=${await asset.length()}');
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
