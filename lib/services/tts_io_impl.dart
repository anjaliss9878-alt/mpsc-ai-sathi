import 'dart:io';

import 'package:path_provider/path_provider.dart';

bool get ttsHasEnvironmentCredentials =>
    (Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'] ?? '')
        .trim()
        .isNotEmpty;

String? get ttsEnvironmentCredentialsPath {
  final path =
      (Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'] ?? '').trim();
  return path.isEmpty ? null : path;
}

Future<String?> readTtsCredentialsFile(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsString();
}

Future<String?> writeTtsCacheFile(String key, List<int> bytes, {String ext = 'mp3'}) async {
  final root = await getApplicationDocumentsDirectory();
  final dir = Directory('${root.path}/tts_cache');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final file = File('${dir.path}/$key.$ext');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<({List<int> bytes, String path})?> readTtsCacheFile(
  String key, {
  String ext = 'mp3',
}) async {
  final root = await getApplicationDocumentsDirectory();
  final file = File('${root.path}/tts_cache/$key.$ext');
  if (!await file.exists() || await file.length() == 0) return null;
  return (bytes: await file.readAsBytes(), path: file.path);
}

Future<bool> cacheFileExists(String path) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return false;
  final file = File(trimmed);
  return await file.exists() && await file.length() > 10000;
}

Future<List<int>?> readFileBytes(String path) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return null;
  final file = File(trimmed);
  if (!await file.exists() || await file.length() == 0) return null;
  return file.readAsBytes();
}
