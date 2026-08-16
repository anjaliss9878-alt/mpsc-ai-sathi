// Smoke-test Google Cloud TTS for AI Classroom.
//
// Usage (from repo root):
//   D:\flutter\flutter\bin\dart.bat run tool/test_cloud_tts.dart
//
// Auth (first match wins):
//   TTS_SERVICE_ACCOUNT_PATH / TTS_SERVICE_ACCOUNT_JSON
//   GOOGLE_APPLICATION_CREDENTIALS
//   TTS_ACCESS_TOKEN
//   GOOGLE_TTS_API_KEY / TTS_API_KEY / AI_API_KEY
//
// Voice defaults: mr-IN-Wavenet-A at speakingRate 0.9 with teaching SSML.

import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  const phrase = 'भारतीय राज्यघटना म्हणजे काय? समजा — हे महत्त्वाचे आहे.';
  final defines = await _loadDefines();

  final languageCode =
      (defines['GOOGLE_TTS_LANGUAGE_CODE'] ?? 'mr-IN').toString().trim();
  final voiceName =
      (defines['GOOGLE_TTS_VOICE_NAME'] ?? 'mr-IN-Wavenet-A').toString().trim();

  stdout.writeln('Synthesizing: $phrase');
  stdout.writeln('voice=$voiceName lang=$languageCode rate=0.9');

  final auth = await _resolveAuth(defines);
  final uri = Uri.parse(
    'https://texttospeech.googleapis.com/v1/text:synthesize',
  );
  final ssml = _toTeachingSsml(phrase);
  final body = jsonEncode({
    'input': {'ssml': ssml},
    'voice': {'languageCode': languageCode, 'name': voiceName},
    'audioConfig': {
      'audioEncoding': 'MP3',
      'speakingRate': 0.9,
      'effectsProfileId': ['handset-class-device'],
    },
  });

  final headers = <String, String>{
    'Content-Type': 'application/json; charset=utf-8',
    ...auth.headers,
  };

  final client = auth.client ?? http.Client();
  try {
    final res = await client.post(uri, headers: headers, body: body);
    if (res.statusCode != 200) {
      stderr.writeln('FAIL: HTTP ${res.statusCode}');
      stderr.writeln(res.body);
      if (res.statusCode == 401 || res.statusCode == 403) {
        stderr.writeln('');
        stderr.writeln(
          'Cloud Text-to-Speech needs a GCP service-account JSON key,',
        );
        stderr.writeln(
          'or GOOGLE_TTS_API_KEY restricted for Cloud TTS.',
        );
        stderr.writeln(
          'Set TTS_SERVICE_ACCOUNT_PATH in dart_defines.json, then retry.',
        );
      }
      exit(2);
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final b64 = decoded['audioContent'] as String?;
    if (b64 == null || b64.isEmpty) {
      stderr.writeln('FAIL: missing audioContent');
      stderr.writeln(res.body);
      exit(3);
    }

    final bytes = base64Decode(b64);
    final outDir = Directory('tts_cache');
    if (!await outDir.exists()) await outDir.create(recursive: true);
    final outFile = File('tts_cache/test_marathi_constitution.mp3');
    await outFile.writeAsBytes(bytes, flush: true);

    stdout.writeln('OK: Google Cloud TTS synthesized Marathi speech.');
    stdout.writeln('Saved: ${outFile.path} (${bytes.length} bytes)');
    stdout.writeln(
      'In AI Classroom → Ask: "$phrase" → audio plays with subtitle highlight.',
    );
  } finally {
    auth.client?.close();
    if (auth.client == null) client.close();
  }
}

String _toTeachingSsml(String text) {
  final escaped = text
      .trim()
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
  return '<speak><prosody pitch="-1st" volume="medium">$escaped</prosody></speak>';
}

Future<({Map<String, String> headers, AutoRefreshingAuthClient? client})>
    _resolveAuth(Map<String, dynamic> defines) async {
  const scopes = ['https://www.googleapis.com/auth/cloud-platform'];

  final token = (defines['TTS_ACCESS_TOKEN'] ?? '').toString().trim();
  if (token.isNotEmpty) {
    return (
      headers: {'Authorization': 'Bearer $token'},
      client: null,
    );
  }

  Map<String, dynamic>? sa;
  final inline = (defines['TTS_SERVICE_ACCOUNT_JSON'] ?? '').toString().trim();
  if (inline.isNotEmpty) {
    sa = jsonDecode(inline) as Map<String, dynamic>;
  } else {
    final path = (defines['TTS_SERVICE_ACCOUNT_PATH'] ??
            Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'] ??
            '')
        .toString()
        .trim();
    if (path.isNotEmpty) {
      final file = File(path);
      if (!await file.exists()) {
        stderr.writeln('FAIL: service-account file not found: $path');
        exit(1);
      }
      sa = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    }
  }

  if (sa != null) {
    final creds = ServiceAccountCredentials.fromJson(sa);
    final client = await clientViaServiceAccount(creds, scopes);
    return (headers: <String, String>{}, client: client);
  }

  final key = (defines['GOOGLE_TTS_API_KEY'] ??
          defines['TTS_API_KEY'] ??
          defines['AI_API_KEY'] ??
          '')
      .toString()
      .trim();
  if (key.isEmpty) {
    stderr.writeln(
      'FAIL: No TTS credentials. Set TTS_SERVICE_ACCOUNT_PATH in dart_defines.json',
    );
    exit(1);
  }
  stdout.writeln(
    'WARN: Using API key auth — prefer a service account for Cloud TTS.',
  );
  return (headers: {'x-goog-api-key': key}, client: null);
}

Future<Map<String, dynamic>> _loadDefines() async {
  final file = File('dart_defines.json');
  if (!await file.exists()) return {};
  return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
}
