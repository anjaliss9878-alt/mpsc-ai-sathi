/// Maps Gemini / network failures to short development-visible reasons.
/// Never includes API keys or stack traces.
String classifyAiGenerationFailure(Object error) {
  final raw = '$error'.trim();
  final first = raw.split('\n').first.trim();
  final lower = raw.toLowerCase();

  const known = <String>{
    'Gemini API key missing',
    'Gemini API unauthorized',
    'model not found',
    'quota exceeded',
    'invalid request',
    'network error',
    'response parsing error',
  };
  if (known.contains(first)) return first;

  if (lower.contains('api key') &&
      (lower.contains('missing') ||
          lower.contains('empty') ||
          lower.contains('not configured'))) {
    return 'Gemini API key missing';
  }
  if (lower.contains('api_key_invalid') ||
      lower.contains('unauthorized') ||
      lower.contains('permission_denied') ||
      lower.contains('permission denied') ||
      lower.contains('401') ||
      lower.contains('403')) {
    return 'Gemini API unauthorized';
  }
  if (lower.contains('resource_exhausted') ||
      lower.contains('quota') ||
      lower.contains('429')) {
    return 'quota exceeded';
  }
  if (lower.contains('not_found') ||
      lower.contains('model not found') ||
      lower.contains('is no longer available') ||
      lower.contains('404')) {
    return 'model not found';
  }
  if (lower.contains('did not return a json') ||
      lower.contains('response parsing') ||
      lower.contains('format exception') ||
      lower.contains('is not a subtype') ||
      lower.contains('json object')) {
    return 'response parsing error';
  }
  if (lower.contains('socket') ||
      lower.contains('network') ||
      lower.contains('failed host') ||
      lower.contains('failed to fetch') ||
      lower.contains('xmlhttprequest') ||
      lower.contains('clientexception') ||
      lower.contains('timed out') ||
      lower.contains('timeout') ||
      lower.contains('cors') ||
      lower.contains('connection refused') ||
      lower.contains('unavailable') ||
      lower.contains('503')) {
    return 'network error';
  }
  if (lower.contains('invalid_argument') ||
      lower.contains('invalid request') ||
      lower.contains('400')) {
    return 'invalid request';
  }
  if (first.isEmpty) return 'invalid request';
  return first;
}

/// Student classroom pipeline stage. Never treat empty RAG as a hard failure.
String classifyClassroomPipelineStage(Object error) {
  final type = error.runtimeType.toString();
  final lower = '$error'.toLowerCase();
  if (type.contains('AiTtsException') ||
      lower.contains('empty lesson script') ||
      lower.contains('tts') ||
      lower.contains('audio') ||
      lower.contains('voice') ||
      lower.contains('आवाज')) {
    return 'tts';
  }
  if (lower.contains('playback') || lower.contains('html audio')) {
    return 'audio playback';
  }
  if (lower.contains('scene generation') ||
      lower.contains('स्लाइड्स तयार') ||
      lower.contains('slides were not')) {
    return 'scene generation';
  }
  if (lower.contains('rag') &&
      (lower.contains('failed') || lower.contains('error'))) {
    return 'rag';
  }
  return 'lesson generation';
}

String classroomPipelineError(Object error, {String? stage}) {
  final resolved = (stage ?? classifyClassroomPipelineStage(error)).trim();
  final classified = classifyAiGenerationFailure(error);
  switch (resolved) {
    case 'tts':
      return 'TTS failed — Retry ($classified)';
    case 'audio playback':
      return 'Audio playback failed — Retry ($classified)';
    case 'scene generation':
      return 'Scene generation failed — Retry ($classified)';
    case 'rag':
      return 'RAG failed — Retry ($classified)';
    default:
      return 'Lesson generation failed — Retry ($classified)';
  }
}
