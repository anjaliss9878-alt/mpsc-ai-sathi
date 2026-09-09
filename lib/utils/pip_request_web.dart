import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<bool> requestPictureInPicture() async {
  final videos = web.document.getElementsByTagName('video');
  if (videos.length == 0) return false;
  final el = videos.item(0);
  if (el is! web.HTMLVideoElement) return false;
  try {
    await el.requestPictureInPicture().toDart;
    return true;
  } catch (_) {
    return false;
  }
}
