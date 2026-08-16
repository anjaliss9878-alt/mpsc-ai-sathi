import 'dart:html' as html;
import 'dart:js_util' as js_util;

Future<bool> requestPictureInPicture() async {
  final videos = html.document.getElementsByTagName('video');
  if (videos.isEmpty) return false;
  final el = videos.first;
  if (el is! html.VideoElement) return false;
  try {
    await js_util.promiseToFuture<Object?>(
      js_util.callMethod(el, 'requestPictureInPicture', const []),
    );
    return true;
  } catch (_) {
    return false;
  }
}
