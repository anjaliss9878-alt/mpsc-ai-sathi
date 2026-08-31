import 'dart:typed_data';

/// Best-effort PDF page count from raw bytes (no extra engine).
///
/// Prefers `/Type /Pages` + `/Count N`. Returns null when the catalog cannot
/// be read (encrypted / compressed object streams).
int? pdfPageCountFromBytes(Uint8List bytes) {
  if (bytes.length < 8) return null;
  final header = String.fromCharCodes(
    bytes.sublist(0, bytes.length < 16 ? bytes.length : 16),
  );
  if (!header.contains('%PDF')) return null;

  final sampleLen = bytes.length < 512 * 1024 ? bytes.length : 512 * 1024;
  final text = String.fromCharCodes(bytes.sublist(0, sampleLen));

  final pagesCount = RegExp(
    r'/Type\s*/Pages\b[\s\S]{0,400}?/Count\s+(\d+)',
  ).firstMatch(text);
  if (pagesCount != null) {
    final n = int.tryParse(pagesCount.group(1)!);
    if (n != null && n > 0) return n;
  }

  final countFirst = RegExp(
    r'/Count\s+(\d+)[\s\S]{0,200}?/Type\s*/Pages\b',
  ).firstMatch(text);
  if (countFirst != null) {
    final n = int.tryParse(countFirst.group(1)!);
    if (n != null && n > 0) return n;
  }

  final pageObjs = RegExp(r'/Type\s*/Page\b').allMatches(text).length;
  if (pageObjs > 0) return pageObjs;
  return null;
}

String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
