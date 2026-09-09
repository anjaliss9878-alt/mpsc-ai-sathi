import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:mpsc_combine_ai/rag/rag_pdf_page_image.dart';
import 'package:mpsc_combine_ai/rag/rag_pdf_raster_cache_stub.dart'
    if (dart.library.io) 'package:mpsc_combine_ai/rag/rag_pdf_raster_cache_io.dart';
import 'package:pdfrx/pdfrx.dart';

const int kRagPdfRasterMaxPages = 40;
const double kRagPdfRasterTargetWidth = 1100;

/// Rasterize PDF pages with the existing PDFium/pdfrx stack (no extra fonts).
Future<List<RagPdfPageImage>> rasterizePdfPagesForRag(
  Uint8List bytes, {
  required Set<int> pageNumbers,
}) async {
  if (bytes.isEmpty) {
    throw StateError('PDF rasterization failed: empty PDF bytes.');
  }
  try {
    // Set cache path before pdfrxFlutterInitialize so it never calls
    // path_provider.getTemporaryDirectory (missing in the :8791 worker).
    ensureRagPdfRasterCacheDirectory();
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openData(
      bytes,
      sourceName: 'rag-extract-${bytes.length}',
    );
    try {
      final out = <RagPdfPageImage>[];
      var rendered = 0;
      for (final page in document.pages) {
        if (rendered >= kRagPdfRasterMaxPages) break;
        if (pageNumbers.isNotEmpty &&
            !pageNumbers.contains(page.pageNumber)) {
          continue;
        }
        final width = page.width <= 1 ? kRagPdfRasterTargetWidth : page.width;
        final scale = (kRagPdfRasterTargetWidth / width).clamp(1.0, 2.2);
        final fullWidth = page.width * scale;
        final fullHeight = page.height * scale;
        final image = await page.render(
          fullWidth: fullWidth,
          fullHeight: fullHeight,
          backgroundColor: 0xffffffff,
        );
        if (image == null) {
          throw StateError(
            'PDF rasterization failed: page ${page.pageNumber} render returned null.',
          );
        }
        try {
          final png = await _bgraToPng(image.pixels, image.width, image.height);
          if (png.isEmpty) {
            throw StateError(
              'PDF rasterization failed: page ${page.pageNumber} PNG encode was empty.',
            );
          }
          out.add(
            RagPdfPageImage(
              pageNumber: page.pageNumber,
              base64Data: base64Encode(png),
            ),
          );
          rendered++;
        } finally {
          image.dispose();
        }
      }
      return out;
    } finally {
      await document.dispose();
    }
  } catch (e) {
    if (e is StateError && '$e'.contains('PDF rasterization failed')) rethrow;
    throw StateError('PDF rasterization failed: $e');
  }
}

Future<Uint8List> _bgraToPng(Uint8List bgra, int width, int height) async {
  if (width < 1 || height < 1 || bgra.length < width * height * 4) {
    return Uint8List(0);
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bgra,
    width,
    height,
    ui.PixelFormat.bgra8888,
    completer.complete,
  );
  final image = await completer.future;
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return Uint8List(0);
    return byteData.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
