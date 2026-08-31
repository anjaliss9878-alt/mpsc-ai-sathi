/// Helpers for Firebase Storage download URLs and object paths.
///
/// Used by upload/viewer code and unit tests. Does not talk to the network.

bool isFirebaseStorageUrl(String url) {
  final u = url.trim().toLowerCase();
  if (u.isEmpty) return false;
  return u.startsWith('gs://') ||
      u.contains('firebasestorage.googleapis.com') ||
      u.contains('firebasestorage.app') ||
      u.contains('.appspot.com');
}

/// Object path such as `notes/123_file.pdf` from a download URL, gs:// URI,
/// or relative Storage path.
String? firebaseStorageObjectPath(String stored) {
  final value = stored.trim();
  if (value.isEmpty) return null;

  if (!value.contains('://')) {
    final path = value.replaceFirst(RegExp(r'^/+'), '');
    return path.isEmpty ? null : path;
  }

  final uri = Uri.tryParse(value);
  if (uri == null) return null;

  if (uri.scheme == 'gs') {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segs.isEmpty ? null : segs.join('/');
  }

  final segs = uri.pathSegments;
  final o = segs.indexOf('o');
  if (o >= 0 && o + 1 < segs.length) {
    final encoded = segs.sublist(o + 1).join('/');
    final decoded = Uri.decodeComponent(encoded);
    return decoded.isEmpty ? null : decoded;
  }
  return null;
}

/// True when [url] is a usable Firebase Storage download URL or gs:// / path.
bool isValidFirebaseDownloadUrl(String url) {
  final u = url.trim();
  if (u.isEmpty) return false;
  if (!isFirebaseStorageUrl(u) && u.contains('://')) return false;
  if (!u.contains('://')) {
    return firebaseStorageObjectPath(u) != null;
  }
  if (u.startsWith('gs://')) {
    return firebaseStorageObjectPath(u) != null;
  }
  final uri = Uri.tryParse(u);
  if (uri == null || uri.scheme != 'https') return false;
  if (!isFirebaseStorageUrl(u)) return false;
  final path = firebaseStorageObjectPath(u);
  if (path == null || path.isEmpty) return false;
  return u.contains('/o/') || u.contains('alt=media') || path.contains('/');
}
