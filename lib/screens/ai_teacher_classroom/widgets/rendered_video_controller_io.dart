import 'dart:io';

import 'package:video_player/video_player.dart';

VideoPlayerController createRenderedVideoController({
  required String source,
  String? assetKey,
}) {
  final asset = assetKey?.trim();
  if (asset != null && asset.isNotEmpty) {
    return VideoPlayerController.asset(asset);
  }
  if (source.startsWith('asset:')) {
    return VideoPlayerController.asset(source.substring('asset:'.length));
  }
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return VideoPlayerController.networkUrl(Uri.parse(source));
  }
  return VideoPlayerController.file(File(source));
}
