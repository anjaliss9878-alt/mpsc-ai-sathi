import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/ai_backend_base.dart';
import 'package:mpsc_combine_ai/services/classroom_video/classroom_video_client.dart';

void main() {
  test('production Student AI Video lesson URL is the Netlify /ai/lesson route', () {
    final bases = lessonBackendBaseCandidates(debug: false, isWeb: true);
    expect(bases, [kProductionAiBackendOrigin]);
    expect(aiLessonEndpoint(bases.single), 'https://mpscaisathi.co.in/ai/lesson');
    expect(aiLessonEndpoint(bases.single), isNot(contains('127.0.0.1')));
    expect(aiLessonEndpoint(bases.single), isNot(contains('localhost')));
  });

  test('mux /render is only advertised by the local ffmpeg worker health payload', () {
    expect(
      classroomEngineHealthOk(200, '{"ok":true}'),
      isFalse,
      reason: 'Netlify /health must not be treated as a video renderer',
    );
    expect(
      classroomEngineHealthOk(
        200,
        '{"ok":true,"canRender":true,"ffmpeg":true}',
      ),
      isTrue,
    );
    expect(
      aiVideoRenderEndpoint(kLocalClassroomWorkerOrigin),
      'http://127.0.0.1:8791/render',
    );
  });

  test('localhost Student waits for the classroom worker health', () {
    expect(
      shouldWaitForLocalAiWorker(
        debug: true,
        isWeb: true,
        pageHost: 'localhost',
      ),
      isTrue,
    );
    expect(
      shouldWaitForLocalAiWorker(
        debug: true,
        isWeb: true,
        pageHost: '',
      ),
      isTrue,
    );
    expect(
      shouldWaitForLocalAiWorker(
        debug: false,
        isWeb: true,
        pageHost: 'mpscaisathi.co.in',
      ),
      isFalse,
    );
  });

  test('first healthy AI backend returns the first origin with HTTP 200', () async {
    final seen = <String>[];
    final found = await firstHealthyAiBackendBase(
      bases: ['http://127.0.0.1:8791', 'https://mpscaisathi.co.in'],
      healthStatus: (origin) async {
        seen.add(origin);
        if (origin.contains('127.0.0.1')) return 503;
        return 200;
      },
    );
    expect(found, 'https://mpscaisathi.co.in');
    expect(seen, ['http://127.0.0.1:8791', 'https://mpscaisathi.co.in']);
  });

  test('local Student wait skips production /health even when it returns 200', () async {
    final found = await firstHealthyAiBackendBase(
      bases: ['http://127.0.0.1:8791', 'https://mpscaisathi.co.in'],
      waitForLocalWorker: true,
      healthStatus: (origin) async {
        if (origin.contains('127.0.0.1')) return 503;
        return 200;
      },
    );
    expect(found, isNull);
  });
}
