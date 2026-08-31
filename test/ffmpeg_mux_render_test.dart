import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/classroom_video/classroom_lecture.dart';
import 'package:path/path.dart' as p;

void main() {
  test('FFmpeg muxes generated audio into a real MP4 with both tracks', () async {
    final bundled = File(p.join('.tools', 'ffmpeg', 'ffmpeg.exe'));
    final ffmpeg = bundled.existsSync() ? bundled.path : 'ffmpeg';
    final probeBin = File(p.join('.tools', 'ffmpeg', 'ffprobe.exe'));
    final ffprobe = probeBin.existsSync() ? probeBin.path : 'ffprobe';
    try {
      final ver = await Process.run(ffmpeg, ['-version']);
      if (ver.exitCode != 0) {
        markTestSkipped('FFmpeg is not available');
        return;
      }
    } catch (_) {
      markTestSkipped('FFmpeg is not available');
      return;
    }

    const lecture = ClassroomLecture(
      title: 'मूलभूत अधिकार',
      narration: 'नमस्कार विद्यार्थ्यांनो.',
      slides: [
        ClassroomSlide(
          heading: 'परिचय',
          points: ['राज्यघटनेचा गाभा'],
          spoken: 'पहिली ओळ',
          durationSeconds: 1.2,
        ),
        ClassroomSlide(
          heading: 'महत्त्व',
          points: ['नागरिकांचे रक्षण'],
          spoken: 'दुसरी ओळ',
          durationSeconds: 1.2,
        ),
      ],
    );
    final holds = lecture.slideDurations(const Duration(milliseconds: 2400));
    expect(holds.fold<int>(0, (a, b) => a + b.inMilliseconds), 2400);

    final work = await Directory.systemTemp.createTemp('mpsc_mux_verify_');
    addTearDown(() async {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    });

    final audio = File(p.join(work.path, 'narration.wav'));
    final sine = await Process.run(ffmpeg, [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:sample_rate=24000:duration=2.4',
      audio.path,
    ]);
    expect(sine.exitCode, 0, reason: '${sine.stderr}');
    expect(audio.existsSync(), isTrue);
    expect(audio.lengthSync(), greaterThan(400));

    final slides = <({String path, double seconds})>[];
    for (var i = 0; i < lecture.slides.length; i++) {
      final png = File(p.join(work.path, 'slide_$i.png'));
      final slide = await Process.run(ffmpeg, [
        '-y',
        '-f',
        'lavfi',
        '-i',
        'color=c=0x0A1F44:s=1280x720:d=0.12',
        '-frames:v',
        '1',
        png.path,
      ]);
      expect(slide.exitCode, 0, reason: '${slide.stderr}');
      slides.add((
        path: png.path,
        seconds: holds[i].inMilliseconds / 1000.0,
      ));
    }

    final list = File(p.join(work.path, 'slides_concat.txt'));
    final sink = list.openWrite();
    for (final s in slides) {
      final abs = File(s.path).absolute.path.replaceAll(r'\', '/');
      sink.writeln("file '$abs'");
      sink.writeln('duration ${s.seconds.toStringAsFixed(3)}');
    }
    final last = File(slides.last.path).absolute.path.replaceAll(r'\', '/');
    sink.writeln("file '$last'");
    await sink.close();

    final out = File(p.join(work.path, 'lecture.mp4'));
    final encode = await Process.run(ffmpeg, [
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      list.path,
      '-i',
      audio.path,
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
    expect(encode.exitCode, 0, reason: '${encode.stderr}');
    expect(out.existsSync(), isTrue);
    expect(out.lengthSync(), greaterThan(8000));

    final probe = await Process.run(ffprobe, [
      '-v',
      'error',
      '-show_entries',
      'stream=codec_type,duration:format=duration',
      '-of',
      'json',
      out.path,
    ]);
    expect(probe.exitCode, 0, reason: '${probe.stderr}');
    final map = jsonDecode('${probe.stdout}') as Map<String, dynamic>;
    final streams = map['streams'] as List? ?? const [];
    final types = [
      for (final s in streams)
        if (s is Map) '${s['codec_type']}',
    ];
    expect(types, contains('video'));
    expect(types, contains('audio'));

    final format = map['format'];
    final videoDuration = double.tryParse(
          format is Map ? '${format['duration']}' : '',
        ) ??
        0;
    expect(videoDuration, greaterThan(1.5));
    expect(videoDuration, closeTo(2.4, 0.6));

    final dest = File(p.join('build', 'ai_rendered_videos', 'ai_teacher_mux_verify.mp4'));
    await dest.parent.create(recursive: true);
    await out.copy(dest.path);
    expect(dest.existsSync(), isTrue);
    expect(dest.lengthSync(), greaterThan(8000));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
