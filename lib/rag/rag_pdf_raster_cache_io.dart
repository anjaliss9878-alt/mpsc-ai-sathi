import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

/// Native worker / VM: avoid path_provider (no Flutter plugin channel).
void ensureRagPdfRasterCacheDirectory() {
  Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.path;
}
