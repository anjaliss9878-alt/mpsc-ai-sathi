import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';

void main() {
  test('production Netlify web build does not dart-define API secrets', () {
    final script = File('tool/netlify_build.sh').readAsStringSync();
    expect(script.contains('--dart-define="AI_API_KEY'), isFalse);
    expect(script.contains('--dart-define=AI_API_KEY'), isFalse);
    expect(script.contains('--dart-define="ELEVENLABS_API_KEY'), isFalse);
    expect(script.contains('--dart-define=ELEVENLABS_API_KEY'), isFalse);
    expect(RegExp(r'--dart-define=["' "'" r']?VERTEX_').hasMatch(script), isFalse);
    expect(
      const String.fromEnvironment('AI_API_KEY'),
      isEmpty,
      reason: 'Gemini key must not be compiled into the test/client bundle',
    );
    expect(const String.fromEnvironment('ELEVENLABS_API_KEY'), isEmpty);
    expect(const String.fromEnvironment('VERTEX_SERVICE_ACCOUNT_JSON'), isEmpty);
    expect(const String.fromEnvironment('VERTEX_ACCESS_TOKEN'), isEmpty);
    expect(const String.fromEnvironment('VERTEX_PROJECT'), isEmpty);
  });

  test('RagBackendClient sends the Firebase ID token on /rag calls', () async {
    http.Request? seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
        jsonEncode({'insufficient': true, 'answer': ''}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final rag = RagBackendClient(
      client: client,
      baseUrl: 'https://example.netlify.app',
      idToken: () async => 'test-id-token',
    );
    final payload = await rag.learn({
      'mode': 'answer',
      'question': 'Article 14?',
      'chunks': const <Map<String, dynamic>>[],
    });
    expect(seen, isNotNull);
    expect(seen!.url.path, '/rag/learn');
    expect(seen!.headers['Authorization'], 'Bearer test-id-token');
    expect(payload['insufficient'], isTrue);
  });
}
