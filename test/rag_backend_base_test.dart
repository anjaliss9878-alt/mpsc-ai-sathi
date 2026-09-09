import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';
import 'package:mpsc_combine_ai/services/ai_backend_base.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';

void main() {
  test('loopback RAG backends are detected', () {
    expect(isLoopbackAiBackend('http://127.0.0.1:8791'), isTrue);
    expect(isLoopbackAiBackend('http://localhost:8081'), isTrue);
    expect(isLoopbackAiBackend(kProductionAiBackendOrigin), isFalse);
  });

  test('debug uses local classroom worker when dart-define is empty', () {
    expect(
      resolveAiBackendBase(debug: true, isWeb: true, configured: ''),
      kLocalClassroomWorkerOrigin,
    );
    expect(aiBackendBase(), kLocalClassroomWorkerOrigin);
  });

  test('release web always uses production Student origin', () {
    expect(
      resolveAiBackendBase(debug: false, isWeb: true, configured: ''),
      kProductionAiBackendOrigin,
    );
  });

  test('release web prefers RAG_BACKEND_URL over CLASSROOM_VIDEO_WORKER', () {
    expect(
      resolveAiBackendBase(
        debug: false,
        isWeb: true,
        configured: 'https://legacy-worker.example',
        ragBackendUrl: kProductionAiBackendOrigin,
      ),
      kProductionAiBackendOrigin,
    );
  });

  test('release web ignores loopback CLASSROOM_VIDEO_WORKER', () {
    expect(
      resolveAiBackendBase(
        debug: false,
        isWeb: true,
        configured: 'http://127.0.0.1:8791',
      ),
      kProductionAiBackendOrigin,
    );
    expect(
      resolveAiBackendBase(
        debug: false,
        isWeb: true,
        configured: 'http://localhost:8791/',
        ragBackendUrl: 'http://127.0.0.1:8791',
      ),
      kProductionAiBackendOrigin,
    );
  });

  test('deployed Admin never uses localhost even in a debug bundle', () {
    expect(
      resolveAiBackendBase(
        debug: true,
        isWeb: true,
        configured: 'http://127.0.0.1:8791',
        ragBackendUrl: '',
        pageHost: 'mpsc-ai-admin.netlify.app',
      ),
      kProductionAiBackendOrigin,
    );
    expect(
      resolveAiBackendBase(
        debug: true,
        isWeb: true,
        ragBackendUrl: kProductionAiBackendOrigin,
        pageHost: 'mpsc-ai-admin.netlify.app',
      ),
      kProductionAiBackendOrigin,
    );
  });

  test('debug Admin ignores production CLASSROOM_VIDEO_WORKER', () {
    expect(
      resolveAiBackendBase(
        debug: true,
        isWeb: true,
        configured: kProductionAiBackendOrigin,
      ),
      kLocalClassroomWorkerOrigin,
    );
    expect(
      resolveAiBackendBase(
        debug: true,
        isWeb: true,
        configured: kProductionAiBackendOrigin,
        pageHost: 'localhost',
      ),
      'http://localhost:8791',
    );
  });

  test('release desktop keeps a non-loopback dart-define', () {
    expect(
      resolveAiBackendBase(
        debug: false,
        isWeb: false,
        configured: 'https://custom-worker.example',
      ),
      'https://custom-worker.example',
    );
  });

  test('debug extract/embed/learn stay on the local worker', () async {
    final origins = <String>[];
    final client = MockClient((request) async {
      origins.add('${request.url.scheme}://${request.url.authority}');
      expect(request.url.path, '/rag/extract');
      expect(request.url.origin, isNot(kProductionAiBackendOrigin));
      return Response(
        jsonEncode({
          'pages': [
            {'page': 1, 'text': 'local'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final rag = RagBackendClient(
      client: client,
      idToken: () async => 'debug-token',
    );
    final pages = await rag.extractPdf(fileUrl: 'https://example.invalid/a.pdf');
    expect(origins, ['http://127.0.0.1:8791']);
    expect(pages.single.text, 'local');
  });

  test('debug extract does not fall back to production', () async {
    final origins = <String>[];
    final client = MockClient((request) async {
      origins.add(request.url.origin);
      throw ClientException('Failed to fetch', request.url);
    });
    final rag = RagBackendClient(
      client: client,
      idToken: () async => 'admin-id-token',
    );
    await expectLater(
      rag.extractPdf(fileUrl: 'https://example.invalid/file.pdf'),
      throwsA(isA<RagException>()),
    );
    expect(origins, ['http://127.0.0.1:8791']);
  });

  test('debug local worker HTTP error includes the local URL', () async {
    final client = MockClient((request) async {
      expect(request.url.origin, 'http://127.0.0.1:8791');
      return Response(
        jsonEncode({'error': 'unauthenticated'}),
        401,
        headers: {'content-type': 'application/json'},
      );
    });
    final rag = RagBackendClient(
      client: client,
      idToken: () async => 'admin-id-token',
    );
    try {
      await rag.extractPdf(fileUrl: 'https://example.invalid/file.pdf');
      fail('should throw');
    } on RagException catch (e) {
      expect(e.message, contains('HTTP 401'));
      expect(e.message, contains('http://127.0.0.1:8791/rag/extract'));
      expect(e.message, contains('unauthenticated'));
      expect(e.message, isNot(contains('mpscaisathi.co.in')));
    }
  });

  test('production baseUrl posts extract to the Student RAG origin', () async {
    late Uri sent;
    final client = MockClient((request) async {
      sent = request.url;
      expect(request.headers['authorization'], 'Bearer admin-id-token');
      expect(request.url.path, '/rag/extract');
      return Response(
        jsonEncode({
          'pages': [
            {'page': 1, 'text': 'prod'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final rag = RagBackendClient(
      client: client,
      baseUrl: kProductionAiBackendOrigin,
      idToken: () async => 'admin-id-token',
    );
    final pages = await rag.extractPdf(fileUrl: 'https://example.invalid/a.pdf');
    expect(sent.origin, kProductionAiBackendOrigin);
    expect('$sent', isNot(contains('127.0.0.1')));
    expect('$sent', isNot(contains('localhost')));
    expect(pages.single.text, 'prod');
  });

  test('explicit baseUrl override does not silently switch origins', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      expect(request.url.origin, 'http://127.0.0.1:8791');
      throw ClientException('Failed to fetch', request.url);
    });
    final rag = RagBackendClient(
      client: client,
      baseUrl: 'http://127.0.0.1:8791',
      idToken: () async => 'token',
    );
    await expectLater(
      rag.extractPdf(fileUrl: 'https://example.invalid/file.pdf'),
      throwsA(isA<RagException>()),
    );
    expect(calls, 1);
  });

  test('debug lesson candidates never use production as localhost fallback', () {
    expect(
      lessonBackendBaseCandidates(debug: true, isWeb: true, configured: ''),
      ['http://localhost:8791', kLocalClassroomWorkerOrigin],
    );
    for (final base in lessonBackendBaseCandidates(
      debug: true,
      isWeb: true,
      configured: '',
    )) {
      expect(isLoopbackAiBackend(base), isTrue);
      expect(base, isNot(contains('mpscaisathi.co.in')));
    }
  });

  test('debug Student on localhost stays on the classroom worker, not production', () {
    expect(
      lessonBackendBaseCandidates(
        debug: true,
        isWeb: true,
        configured: '',
        pageHost: 'localhost',
      ),
      ['http://localhost:8791', kLocalClassroomWorkerOrigin],
    );
    expect(
      lessonBackendBaseCandidates(
        debug: true,
        isWeb: true,
        configured: '',
        pageHost: '127.0.0.1',
      ),
      [kLocalClassroomWorkerOrigin],
    );
    for (final base in lessonBackendBaseCandidates(
      debug: true,
      isWeb: true,
      pageHost: 'localhost',
    )) {
      expect(isLoopbackAiBackend(base), isTrue);
      expect(base, isNot(contains('mpscaisathi.co.in')));
    }
  });

  test('release and deployed web lesson candidates never use localhost', () {
    expect(
      lessonBackendBaseCandidates(debug: false, isWeb: true, configured: ''),
      [kProductionAiBackendOrigin],
    );
    expect(
      lessonBackendBaseCandidates(
        debug: true,
        isWeb: true,
        configured: 'http://127.0.0.1:8791',
        pageHost: 'mpscaisathi.co.in',
      ),
      [kProductionAiBackendOrigin],
    );
    expect(
      lessonBackendBaseCandidates(
        debug: false,
        isWeb: true,
        configured: 'http://localhost:8791',
        ragBackendUrl: 'http://127.0.0.1:8791',
      ),
      [kProductionAiBackendOrigin],
    );
    for (final base in lessonBackendBaseCandidates(
      debug: false,
      isWeb: true,
      configured: 'http://127.0.0.1:8791',
    )) {
      expect(isLoopbackAiBackend(base), isFalse);
      expect(base, isNot(contains('localhost')));
    }
  });

  test('AI lesson and render endpoints stay on the resolved backend origin', () {
    expect(
      aiLessonEndpoint(kProductionAiBackendOrigin),
      '$kProductionAiBackendOrigin/ai/lesson',
    );
    expect(
      aiVideoRenderEndpoint(kLocalClassroomWorkerOrigin),
      '$kLocalClassroomWorkerOrigin/render',
    );
    expect(aiLessonEndpoint(kProductionAiBackendOrigin), isNot(contains('127.0.0.1')));
  });
}
