import 'dart:typed_data';

/// Local file chosen in Admin UI, before the existing Storage upload pipeline.
class AdminPickedLocalFile {
  const AdminPickedLocalFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// HTML `accept` list, e.g. `.pdf` or `.jpg,.png`.
String adminFileInputAccept(List<String> extensions) {
  return extensions
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .map((e) => e.startsWith('.') ? e : '.$e')
      .join(',');
}

bool adminFileNameMatchesExtensions(String name, List<String> extensions) {
  final lower = name.trim().toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot < 0 || dot == lower.length - 1) return false;
  final ext = lower.substring(dot + 1);
  for (final allowed in extensions) {
    final a = allowed.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    if (a == ext) return true;
  }
  return false;
}
