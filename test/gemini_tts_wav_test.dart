import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/gemini_tts_synthesizer.dart';

void main() {
  test('raw PCM is wrapped as WAV with the mime sample rate', () {
    final pcm = Uint8List.fromList(List<int>.filled(480, 0));
    final wav = GeminiTtsSynthesizer.ensureWav(
      pcm,
      mimeType: 'audio/L16;rate=24000',
    );
    expect(GeminiTtsSynthesizer.isWavContainer(wav), isTrue);
    expect(wav.length, 44 + pcm.length);
    expect(ByteData.sublistView(wav).getUint32(24, Endian.little), 24000);
  });

  test('existing WAV is not double wrapped', () {
    final pcm = Uint8List.fromList(List<int>.filled(200, 1));
    final wav = GeminiTtsSynthesizer.ensureWav(
      pcm,
      mimeType: 'audio/L16;rate=16000',
    );
    final again = GeminiTtsSynthesizer.ensureWav(
      wav,
      mimeType: 'audio/wav',
    );
    expect(identical(again, wav) || again.length == wav.length, isTrue);
    expect(again.length, wav.length);
    expect(GeminiTtsSynthesizer.isWavContainer(again), isTrue);
    expect(again.sublist(0, 12), wav.sublist(0, 12));
  });
}
