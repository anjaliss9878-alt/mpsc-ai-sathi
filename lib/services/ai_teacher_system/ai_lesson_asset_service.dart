import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/media_bytes_cache.dart';
import 'package:mpsc_combine_ai/services/storage_service.dart';
import '../tts_io_stub.dart' if (dart.library.io) '../tts_io_impl.dart' as tts_io;

/// Uploads / downloads AI Classroom assets by Storage path.
/// Callers never display the HTTPS URL returned by getDownloadURL.
class AiLessonAssetService {
  AiLessonAssetService({StorageService? storage})
      : _storage = storage ?? storageService;

  final StorageService _storage;

  String audioPath(String lessonId, {String ext = 'mp3'}) =>
      'ai_lessons/$lessonId/audio.$ext';
  String legacyAudioPath(String lessonId, {String ext = 'mp3'}) =>
      'audio/$lessonId.$ext';
  String videoPath(String lessonId) => 'videos/ai_lessons/$lessonId.mp4';
  String thumbnailPath(String lessonId) => 'thumbnails/$lessonId.jpg';

  Future<String> uploadAudio({
    required String lessonId,
    required Uint8List bytes,
    String contentType = 'audio/mpeg',
    String ext = 'mp3',
  }) async {
    if (bytes.isEmpty) {
      throw StateError('Cannot upload empty AI Teacher audio');
    }
    final path = audioPath(lessonId, ext: ext);
    await _storage.uploadBytesAtPath(
      path: path,
      bytes: bytes,
      contentType: contentType,
      debugLabel: 'ai-audio',
    );
    if (!await existsAtPath(path)) {
      throw StateError('Audio upload did not create $path');
    }
    mediaBytesCache.write(path, bytes);
    return path;
  }

  Future<bool> existsAtPath(String storedPath) async {
    if (storedPath.trim().isEmpty) return false;
    try {
      await _storage.refFromStored(storedPath).getMetadata();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> uploadVideoBytes({
    required String lessonId,
    required Uint8List bytes,
    String contentType = 'video/mp4',
  }) async {
    final path = videoPath(lessonId);
    await _storage.uploadBytesAtPath(
      path: path,
      bytes: bytes,
      contentType: contentType,
      debugLabel: 'ai-video',
    );
    return path;
  }

  Future<String?> uploadVideoFile({
    required String lessonId,
    required String localPath,
  }) async {
    if (kIsWeb) return null;
    final bytes = await tts_io.readFileBytes(localPath);
    if (bytes == null || bytes.length < 8000) return null;
    return uploadVideoBytes(
      lessonId: lessonId,
      bytes: Uint8List.fromList(bytes),
    );
  }

  Future<String> uploadThumbnail({
    required String lessonId,
    required Uint8List bytes,
  }) async {
    final path = thumbnailPath(lessonId);
    await _storage.uploadBytesAtPath(
      path: path,
      bytes: bytes,
      contentType: 'image/jpeg',
      debugLabel: 'ai-thumb',
    );
    mediaBytesCache.write(path, bytes);
    return path;
  }

  /// Internal playback URL. Never show this string in widgets.
  Future<String> playbackUrl(String storedPath) async {
    return _storage.resolveDownloadUrl(storedPath);
  }

  Future<Uint8List> downloadBytes(String storedPath) async {
    final cached = mediaBytesCache.read(storedPath);
    if (cached != null && cached.isNotEmpty) return cached;
    final bytes = await _storage.downloadBytes(storedPath);
    mediaBytesCache.write(storedPath, bytes);
    if (!kIsWeb) {
      try {
        final key = sha256.convert(utf8.encode(storedPath)).toString().substring(0, 16);
        await tts_io.writeTtsCacheFile('asset_$key', bytes, ext: _ext(storedPath));
      } catch (_) {}
    }
    return bytes;
  }

  Future<void> deletePath(String storedPath) async {
    if (storedPath.trim().isEmpty) return;
    await _storage.deleteByPath(storedPath);
  }

  String _ext(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0) return 'bin';
    return path.substring(i + 1);
  }
}

final AiLessonAssetService aiLessonAssetService = AiLessonAssetService();
