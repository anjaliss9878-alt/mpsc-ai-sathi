import 'dart:html' as html;
import 'dart:typed_data';

String? createAudioBlobUrl(Uint8List bytes, String mimeType) {
  if (bytes.isEmpty) return null;
  final blob = html.Blob([bytes], mimeType);
  return html.Url.createObjectUrlFromBlob(blob);
}

void revokeAudioBlobUrl(String? url) {
  final u = (url ?? '').trim();
  if (u.isEmpty) return;
  try {
    html.Url.revokeObjectUrl(u);
  } catch (_) {}
}
