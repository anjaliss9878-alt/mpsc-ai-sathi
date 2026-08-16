// Student-facing Marathi copy. Never show backend stages, URLs, or stack traces.

import 'package:flutter/foundation.dart';
import 'package:mpsc_combine_ai/utils/ai_generation_error.dart';

const kDhadaPreparing = 'AI धडा तयार करत आहे...';
const kEnterTopic = 'कृपया विषय लिहा.';
const kLessonFailed = 'AI धडा तयार करता आला नाही. कृपया पुन्हा प्रयत्न करा.';
const kAudioUnavailable =
    'आवाज सध्या उपलब्ध नाही. धडा वाचून अभ्यास करू शकता.';
const kGenericRetry = 'काहीतरी चुकले. कृपया पुन्हा प्रयत्न करा.';

String studentFacingError(Object error) {
  final classified = classifyAiGenerationFailure(error);
  if (kDebugMode) return classified;

  final raw = '$error';
  final lower = raw.toLowerCase();
  if (lower.contains('कृपया विषय') || lower.contains('enter a topic')) {
    return kEnterTopic;
  }
  if (lower.contains('localhost') ||
      lower.contains('127.0.0.1') ||
      lower.contains('elevenlabs') ||
      lower.contains('gemini') ||
      lower.contains('api key') ||
      lower.contains('http') ||
      lower.contains('exception') ||
      lower.contains('timeout') ||
      lower.contains('websocket') ||
      lower.contains('firebase') ||
      lower.contains('stack') ||
      classified != raw.split('\n').first.trim()) {
    return kLessonFailed;
  }
  if (raw.contains('धडा') || raw.contains('कृपया')) {
    return raw.split('\n').first.trim();
  }
  return kLessonFailed;
}
