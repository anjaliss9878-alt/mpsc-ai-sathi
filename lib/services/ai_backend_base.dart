import 'package:flutter/foundation.dart';

/// Resolves the AI backend base URL.
///
/// [CLASSROOM_VIDEO_WORKER] overrides everything when set.
/// Debug / desktop default remains the local classroom worker.
/// Release web uses the same origin so Netlify `/ai/*` functions work
/// without baking API keys into the Flutter JS bundle.
String aiBackendBase() {
  const configured = String.fromEnvironment(
    'CLASSROOM_VIDEO_WORKER',
    defaultValue: '',
  );
  final trimmed = configured.trim().replaceAll(RegExp(r'/$'), '');
  if (trimmed.isNotEmpty) return trimmed;
  if (kIsWeb && !kDebugMode) {
    return Uri.base.origin;
  }
  return 'http://127.0.0.1:8791';
}
