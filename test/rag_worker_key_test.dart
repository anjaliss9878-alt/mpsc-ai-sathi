import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/ai_backend_base.dart';

void main() {
  test('local worker Gemini key prefers process env over dart_defines', () {
    expect(
      resolveWorkerGeminiApiKey(envValue: 'env-key', definesValue: 'file-key'),
      'env-key',
    );
    expect(
      resolveWorkerGeminiApiKey(envValue: '  ', definesValue: 'file-key'),
      'file-key',
    );
    expect(
      resolveWorkerGeminiApiKey(envValue: '', definesValue: ''),
      isEmpty,
    );
  });

  test('debug Admin on localhost uses same-host worker, not 127.0.0.1', () {
    expect(
      resolveAiBackendBase(
        debug: true,
        isWeb: true,
        configured: '',
        pageHost: 'localhost',
      ),
      'http://localhost:8791',
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

  test('production Admin uses RAG_BACKEND_URL not localhost', () {
    expect(
      resolveAiBackendBase(
        debug: false,
        isWeb: true,
        ragBackendUrl: 'https://mpscaisathi.co.in',
        configured: 'http://127.0.0.1:8791',
      ),
      'https://mpscaisathi.co.in',
    );
  });
}
