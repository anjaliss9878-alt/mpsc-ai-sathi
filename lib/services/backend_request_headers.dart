import 'package:firebase_auth/firebase_auth.dart';

/// Resolves the Firebase ID token attached to Netlify `/ai/*` and `/rag/*`
/// calls. Secrets stay on the server; this only forwards the signed-in user's
/// ID token.
typedef IdTokenProvider = Future<String?> Function();

Future<String?> defaultBackendIdToken() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  } catch (_) {
    return null;
  }
}

/// JSON + optional `Authorization: Bearer <idToken>` for AI/RAG backends.
Future<Map<String, String>> backendJsonHeaders({
  IdTokenProvider? idToken,
}) async {
  final headers = <String, String>{'Content-Type': 'application/json'};
  final token = '${await (idToken ?? defaultBackendIdToken)() ?? ''}'.trim();
  if (token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  return headers;
}
