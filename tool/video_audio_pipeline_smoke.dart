import 'dart:convert';
import 'dart:io';

/// Local smoke: ElevenLabs TTS (short script) → FFmpeg slides+audio → ffprobe.
///
/// Usage (repo root, worker optional for /ai/tts; this talks to ElevenLabs via
/// dart_defines.json and local FFmpeg):
///   dart run tool/video_audio_pipeline_smoke.dart
Future<void> main() async {
  final defines = jsonDecode(File('dart_defines.json').readAsStringSync());
  final map = defines is Map ? Map<String, dynamic>.from(defines) : <String, dynamic>{};
  final key = '${map['ELEVENLABS_API_KEY'] ?? ''}'.trim();
  if (key.isEmpty) {
    stderr.writeln('FAIL: ELEVENLABS_API_KEY missing in dart_defines.json');
    exit(1);
  }
  final voice = '${map['ELEVENLABS_VOICE_ID'] ?? 'pNInz6obpgDQGcFmaJgB'}'.trim();
  final model =
      '${map['ELEVENLABS_MODEL_ID'] ?? map['ELEVENLABS_MODEL'] ?? 'eleven_multilingual_v2'}'
          .trim();
  const script =
      'नमस्कार विद्यार्थ्यांनो. आज आपण भारतीय राज्यघटनेतील मूलभूत अधिकारांचा अभ्यास करणार आहोत.';

  stdout.writeln('POST ElevenLabs TTS chars=${script.length} voice=$voice');
  final uri = Uri.parse(
    'https://api.elevenlabs.io/v1/text-to-speech/$voice/with-timestamps',
  );
  final client = HttpClient();
  final req = await client.postUrl(uri);
  req.headers.contentType = ContentType.json;
  req.headers.set('xi-api-key', key);
  req.headers.set('Accept', 'application/json');
  req.add(utf8.encode(jsonEncode({
    'text': script,
    'model_id': model,
  })));
  final res = await req.close().timeout(const Duration(seconds: 120));
  final body = await utf8.decodeStream(res);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    stderr.writeln('FAIL: ElevenLabs HTTP ${res.statusCode} ${body.substring(0, body.length.clamp(0, 200))}');
    exit(1);
  }
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final b64 = '${decoded['audio_base64'] ?? ''}'.trim();
  if (b64.isEmpty) {
    stderr.writeln('FAIL: ElevenLabs returned empty audio');
    exit(1);
  }
  final audioBytes = base64Decode(b64);
  stdout.writeln('TTS bytes=${audioBytes.length}');
  if (audioBytes.length < 800) {
    stderr.writeln('FAIL: audio too short');
    exit(1);
  }

  final ffmpeg = File('.tools/ffmpeg/ffmpeg.exe');
  final ffprobe = File('.tools/ffmpeg/ffprobe.exe');
  if (!ffmpeg.existsSync() || !ffprobe.existsSync()) {
    stderr.writeln('FAIL: local ffmpeg/ffprobe missing');
    exit(1);
  }

  final work = await Directory.systemTemp.createTemp('mpsc_av_smoke_');
  final audioFile = File('${work.path}${Platform.pathSeparator}audio.mp3');
  await audioFile.writeAsBytes(audioBytes, flush: true);

  for (var i = 0; i < 2; i++) {
    final png = File('${work.path}${Platform.pathSeparator}slide_$i.png');
    final slide = await Process.run(ffmpeg.path, [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'color=c=0x0A1F44:s=1280x720:d=0.2',
      '-vf',
      "drawtext=text='MPSC Combine AI ${i + 1}':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2",
      '-frames:v',
      '1',
      png.path,
    ]);
    if (slide.exitCode != 0) {
      stderr.writeln('FAIL: slide render ${slide.stderr}');
      exit(1);
    }
  }

  final list = File('${work.path}${Platform.pathSeparator}list.txt');
  final s0 = File('${work.path}${Platform.pathSeparator}slide_0.png').absolute.path.replaceAll(r'\', '/');
  final s1 = File('${work.path}${Platform.pathSeparator}slide_1.png').absolute.path.replaceAll(r'\', '/');
  await list.writeAsString(
    "file '$s0'\nduration 3\nfile '$s1'\nduration 3\nfile '$s1'\n",
  );
  final out = File('${work.path}${Platform.pathSeparator}lesson.mp4');
  final encode = await Process.run(ffmpeg.path, [
    '-y',
    '-f',
    'concat',
    '-safe',
    '0',
    '-i',
    list.path,
    '-i',
    audioFile.path,
    '-vf',
    'fps=30,format=yuv420p,tpad=stop_mode=clone:stop=-1',
    '-c:v',
    'libx264',
    '-preset',
    'veryfast',
    '-crf',
    '22',
    '-map',
    '0:v:0',
    '-map',
    '1:a:0',
    '-c:a',
    'aac',
    '-b:a',
    '128k',
    '-shortest',
    '-movflags',
    '+faststart',
    out.path,
  ]);
  if (encode.exitCode != 0 || !out.existsSync()) {
    stderr.writeln('FAIL: ffmpeg ${encode.stderr}');
    exit(1);
  }

  final probe = await Process.run(ffprobe.path, [
    '-v',
    'error',
    '-show_entries',
    'stream=codec_type,codec_name',
    '-of',
    'json',
    out.path,
  ]);
  stdout.writeln(probe.stdout);
  final streams = jsonDecode('${probe.stdout}') as Map<String, dynamic>;
  final listStreams = streams['streams'] as List? ?? const [];
  final types = [
    for (final s in listStreams)
      if (s is Map) '${s['codec_type']}',
  ];
  final hasVideo = types.contains('video');
  final hasAudio = types.contains('audio');
  stdout.writeln('MP4 bytes=${out.lengthSync()} video=$hasVideo audio=$hasAudio');
  if (!hasVideo || !hasAudio) {
    stderr.writeln('FAIL: missing tracks');
    exit(1);
  }

  final dest = File('build/web/pipeline_test.mp4');
  await dest.parent.create(recursive: true);
  await out.copy(dest.path);
  stdout.writeln('COPIED ${dest.path}');
  stdout.writeln('PASS script/tts/audio/mux/tracks');
}
