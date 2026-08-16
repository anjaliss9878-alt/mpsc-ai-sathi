import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/services/storage_service.dart';
import '../tts_io_stub.dart' if (dart.library.io) '../tts_io_impl.dart' as tts_io;

/// Remote Firebase Storage cache entry for a rendered topic video.
class StoredVideoCacheEntry {
  const StoredVideoCacheEntry({
    required this.topic,
    required this.downloadUrl,
    this.localPath,
    this.mimeType = 'video/mp4',
  });

  final String topic;
  final String downloadUrl;
  final String? localPath;
  final String mimeType;
}

/// Module 5 — Cache rendered MP4s in Firebase Storage keyed by topic hash.
///
/// Best-effort: failures never break local playback. Works for ANY topic.
class VideoStorageCacheService {
  VideoStorageCacheService({
    StorageService? storage,
    FirebaseStorage? firebaseStorage,
    http.Client? client,
  })  : _storage = storage ?? storageService,
        _firebaseStorageOverride = firebaseStorage,
        _client = client ?? http.Client();

  final StorageService _storage;
  final FirebaseStorage? _firebaseStorageOverride;
  final http.Client _client;

  static const String folder = 'ai_videos';

  String keyForTopic(String topic) {
    final material = 'dynvideo|${topic.trim().toLowerCase()}';
    return sha256.convert(utf8.encode(material)).toString().substring(0, 32);
  }

  String _objectPath(String topic, {String ext = 'mp4'}) =>
      '$folder/${keyForTopic(topic)}.$ext';

  FirebaseStorage? get _firebase {
    if (_firebaseStorageOverride != null) return _firebaseStorageOverride;
    try {
      final app = Firebase.app();
      final bucket = app.options.storageBucket;
      if (bucket == null || bucket.isEmpty) return null;
      final gs = bucket.startsWith('gs://') ? bucket : 'gs://$bucket';
      return FirebaseStorage.instanceFor(app: app, bucket: gs);
    } catch (_) {
      return null;
    }
  }

  /// Upload a local MP4 to a deterministic topic path.
  Future<String?> uploadFile({
    required String topic,
    required String localPath,
    String mimeType = 'video/mp4',
  }) async {
    if (kIsWeb) return null;
    final trimmed = topic.trim();
    if (trimmed.isEmpty || localPath.trim().isEmpty) return null;

    try {
      final bytes = await tts_io.readFileBytes(localPath);
      if (bytes == null || bytes.length < 10000) return null;

      final url = await _storage.uploadBytesAtPath(
        path: _objectPath(trimmed),
        bytes: Uint8List.fromList(bytes),
        contentType: mimeType,
      );
      debugPrint('[VideoStorageCache] uploaded topic="$trimmed" url=$url');
      return url;
    } catch (e) {
      debugPrint('[VideoStorageCache] upload skipped: $e');
      return null;
    }
  }

  /// Resolve a cached remote video and optionally download to local cache.
  Future<StoredVideoCacheEntry?> read(String topic) async {
    final trimmed = topic.trim();
    if (trimmed.isEmpty) return null;

    final storage = _firebase;
    if (storage == null) return null;

    try {
      final ref = storage.ref().child(_objectPath(trimmed));
      final url = await ref.getDownloadURL().timeout(
            const Duration(seconds: 12),
          );

      String? localPath;
      if (!kIsWeb) {
        localPath = await _downloadToLocalCache(
          topic: trimmed,
          url: url,
        );
      }

      return StoredVideoCacheEntry(
        topic: trimmed,
        downloadUrl: url,
        localPath: localPath,
        mimeType: 'video/mp4',
      );
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return null;
      debugPrint('[VideoStorageCache] read skipped: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[VideoStorageCache] read skipped: $e');
      return null;
    }
  }

  Future<String?> _downloadToLocalCache({
    required String topic,
    required String url,
  }) async {
    try {
      final key = keyForTopic(topic);
      final cached = await tts_io.readTtsCacheFile('aivideo_$key', ext: 'mp4');
      if (cached != null && cached.bytes.length > 10000) {
        return cached.path;
      }

      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          response.bodyBytes.length < 10000) {
        return null;
      }
      return tts_io.writeTtsCacheFile(
        'aivideo_$key',
        response.bodyBytes,
        ext: 'mp4',
      );
    } catch (e) {
      debugPrint('[VideoStorageCache] download skipped: $e');
      return null;
    }
  }
}

final VideoStorageCacheService videoStorageCacheService =
    VideoStorageCacheService();
