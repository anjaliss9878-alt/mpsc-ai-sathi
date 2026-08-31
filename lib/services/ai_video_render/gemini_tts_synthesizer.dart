import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Gemini TTS via generateContent (uses AI_API_KEY already configured).
///
/// Returns WAV bytes (PCM16 mono) suitable for FFmpeg concat/mux.
class GeminiTtsSynthesizer {
  GeminiTtsSynthesizer({http.Client? client, String? apiKey})
      : _client = client ?? http.Client(),
        _apiKey = (apiKey ?? _envApiKey).trim();

  final http.Client _client;
  final String _apiKey;

  static const String _envApiKey = String.fromEnvironment('AI_API_KEY');
  static const String _modelOverride = String.fromEnvironment('GEMINI_TTS_MODEL');

  static const _models = <String>[
    'gemini-3.1-flash-tts-preview',
  ];

  bool get isConfigured => _apiKey.trim().isNotEmpty;

  Future<Uint8List> synthesizeMarathiFaculty(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw StateError('Empty TTS text');
    }
    if (!isConfigured) {
      throw StateError('AI_API_KEY missing for Gemini TTS');
    }

    final models = <String>[
      if (_modelOverride.trim().isNotEmpty) _modelOverride.trim(),
      ..._models,
    ];
    Object? lastError;
    for (final model in models) {
      try {
        return await _synthesizeWithModel(model, trimmed);
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('Gemini TTS failed for all models: $lastError');
  }

  /// Three attempts with exponential backoff. Stores the last exact error.
  Future<Uint8List> synthesizeMarathiFacultyWithRetry(
    String text, {
    int attempts = 1,
  }) async {
    Object? lastError;
    for (var i = 0; i < attempts; i++) {
      try {
        return await synthesizeMarathiFaculty(text);
      } catch (e) {
        lastError = e;
        if (i == attempts - 1) break;
        await Future<void>.delayed(Duration(milliseconds: 400 * (1 << i)));
      }
    }
    throw StateError('Gemini TTS failed after $attempts retries: $lastError');
  }

  /// Concatenate Gemini WAV clips (PCM16 mono). Headers after the first are stripped.
  static Uint8List concatWav(List<Uint8List> wavs) {
    if (wavs.isEmpty) {
      throw StateError('No WAV clips to concatenate');
    }
    if (wavs.length == 1) return wavs.first;
    var sampleRate = 24000;
    final pcm = BytesBuilder(copy: false);
    for (final wav in wavs) {
      if (wav.length < 44) continue;
      sampleRate = ByteData.sublistView(wav).getUint32(24, Endian.little);
      pcm.add(wav.sublist(44));
    }
    final data = pcm.takeBytes();
    if (data.isEmpty) return wavs.first;
    return _pcm16ToWavStatic(Uint8List.fromList(data), sampleRate: sampleRate);
  }

  static Uint8List _pcm16ToWavStatic(Uint8List pcm, {required int sampleRate}) {
    final dataLength = pcm.length;
    final byteRate = sampleRate * 2;
    final header = BytesBuilder();
    void writeString(String s) => header.add(utf8.encode(s));
    void writeUint32(int v) {
      header.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
    }

    void writeUint16(int v) {
      header.add([v & 0xff, (v >> 8) & 0xff]);
    }

    writeString('RIFF');
    writeUint32(36 + dataLength);
    writeString('WAVE');
    writeString('fmt ');
    writeUint32(16);
    writeUint16(1);
    writeUint16(1);
    writeUint32(sampleRate);
    writeUint32(byteRate);
    writeUint16(2);
    writeUint16(16);
    writeString('data');
    writeUint32(dataLength);
    return Uint8List.fromList([...header.takeBytes(), ...pcm]);
  }

  /// Duration of a PCM16 mono WAV produced by this synthesizer.
  static Duration wavDuration(Uint8List wav) {
    if (wav.length < 44) return Duration.zero;
    final rate = ByteData.sublistView(wav).getUint32(24, Endian.little);
    if (rate <= 0) return Duration.zero;
    final dataLen = wav.length - 44;
    final ms = (dataLen / (rate * 2) * 1000).round();
    return Duration(milliseconds: ms.clamp(0, 60 * 60 * 1000));
  }

  Future<Uint8List> _synthesizeWithModel(String model, String trimmed) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    );
    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'text':
                  'Speak in natural Marathi as a warm female MPSC faculty. '
                  'Do not add extra words. Read exactly:\n$trimmed',
            },
          ],
        },
      ],
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {
              'voiceName': 'Kore',
            },
          },
        },
      },
    });

    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': _apiKey,
          },
          body: body,
        )
          .timeout(const Duration(seconds: 90));

    if (response.statusCode != 200) {
      final snippet = response.body.length > 220
          ? response.body.substring(0, 220)
          : response.body;
      print('[GeminiTTS] http=${response.statusCode} model=$model');
      throw StateError(
        'Gemini TTS failed HTTP ${response.statusCode} ($model): $snippet',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw StateError('Gemini TTS returned no candidates ($model)');
    }
    final content = (candidates.first as Map)['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List || parts.isEmpty) {
      throw StateError('Gemini TTS returned no audio parts ($model)');
    }
    final inline = (parts.first as Map)['inlineData'] ??
        (parts.first as Map)['inline_data'];
    if (inline is! Map) {
      throw StateError('Gemini TTS missing inline audio data ($model)');
    }
    final b64 = (inline['data'] as String?) ?? '';
    final mime = (inline['mimeType'] as String?) ??
        (inline['mime_type'] as String?) ??
        'audio/L16;rate=24000';
    if (b64.isEmpty) {
      throw StateError('Gemini TTS empty audio payload ($model)');
    }
    final pcm = base64Decode(b64);
    final rate = _parseRate(mime) ?? 24000;
    return _pcm16ToWav(Uint8List.fromList(pcm), sampleRate: rate);
  }

  int? _parseRate(String mime) {
    final m = RegExp(r'rate=(\d+)').firstMatch(mime);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  Uint8List _pcm16ToWav(Uint8List pcm, {required int sampleRate}) {
    final dataLength = pcm.length;
    final byteRate = sampleRate * 2; // mono 16-bit
    final header = BytesBuilder();
    void writeString(String s) => header.add(utf8.encode(s));
    void writeUint32(int v) {
      header.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
    }

    void writeUint16(int v) {
      header.add([v & 0xff, (v >> 8) & 0xff]);
    }

    writeString('RIFF');
    writeUint32(36 + dataLength);
    writeString('WAVE');
    writeString('fmt ');
    writeUint32(16); // PCM chunk size
    writeUint16(1); // PCM
    writeUint16(1); // mono
    writeUint32(sampleRate);
    writeUint32(byteRate);
    writeUint16(2); // block align
    writeUint16(16); // bits
    writeString('data');
    writeUint32(dataLength);
    final out = BytesBuilder(copy: false)
      ..add(header.takeBytes())
      ..add(pcm);
    return out.takeBytes();
  }
}
