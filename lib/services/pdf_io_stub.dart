/// Web stub — no dart:io File / Directory APIs.
Future<String> pdfCacheDirectoryPath() async {
  throw UnsupportedError('Local PDF cache is not used on web.');
}

Future<bool> pdfFileExists(String path) async => false;

Future<int> pdfFileLength(String path) async => 0;

Future<void> pdfWriteBytes(String path, List<int> bytes) async {
  throw UnsupportedError('Local PDF cache is not used on web.');
}

Future<void> pdfEnsureDirectory(String path) async {}
