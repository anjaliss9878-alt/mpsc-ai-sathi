import 'dart:math' as math;
import 'dart:typed_data';

/// Last-resort timed mono WAV so FFmpeg can still mux a real MP4 when online
/// TTS is unavailable. Soft tonal bed (not speech) — never used when Gemini /
/// Cloud TTS succeeds.
Uint8List buildTimedSoftBedWav(Duration duration, {int sampleRate = 24000}) {
  final seconds = duration.inMilliseconds / 1000.0;
  final n = math.max(sampleRate ~/ 4, (seconds * sampleRate).round());
  final pcm = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    // Very soft low chord — keeps A/V sync without fake speech.
    final env = (t < 0.04)
        ? t / 0.04
        : (t > seconds - 0.08 ? ((seconds - t) / 0.08).clamp(0.0, 1.0) : 1.0);
    final sample = 0.035 *
        env *
        (math.sin(2 * math.pi * 196 * t) +
            0.5 * math.sin(2 * math.pi * 247 * t));
    final v = (sample * 32767).round().clamp(-32768, 32767);
    pcm.setInt16(i * 2, v, Endian.little);
  }
  return _wrapWav(pcm.buffer.asUint8List(), sampleRate: sampleRate);
}

Uint8List _wrapWav(Uint8List pcm, {required int sampleRate}) {
  final dataLength = pcm.length;
  final header = BytesBuilder();
  void u32(int v) => header.add([
        v & 0xff,
        (v >> 8) & 0xff,
        (v >> 16) & 0xff,
        (v >> 24) & 0xff,
      ]);
  void u16(int v) => header.add([v & 0xff, (v >> 8) & 0xff]);
  header.add([0x52, 0x49, 0x46, 0x46]); // RIFF
  u32(36 + dataLength);
  header.add([0x57, 0x41, 0x56, 0x45, 0x66, 0x6d, 0x74, 0x20]); // WAVEfmt
  u32(16);
  u16(1);
  u16(1);
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  header.add([0x64, 0x61, 0x74, 0x61]); // data
  u32(dataLength);
  return (BytesBuilder(copy: false)
        ..add(header.takeBytes())
        ..add(pcm))
      .takeBytes();
}
