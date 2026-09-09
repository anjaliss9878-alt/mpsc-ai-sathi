import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/utils/ai_generation_error.dart';

void main() {
  test('classifies Gemini development failures', () {
    expect(classifyAiGenerationFailure('Gemini API key is missing'),
        'Gemini API key missing');
    expect(classifyAiGenerationFailure('HTTP 403 PERMISSION_DENIED'),
        'Gemini API unauthorized');
    expect(
      classifyAiGenerationFailure(
        'models/gemini-2.0-flash is no longer available 404 NOT_FOUND',
      ),
      'model not found',
    );
    expect(classifyAiGenerationFailure('RESOURCE_EXHAUSTED 429 quota'),
        'quota exceeded');
    expect(classifyAiGenerationFailure('INVALID_ARGUMENT 400'),
        'invalid request');
    expect(classifyAiGenerationFailure('XMLHttpRequest error'), 'network error');
    expect(classifyAiGenerationFailure('Gemini did not return a JSON object'),
        'response parsing error');
  });

  test('classroom errors name the failed stage, not generic video failure', () {
    expect(classifyClassroomPipelineStage('network error'), 'lesson generation');
    expect(
      classroomPipelineError('network error'),
      'Lesson generation failed — Retry (network error)',
    );
    expect(
      classroomPipelineError('XMLHttpRequest error'),
      isNot(contains('Video generation failed')),
    );
    expect(
      classroomPipelineError('scene generation: slides empty'),
      startsWith('Scene generation failed'),
    );
    expect(
      classroomPipelineError('Gemini TTS failed', stage: 'tts'),
      startsWith('TTS failed'),
    );
  });
}
