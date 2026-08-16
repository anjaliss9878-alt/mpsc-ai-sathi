import 'package:flutter/foundation.dart';

/// Development-only AI Teacher traces. Never prints secrets or raw API keys.
void aiChapterLog(String stage, [Map<String, Object?> details = const {}]) {
  if (!kDebugMode) return;
  final parts = <String>[
    for (final e in details.entries)
      if (e.value != null) '${e.key}=${e.value}',
  ];
  debugPrint('[AI-CHAPTER] $stage${parts.isEmpty ? '' : ' ${parts.join(' ')}'}');
}
