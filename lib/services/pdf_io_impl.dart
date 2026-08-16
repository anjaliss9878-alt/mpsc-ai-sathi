import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> pdfCacheDirectoryPath() async {
  final root = await getApplicationDocumentsDirectory();
  final dir = Directory('${root.path}/notes_pdf_cache');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}

Future<bool> pdfFileExists(String path) async {
  final file = File(path);
  return file.exists();
}

Future<int> pdfFileLength(String path) async {
  final file = File(path);
  if (!await file.exists()) return 0;
  return file.length();
}

Future<void> pdfWriteBytes(String path, List<int> bytes) async {
  await File(path).writeAsBytes(bytes, flush: true);
}

Future<void> pdfEnsureDirectory(String path) async {
  final dir = Directory(path);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
}
