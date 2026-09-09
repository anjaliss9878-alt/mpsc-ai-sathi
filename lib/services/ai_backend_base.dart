import 'package:flutter/foundation.dart';

/// Production Student Netlify origin that already hosts `/rag/*` and `/ai/*`.
/// Same default as `tool/netlify_build_admin.sh` / `admin-netlify/netlify.toml`.
const kProductionAiBackendOrigin = 'https://mpscaisathi.co.in';

const kLocalClassroomWorkerOrigin = 'http://127.0.0.1:8791';

/// Resolves the AI / RAG backend base URL.
///
/// Production Admin (release web, or any deployed non-loopback host) uses
/// [RAG_BACKEND_URL], then [CLASSROOM_VIDEO_WORKER], then
/// [kProductionAiBackendOrigin]. Loopback values are ignored so deployed
/// Admin never depends on localhost.
///
/// Local debug Admin on localhost:8080/8081 uses [kLocalClassroomWorkerOrigin]
/// so the classroom worker on :8791 keeps working for development.
String aiBackendBase() {
  const ragBackendUrl = String.fromEnvironment(
    'RAG_BACKEND_URL',
    defaultValue: '',
  );
  const configured = String.fromEnvironment(
    'CLASSROOM_VIDEO_WORKER',
    defaultValue: '',
  );
  return resolveAiBackendBase(
    debug: kDebugMode,
    isWeb: kIsWeb,
    configured: configured,
    ragBackendUrl: ragBackendUrl,
    pageHost: kIsWeb ? Uri.base.host : '',
  );
}

/// Pure resolver used by [aiBackendBase] and unit tests.
String resolveAiBackendBase({
  required bool debug,
  required bool isWeb,
  String configured = '',
  String ragBackendUrl = '',
  String pageHost = '',
}) {
  final explicit = _firstNonEmpty([ragBackendUrl, configured]);
  final releaseWeb = isWeb && !debug;
  final deployedWeb = isWeb && _isDeployedWebHost(pageHost);

  // Deployed / release Admin must never call 127.0.0.1, even if a debug
  // bundle leaked onto Netlify or CLASSROOM_VIDEO_WORKER is loopback.
  if (releaseWeb || deployedWeb) {
    if (explicit.isNotEmpty && !isLoopbackAiBackend(explicit)) {
      return explicit;
    }
    return kProductionAiBackendOrigin;
  }

  if (debug) {
    // Same-host as the Admin/Student page (localhost vs 127.0.0.1).
    if (isWeb && isLoopbackHost(pageHost)) {
      return resolveLocalRagWorkerOrigin(pageHost: pageHost);
    }
    return kLocalClassroomWorkerOrigin;
  }

  if (explicit.isNotEmpty) return explicit;
  return kLocalClassroomWorkerOrigin;
}

/// Production origin used for Student `/ai/lesson` (never loopback).
String productionAiBackendOrigin({
  String configured = '',
  String ragBackendUrl = '',
}) {
  final explicit = _firstNonEmpty([ragBackendUrl, configured]);
  if (explicit.isNotEmpty && !isLoopbackAiBackend(explicit)) {
    return explicit;
  }
  return kProductionAiBackendOrigin;
}

/// Lesson/video HTTP bases. Release/deployed web is production only.
///
/// Localhost Student Web must call the classroom worker (same-host `:8791`)
/// so Chrome does not treat `localhost` → `127.0.0.1` as a failed fetch and
/// fall through to production `/ai/lesson`. Production Netlify `/health` is
/// `{ok:true}` even when `AI_API_KEY` is unset, which previously surfaced as
/// HTTP 500 `AI_API_KEY missing`.
List<String> lessonBackendBaseCandidates({
  required bool debug,
  required bool isWeb,
  String configured = '',
  String ragBackendUrl = '',
  String pageHost = '',
}) {
  final primary = resolveAiBackendBase(
    debug: debug,
    isWeb: isWeb,
    configured: configured,
    ragBackendUrl: ragBackendUrl,
    pageHost: pageHost,
  );
  final releaseWeb = isWeb && !debug;
  final deployedWeb = isWeb && _isDeployedWebHost(pageHost);
  if (releaseWeb || deployedWeb) {
    final prod = productionAiBackendOrigin(
      configured: configured,
      ragBackendUrl: ragBackendUrl,
    );
    if (isLoopbackAiBackend(primary)) return [prod];
    return [primary];
  }
  // Localhost Student Web (including empty Uri.base.host on web-server)
  // must never fall through to production /health {ok:true}.
  if (debug && isWeb && (pageHost.trim().isEmpty || isLoopbackHost(pageHost))) {
    final host = pageHost.trim().isEmpty ? 'localhost' : pageHost.trim();
    return _uniqueUrls([
      resolveLocalRagWorkerOrigin(pageHost: host),
      kLocalClassroomWorkerOrigin,
    ]);
  }
  final prod = productionAiBackendOrigin(
    configured: configured,
    ragBackendUrl: ragBackendUrl,
  );
  if (isLoopbackAiBackend(primary) && prod != primary) {
    return [primary, prod];
  }
  return [primary];
}

List<String> _uniqueUrls(List<String> urls) {
  final out = <String>[];
  for (final url in urls) {
    final trimmed = url.trim().replaceAll(RegExp(r'/$'), '');
    if (trimmed.isEmpty || out.contains(trimmed)) continue;
    out.add(trimmed);
  }
  return out;
}

List<String> lessonBackendBases() {
  const ragBackendUrl = String.fromEnvironment(
    'RAG_BACKEND_URL',
    defaultValue: '',
  );
  const configured = String.fromEnvironment(
    'CLASSROOM_VIDEO_WORKER',
    defaultValue: '',
  );
  return lessonBackendBaseCandidates(
    debug: kDebugMode,
    isWeb: kIsWeb,
    configured: configured,
    ragBackendUrl: ragBackendUrl,
    pageHost: kIsWeb ? Uri.base.host : '',
  );
}

String aiLessonEndpoint(String base) =>
    '${base.replaceAll(RegExp(r'/$'), '')}/ai/lesson';

String aiTtsEndpoint(String base) =>
    '${base.replaceAll(RegExp(r'/$'), '')}/ai/tts';

String aiVideoRenderEndpoint(String base) =>
    '${base.replaceAll(RegExp(r'/$'), '')}/render';

String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    final trimmed = value.trim().replaceAll(RegExp(r'/$'), '');
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

bool _isDeployedWebHost(String pageHost) {
  final host = pageHost.trim().toLowerCase();
  if (host.isEmpty) return false;
  return !isLoopbackHost(host);
}

/// Same-host loopback as the Admin page so Chrome does not treat
/// `localhost:8081` → `127.0.0.1:8791` as a failed fetch and skip the worker.
String resolveLocalRagWorkerOrigin({String pageHost = '127.0.0.1'}) {
  final host = pageHost.trim().toLowerCase();
  if (host == 'localhost' || host == '127.0.0.1') {
    return 'http://$host:8791';
  }
  if (host == '::1' || host == '[::1]') {
    return 'http://[::1]:8791';
  }
  return kLocalClassroomWorkerOrigin;
}

/// Gemini key for the local classroom worker. Prefer process env so the
/// Flutter/Admin web bundle never needs the secret compiled in.
String resolveWorkerGeminiApiKey({
  String envValue = '',
  String definesValue = '',
}) {
  final env = envValue.trim();
  if (env.isNotEmpty) return env;
  return definesValue.trim();
}

/// Local Student Web often starts before the classroom worker finishes compiling.
const kLocalAiWorkerHealthAttempts = 10;
const kLocalAiWorkerHealthRetryDelay = Duration(seconds: 3);

bool shouldWaitForLocalAiWorker({
  required bool debug,
  required bool isWeb,
  required String pageHost,
}) =>
    debug && isWeb && (pageHost.trim().isEmpty || isLoopbackHost(pageHost));

Future<String?> firstHealthyAiBackendBase({
  required List<String> bases,
  required Future<int> Function(String origin) healthStatus,
  bool waitForLocalWorker = false,
}) async {
  final attempts = waitForLocalWorker ? kLocalAiWorkerHealthAttempts : 1;
  for (var i = 0; i < attempts; i++) {
    for (final base in bases) {
      final origin = base.trim().replaceAll(RegExp(r'/$'), '');
      if (origin.isEmpty) continue;
      try {
        if (await healthStatus(origin) != 200) continue;
        // Production /health is {ok:true} without a lesson worker. Debug
        // Student Web must not treat that as a healthy /ai/lesson host.
        if (waitForLocalWorker && !isLoopbackAiBackend(origin)) continue;
        return origin;
      } catch (_) {}
    }
    if (i + 1 < attempts) {
      await Future<void>.delayed(kLocalAiWorkerHealthRetryDelay);
    }
  }
  return null;
}

bool isLoopbackHost(String host) {
  final h = host.trim().toLowerCase();
  return h == 'localhost' ||
      h == '127.0.0.1' ||
      h == '::1' ||
      h == '[::1]';
}

bool isLoopbackAiBackend(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;
  try {
    final uri = Uri.parse(trimmed);
    return isLoopbackHost(uri.host);
  } catch (_) {
    return trimmed.contains('127.0.0.1') ||
        trimmed.contains('localhost') ||
        trimmed.contains('[::1]');
  }
}
