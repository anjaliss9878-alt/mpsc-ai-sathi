// Student-facing helpers for notes media. Never expose Firebase URLs,
// Storage paths, or raw browser/CORS exceptions in the UI.

bool looksLikeUrl(String value) {
  final v = value.trim().toLowerCase();
  return v.contains('http://') ||
      v.contains('https://') ||
      v.contains('firebasestorage') ||
      v.contains('googleapis.com') ||
      v.contains('appspot.com') ||
      v.startsWith('gs://');
}

/// Display name for an attachment. Strips upload timestamps and rejects URLs.
String friendlyAttachmentName(String? raw, {String fallback = 'Notes'}) {
  var name = (raw ?? '').trim();
  if (name.isEmpty || looksLikeUrl(name)) return fallback;
  if (RegExp(r'^\d{8,}_').hasMatch(name)) {
    name = name.substring(name.indexOf('_') + 1);
  }
  if (name.isEmpty || looksLikeUrl(name)) return fallback;
  return name;
}

bool isYoutubeUrl(String url) {
  final u = url.trim().toLowerCase();
  return u.contains('youtube.com') || u.contains('youtu.be');
}

String? youtubeVideoId(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host.contains('youtu.be')) {
    return uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
  }
  if (host.contains('youtube.com')) {
    final v = uri.queryParameters['v'];
    if (v != null && v.isNotEmpty) return v;
    final parts = uri.pathSegments;
    final embed = parts.indexOf('embed');
    if (embed >= 0 && embed + 1 < parts.length) return parts[embed + 1];
  }
  return null;
}

/// Maps load/play failures to a short student message (no stack, no URL).
String studentFacingMediaError(Object error) {
  final s = error.toString().toLowerCase();
  if (s.contains('failed to fetch') ||
      s.contains('typeerror') ||
      s.contains('cors') ||
      s.contains('xmlhttprequest') ||
      s.contains('network')) {
    return 'ही फाइल सध्या उघडता आली नाही. कृपया पुन्हा प्रयत्न करा.';
  }
  if (s.contains('permission') ||
      s.contains('unauthorized') ||
      s.contains('403') ||
      s.contains('401')) {
    return 'ही फाइल सध्या उपलब्ध नाही.';
  }
  if (s.contains('not found') || s.contains('404')) {
    return 'ही फाइल उपलब्ध नाही.';
  }
  return 'ही फाइल सध्या उघडता आली नाही. कृपया पुन्हा प्रयत्न करा.';
}

String formatMediaClock(Duration duration) {
  final h = duration.inHours;
  final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}

String formatMediaClockSeconds(double seconds) {
  if (seconds.isNaN || seconds.isInfinite || seconds < 0) {
    return '00:00';
  }
  return formatMediaClock(Duration(milliseconds: (seconds * 1000).round()));
}
