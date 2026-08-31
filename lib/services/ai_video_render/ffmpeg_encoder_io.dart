import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Shells out to a local FFmpeg binary to mux PNG frames + audio → MP4/WebM.
class FfmpegVideoEncoder {
  FfmpegVideoEncoder({this.ffmpegPath});

  final String? ffmpegPath;

  Future<String?> _resolveFfmpeg() async {
    final configured = ffmpegPath;
    if (configured != null && await File(configured).exists()) {
      return configured;
    }
    final candidates = <String>[
      p.join(Directory.current.path, '.tools', 'ffmpeg', 'ffmpeg.exe'),
      p.join(Directory.current.path, '.tools', 'ffmpeg', 'ffmpeg'),
      'ffmpeg',
      'ffmpeg.exe',
    ];
    for (final c in candidates) {
      if (c == 'ffmpeg' || c == 'ffmpeg.exe') {
        try {
          final r = await Process.run(c, ['-version']);
          if (r.exitCode == 0) return c;
        } catch (_) {}
        continue;
      }
      if (await File(c).exists()) return c;
    }
    return null;
  }

  Future<bool> get isAvailable async => (await _resolveFfmpeg()) != null;

  Future<String> encode({
    required String workDir,
    required List<String> framePaths,
    required String audioPath,
    required String outputPath,
    required int fps,
    void Function(double progress)? onProgress,
  }) async {
    final ffmpeg = await _resolveFfmpeg();
    if (ffmpeg == null) {
      throw StateError(
        'FFmpeg not found. Place ffmpeg at .tools/ffmpeg/ffmpeg.exe',
      );
    }
    if (framePaths.isEmpty) {
      throw ArgumentError('No frames to encode');
    }

    final dir = Directory(workDir);
    if (!await dir.exists()) await dir.create(recursive: true);

    // Copy/link frames into contiguous frame_%05d.png sequence.
    final seqDir = Directory(p.join(workDir, 'seq'));
    if (await seqDir.exists()) {
      await seqDir.delete(recursive: true);
    }
    await seqDir.create(recursive: true);

    for (var i = 0; i < framePaths.length; i++) {
      final dest = p.join(seqDir.path, 'frame_${(i + 1).toString().padLeft(5, '0')}.png');
      await File(framePaths[i]).copy(dest);
      if (i % 12 == 0) onProgress?.call(i / framePaths.length * 0.35);
    }

    final out = File(outputPath);
    if (await out.exists()) await out.delete();
    await out.parent.create(recursive: true);

    String ffmpegPathArg(String path) =>
        File(path).absolute.path.replaceAll(r'\', '/');

    final framesPattern = ffmpegPathArg(p.join(seqDir.path, 'frame_%05d.png'));
    final audioAbs = audioPath.isNotEmpty && await File(audioPath).exists()
        ? ffmpegPathArg(audioPath)
        : '';
    final outAbs = ffmpegPathArg(outputPath);

    final isWebm = outputPath.toLowerCase().endsWith('.webm');
    final args = <String>[
      '-y',
      '-framerate',
      '$fps',
      '-i',
      framesPattern,
      if (audioAbs.isNotEmpty) ...[
        '-i',
        audioAbs,
        '-vf',
        'tpad=stop_mode=clone:stop=-1',
      ],
      '-r',
      '$fps',
      if (isWebm) ...[
        '-c:v',
        'libvpx-vp9',
        '-b:v',
        '1.2M',
        '-pix_fmt',
        'yuv420p',
        if (audioAbs.isNotEmpty) ...[
          '-map',
          '0:v:0',
          '-map',
          '1:a:0',
          '-c:a',
          'libopus',
          '-b:a',
          '96k',
          '-shortest',
        ],
      ] else ...[
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        '-preset',
        'veryfast',
        '-crf',
        '23',
        if (audioAbs.isNotEmpty) ...[
          '-map',
          '0:v:0',
          '-map',
          '1:a:0',
          '-c:a',
          'aac',
          '-b:a',
          '128k',
          '-shortest',
        ],
      ],
      '-movflags',
      '+faststart',
      outAbs,
    ];

    onProgress?.call(0.4);
    debugPrint('FFmpeg: $ffmpeg ${args.join(' ')}');
    final proc = await Process.start(ffmpeg, args, workingDirectory: workDir);
    final stderrBuf = StringBuffer();
    proc.stderr.transform(SystemEncoding().decoder).listen((s) {
      stderrBuf.write(s);
      // Rough progress from frame= lines when present.
      final m = RegExp(r'frame=\s*(\d+)').firstMatch(s);
      if (m != null) {
        final f = int.tryParse(m.group(1) ?? '') ?? 0;
        final pFrac = (0.4 + 0.55 * (f / framePaths.length)).clamp(0.4, 0.95);
        onProgress?.call(pFrac);
      }
    });
    final code = await proc.exitCode;
    if (code != 0 || !await out.exists()) {
      throw StateError(
        'FFmpeg encode failed (code $code):\n${stderrBuf.toString().substring(0, stderrBuf.length.clamp(0, 1200))}',
      );
    }
    onProgress?.call(1);
    return outputPath;
  }

  /// Low-RAM encode: one PNG per timed hold → concat demuxer → 30 FPS MP4.
  ///
  /// Avoids writing thousands of duplicate frames to disk (critical on 4GB devices).
  Future<String> encodeTimedSlides({
    required String workDir,
    required List<({String path, double seconds})> slides,
    required String audioPath,
    required String outputPath,
    required int fps,
    void Function(double progress)? onProgress,
  }) async {
    final ffmpeg = await _resolveFfmpeg();
    if (ffmpeg == null) {
      throw StateError(
        'FFmpeg not found. Place ffmpeg at .tools/ffmpeg/ffmpeg.exe',
      );
    }
    if (slides.isEmpty) {
      throw ArgumentError('No timed slides to encode');
    }

    final listPath = p.join(workDir, 'slides_concat.txt');
    final sink = File(listPath).openWrite(mode: FileMode.writeOnly);
    for (var i = 0; i < slides.length; i++) {
      final s = slides[i];
      final abs = File(s.path).absolute.path.replaceAll(r'\', '/');
      final escaped = abs.replaceAll("'", r"'\''");
      sink.writeln("file '$escaped'");
      sink.writeln('duration ${s.seconds.toStringAsFixed(3)}');
      if (i % 4 == 0) onProgress?.call(i / slides.length * 0.25);
    }
    // Concat demuxer needs the last file repeated without duration.
    final last = File(slides.last.path).absolute.path.replaceAll(r'\', '/');
    final lastEscaped = last.replaceAll("'", r"'\''");
    sink.writeln("file '$lastEscaped'");
    await sink.close();

    final out = File(outputPath);
    if (await out.exists()) await out.delete();
    await out.parent.create(recursive: true);

    String ffmpegPathArg(String path) =>
        File(path).absolute.path.replaceAll(r'\', '/');

    final audioAbs = audioPath.isNotEmpty && await File(audioPath).exists()
        ? ffmpegPathArg(audioPath)
        : '';
    final outAbs = ffmpegPathArg(outputPath);
    final listAbs = ffmpegPathArg(listPath);

    if (audioAbs.isEmpty) {
      throw StateError('Generated audio missing for FFmpeg mux');
    }

    final args = <String>[
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      listAbs,
      if (audioAbs.isNotEmpty) ...['-i', audioAbs],
      '-vf',
      audioAbs.isNotEmpty
          ? 'fps=$fps,format=yuv420p,tpad=stop_mode=clone:stop=-1'
          : 'fps=$fps,format=yuv420p',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '22',
      if (audioAbs.isNotEmpty) ...[
        '-map',
        '0:v:0',
        '-map',
        '1:a:0',
        '-c:a',
        'aac',
        '-b:a',
        '128k',
        '-shortest',
      ],
      '-movflags',
      '+faststart',
      outAbs,
    ];

    onProgress?.call(0.35);
    debugPrint('FFmpeg timed slides: $ffmpeg ${args.join(' ')}');
    final proc = await Process.start(ffmpeg, args, workingDirectory: workDir);
    final stderrBuf = StringBuffer();
    proc.stderr.transform(SystemEncoding().decoder).listen(stderrBuf.write);
    final code = await proc.exitCode;
    if (code != 0 || !await out.exists() || await out.length() < 8000) {
      final err = stderrBuf.toString();
      throw StateError(
        'FFmpeg timed encode failed (code $code):\n'
        '${err.substring(0, err.length.clamp(0, 1200))}',
      );
    }
    onProgress?.call(1);
    return outputPath;
  }

  Future<String> encodeFromPngBytes({
    required String workDir,
    required List<Uint8List> frames,
    required Uint8List audioBytes,
    required String outputPath,
    required int fps,
    void Function(double progress)? onProgress,
  }) async {
    final dir = Directory(p.join(workDir, 'raw_frames'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final paths = <String>[];
    for (var i = 0; i < frames.length; i++) {
      final path = p.join(dir.path, 'f_${i.toString().padLeft(5, '0')}.png');
      await File(path).writeAsBytes(frames[i], flush: true);
      paths.add(path);
      if (i % 8 == 0) onProgress?.call(i / frames.length * 0.3);
    }
    final audioPath = p.join(workDir, 'narration.mp3');
    if (audioBytes.isNotEmpty) {
      await File(audioPath).writeAsBytes(audioBytes, flush: true);
    }
    return encode(
      workDir: workDir,
      framePaths: paths,
      audioPath: audioBytes.isEmpty ? '' : audioPath,
      outputPath: outputPath,
      fps: fps,
      onProgress: onProgress,
    );
  }
}
