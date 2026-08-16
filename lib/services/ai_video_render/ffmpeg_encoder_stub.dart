import 'dart:typed_data';

/// Web stub — real encode requires IO + FFmpeg.
class FfmpegVideoEncoder {
  const FfmpegVideoEncoder();

  Future<bool> get isAvailable async => false;

  Future<String> encode({
    required String workDir,
    required List<String> framePaths,
    required String audioPath,
    required String outputPath,
    required int fps,
    void Function(double progress)? onProgress,
  }) async {
    throw UnsupportedError(
      'Real MP4/WebM encode needs FFmpeg on a native target '
      '(Windows/Android/macOS). On web, play a cached/prebuilt video asset.',
    );
  }

  Future<String> encodeTimedSlides({
    required String workDir,
    required List<({String path, double seconds})> slides,
    required String audioPath,
    required String outputPath,
    required int fps,
    void Function(double progress)? onProgress,
  }) =>
      encode(
        workDir: workDir,
        framePaths: slides.map((s) => s.path).toList(),
        audioPath: audioPath,
        outputPath: outputPath,
        fps: fps,
        onProgress: onProgress,
      );

  Future<String> encodeFromPngBytes({
    required String workDir,
    required List<Uint8List> frames,
    required Uint8List audioBytes,
    required String outputPath,
    required int fps,
    void Function(double progress)? onProgress,
  }) =>
      encode(
        workDir: workDir,
        framePaths: const [],
        audioPath: '',
        outputPath: outputPath,
        fps: fps,
        onProgress: onProgress,
      );
}
