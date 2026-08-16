import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Progress of an in-flight upload, reported to the Admin Panel's upload
/// progress bars.
class UploadProgress {
  const UploadProgress(this.bytesTransferred, this.totalBytes);

  final int bytesTransferred;
  final int totalBytes;

  double get fraction => totalBytes == 0 ? 0 : bytesTransferred / totalBytes;
}

/// Thin wrapper around Firebase Storage used by every Admin Panel upload
/// (subject images, video files, note/teaching-slide attachments, faculty
/// photos, etc).
///
/// Every file uploaded through this service lives under a predictable path
/// (`<folder>/<timestamp>_<safeFileName>`) so admins can find raw files in
/// the Firebase console if ever needed, while still getting a fresh, unique
/// path per upload (no accidental overwrites).
class StorageService {
  StorageService({FirebaseStorage? storage}) : _storageOverride = storage;

  final FirebaseStorage? _storageOverride;

  /// Resolves the Storage instance against the already-initialized Firebase
  /// app + configured [FirebaseOptions.storageBucket]. Using the explicit
  /// bucket avoids a silent hang when the default instance points at the
  /// wrong / uninitialized bucket on Flutter Web.
  FirebaseStorage get _storage {
    if (_storageOverride != null) return _storageOverride;
    final app = Firebase.app();
    final bucket = app.options.storageBucket;
    if (bucket == null || bucket.isEmpty) {
      throw StateError(
        'Firebase Storage bucket is not configured. '
        'Check DefaultFirebaseOptions.storageBucket.',
      );
    }
    final gs = bucket.startsWith('gs://') ? bucket : 'gs://$bucket';
    return FirebaseStorage.instanceFor(app: app, bucket: gs);
  }

  /// Uploads raw [bytes] to `<folder>/<timestamp>_<safeFileName>` and returns
  /// the public download URL once complete. Reports progress via
  /// [onProgress] as the upload streams.
  ///
  /// Never hangs forever: putData and getDownloadURL are both bounded by
  /// timeouts, and every Firebase / network failure is rethrown with the
  /// exact exception code/message so the Admin form can leave "Saving…".
  Future<String> uploadBytes({
    required String folder,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
    void Function(UploadProgress progress)? onProgress,
  }) async {
    final path = _buildPath(folder: folder, fileName: fileName);
    return uploadBytesAtPath(
      path: path,
      bytes: bytes,
      contentType: contentType ?? _contentTypeFor(fileName),
      onProgress: onProgress,
      debugLabel: fileName,
    );
  }

  /// Uploads to an exact Storage object [path] (used for topic-keyed AI video cache).
  Future<String> uploadBytesAtPath({
    required String path,
    required Uint8List bytes,
    String? contentType,
    void Function(UploadProgress progress)? onProgress,
    String debugLabel = 'bytes',
  }) async {
    debugPrint('[Storage] ===== uploadBytesAtPath START =====');
    debugPrint('[Storage] path=$path label=$debugLabel bytes=${bytes.length}');

    if (bytes.isEmpty) {
      debugPrint('[Storage] FAIL: empty bytes');
      throw StateError(
        'Selected file "$debugLabel" has 0 bytes. Re-select the file and try again.',
      );
    }

    late final FirebaseStorage storage;
    try {
      storage = _storage;
      debugPrint(
        '[Storage] bucket=${storage.bucket} app=${storage.app.name} '
        'optionsBucket=${Firebase.app().options.storageBucket}',
      );
    } catch (e, st) {
      debugPrint('[Storage] FAIL initializing Storage: $e\n$st');
      rethrow;
    }

    // Fail fast when the GCS bucket was never provisioned. On Flutter Web,
    // putData against a missing bucket hangs until timeout instead of
    // returning a clear FirebaseException — that was the "Saving…" hang.
    await _assertBucketExists(storage.bucket);

    final ref = storage.ref().child(path);
    final resolvedType = contentType ?? _contentTypeFor(path);
    debugPrint('[Storage] path=$path contentType=$resolvedType');
    StreamSubscription<TaskSnapshot>? subscription;
    try {
      debugPrint('[Storage] putData starting…');
      final task = ref.putData(
        bytes,
        SettableMetadata(contentType: resolvedType),
      );

      if (onProgress != null) {
        subscription = task.snapshotEvents.listen(
          (snapshot) {
            debugPrint(
              '[Storage] progress ${snapshot.bytesTransferred}/${snapshot.totalBytes} '
              'state=${snapshot.state}',
            );
            onProgress(
              UploadProgress(snapshot.bytesTransferred, snapshot.totalBytes),
            );
          },
          onError: (Object e, StackTrace st) {
            debugPrint('[Storage] snapshotEvents error: $e\n$st');
          },
        );
      }

      final snapshot = await task.timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          debugPrint('[Storage] FAIL: putData timed out after 90s');
          throw TimeoutException(
            'Firebase Storage upload timed out after 90s '
            '(bucket=${storage.bucket}, path=$path). '
            'Bucket exists, so this is usually Storage rules deny, missing '
            'CORS for this web origin, or a network block. '
            'Deploy storage.rules and set cors.json on the bucket.',
          );
        },
      );

      debugPrint(
        '[Storage] putData finished state=${snapshot.state} '
        'bytes=${snapshot.bytesTransferred}',
      );

      if (snapshot.state == TaskState.error) {
        throw StateError(
          'Firebase Storage upload ended in error state for "$debugLabel".',
        );
      }
      if (snapshot.state == TaskState.canceled) {
        throw StateError(
          'Firebase Storage upload was canceled for "$debugLabel".',
        );
      }

      debugPrint('[Storage] getDownloadURL starting…');
      final url = await ref.getDownloadURL().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('[Storage] FAIL: getDownloadURL timed out');
          throw TimeoutException(
            'Firebase Storage getDownloadURL timed out after 30s '
            '(path=$path). Upload may have succeeded — check the Storage console.',
          );
        },
      );
      debugPrint('[Storage] getDownloadURL OK url=$url');
      debugPrint('[Storage] ===== uploadBytes DONE =====');
      return url;
    } on FirebaseException catch (e, st) {
      debugPrint(
        '[Storage] FirebaseException code=${e.code} message=${e.message}\n$st',
      );
      throw StateError(
        'Firebase Storage upload failed [${e.code}]: ${e.message ?? e.toString()} '
        '(file: $debugLabel, path: $path, bucket: ${storage.bucket})',
      );
    } on TimeoutException catch (e, st) {
      debugPrint('[Storage] TimeoutException: $e\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint('[Storage] Unexpected error: $e\n$st');
      throw StateError(
        'Firebase Storage upload failed: $e (file: $debugLabel, path: $path)',
      );
    } finally {
      try {
        await subscription?.cancel();
      } catch (_) {
        // Never block leaving "Saving…" on a listener cancel failure.
      }
    }
  }

  /// Probes Google Cloud Storage metadata for [bucket]. A 404 means Storage
  /// was never enabled for this Firebase project (the real root cause of the
  /// 90s upload timeout). 401/403 means the bucket exists but we are
  /// unauthenticated for the metadata API — that is fine for uploads.
  Future<void> _assertBucketExists(String bucket) async {
    final name = bucket.startsWith('gs://') ? bucket.substring(5) : bucket;
    final uri = Uri.https(
      'storage.googleapis.com',
      '/storage/v1/b/$name',
    );
    debugPrint('[Storage] probing bucket existence: $uri');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      debugPrint('[Storage] bucket probe status=${response.statusCode}');
      if (response.statusCode == 404) {
        throw StateError(
          'Firebase Storage bucket "$name" does not exist. '
          'Open Firebase Console → project mpsc-3f4ef → Build → Storage → '
          'Get started (creates the bucket). firebase_options.dart already '
          'points at this bucket name.',
        );
      }
      // 200 = readable, 401/403 = exists but private — both OK.
    } on TimeoutException {
      debugPrint('[Storage] bucket probe timed out — continuing to upload');
    } on StateError {
      rethrow;
    } catch (e) {
      debugPrint('[Storage] bucket probe error (non-fatal): $e');
    }
  }

  /// Storage object from a download URL, gs:// URI, or relative object path.
  Reference refFromStored(String stored) {
    final value = stored.trim();
    if (value.isEmpty) {
      throw StateError('Storage path is empty.');
    }
    if (value.startsWith('gs://') ||
        value.contains('firebasestorage.googleapis.com') ||
        value.contains('firebasestorage.app') ||
        value.contains('.appspot.com')) {
      return _storage.refFromURL(value);
    }
    final path = value.replaceFirst(RegExp(r'^/+'), '');
    return _storage.ref().child(path);
  }

  /// True when [url] points at this project's Firebase Storage (https or gs).
  bool isFirebaseStorageUrl(String url) {
    final u = url.trim().toLowerCase();
    if (u.isEmpty) return false;
    return u.startsWith('gs://') ||
        u.contains('firebasestorage.googleapis.com') ||
        u.contains('firebasestorage.app') ||
        u.contains('.appspot.com');
  }

  /// Refreshes a Storage object URL through [Reference.getDownloadURL].
  ///
  /// Non-Storage links (YouTube, etc.) are returned unchanged. Never use the
  /// returned string as student-visible UI — it is only for loading media.
  Future<String> resolveDownloadUrl(String stored) async {
    final url = stored.trim();
    if (url.isEmpty) return '';
    try {
      if (isFirebaseStorageUrl(url) || !url.contains('://')) {
        final fresh = await refFromStored(url).getDownloadURL().timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            throw TimeoutException('getDownloadURL timed out');
          },
        );
        debugPrint('[Storage] resolveDownloadUrl OK');
        return fresh;
      }
      return url;
    } catch (e) {
      debugPrint('[Storage] resolveDownloadUrl fallback: $e');
      return isFirebaseStorageUrl(url) ? url : url;
    }
  }

  /// Downloads file bytes. Prefers the Storage SDK ([getDownloadURL] +
  /// [Reference.getData]) so Flutter Web does not CORS-fetch the public URL
  /// the way [PdfViewer.uri] does (`TypeError: Failed to fetch`).
  Future<Uint8List> downloadBytes(
    String stored, {
    int maxSize = 32 * 1024 * 1024,
  }) async {
    final url = stored.trim();
    if (url.isEmpty) {
      throw StateError('File URL is empty.');
    }

    if (isFirebaseStorageUrl(url) || !url.contains('://')) {
      try {
        final ref = refFromStored(url);
        await ref.getDownloadURL().timeout(const Duration(seconds: 20));
        final data = await ref.getData(maxSize).timeout(
          const Duration(seconds: 60),
        );
        if (data != null && data.isNotEmpty) {
          debugPrint('[Storage] getData OK bytes=${data.length}');
          return data;
        }
      } catch (e) {
        debugPrint('[Storage] getData failed, HTTP fallback: $e');
      }
    }

    final resolved = await resolveDownloadUrl(url);
    final response = await http.get(Uri.parse(resolved)).timeout(
      const Duration(seconds: 60),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('File download failed.');
    }
    if (response.bodyBytes.isEmpty) {
      throw StateError('File download returned an empty file.');
    }
    return response.bodyBytes;
  }

  /// Best-effort delete of a previously uploaded file, given its download
  /// URL. Never throws — a missing/foreign file simply means there is
  /// nothing to clean up.
  Future<void> deleteByUrl(String url) async {
    if (url.isEmpty) return;
    try {
      await refFromStored(url).delete();
    } catch (_) {}
  }

  Future<void> deleteByPath(String path) async {
    await deleteByUrl(path);
  }

  String _buildPath({required String folder, required String fileName}) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeName = fileName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    return '$folder/${ts}_$safeName';
  }

  String _contentTypeFor(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'webm':
        return 'video/webm';
      case 'csv':
        return 'text/csv';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      default:
        return 'application/octet-stream';
    }
  }
}

/// Shared instance used across the Admin Panel.
final StorageService storageService = StorageService();
