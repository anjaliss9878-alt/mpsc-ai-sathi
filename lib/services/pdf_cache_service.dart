import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pdf_io_stub.dart' if (dart.library.io) 'pdf_io_impl.dart' as pdf_io;

/// Downloads Notes PDFs from Firebase Storage download URLs, caches them on
/// disk for offline re-opens, and opens them in a native PDF viewer.
///
/// On web (no durable app documents dir for this flow), falls back to opening
/// the Storage URL in a new browser tab.
///
/// Important: never imports `dart:io` directly — that breaks Flutter web
/// compilation / Chrome debug attach.
class PdfCacheService {
  PdfCacheService._();

  static final PdfCacheService instance = PdfCacheService._();

  /// Stable, filesystem-safe cache key derived from the Storage URL (so the
  /// same PDF always maps to the same local file across launches).
  String _cacheFileName(String url, String fileName) {
    final digest = url.hashCode.toRadixString(16).replaceAll('-', 'n');
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final withExt = safe.toLowerCase().endsWith('.pdf') ? safe : '$safe.pdf';
    return '${digest}_$withExt';
  }

  Future<String> _cachedPath(String url, String fileName) async {
    final dir = await pdf_io.pdfCacheDirectoryPath();
    return '$dir/${_cacheFileName(url, fileName)}';
  }

  /// Returns a local cached file path for [url], downloading it first when missing.
  Future<String> getCachedOrDownload({
    required String url,
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Local PDF cache is not used on web.');
    }
    final path = await _cachedPath(url, fileName);
    if (await pdf_io.pdfFileExists(path) && await pdf_io.pdfFileLength(path) > 0) {
      onProgress?.call(1);
      return path;
    }

    final uri = Uri.parse(url);
    final request = http.Request('GET', uri);
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw StateError(
        'PDF download failed (HTTP ${streamed.statusCode}).',
      );
    }

    final total = streamed.contentLength ?? 0;
    final bytes = <int>[];
    var received = 0;
    await for (final chunk in streamed.stream) {
      bytes.addAll(chunk);
      received += chunk.length;
      if (total > 0) {
        onProgress?.call(received / total);
      }
    }
    if (bytes.isEmpty) {
      throw StateError('PDF download returned an empty file.');
    }
    await pdf_io.pdfWriteBytes(path, bytes);
    onProgress?.call(1);
    return path;
  }

  Future<void> openPdfFromBytes({
    required List<int> bytes,
    required String fileName,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Use blob open on web.');
    }
    final path = await _cachedPath('local-bytes', fileName);
    await pdf_io.pdfWriteBytes(path, bytes);
    final result = await OpenFilex.open(path, type: 'application/pdf');
    if (result.type == ResultType.done) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'application/pdf', name: fileName)],
        text: fileName,
      ),
    );
  }

  /// Downloads (or reuses cache) then opens the PDF. On web, opens the Storage
  /// URL directly in a new tab.
  Future<void> openPdf({
    required String url,
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw StateError('PDF URL is empty.');
    }

    if (kIsWeb) {
      final uri = Uri.parse(trimmed.contains('://') ? trimmed : 'https://$trimmed');
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        throw StateError('Could not open the PDF in the browser.');
      }
      return;
    }

    final path = await getCachedOrDownload(
      url: trimmed,
      fileName: fileName,
      onProgress: onProgress,
    );
    final result = await OpenFilex.open(path, type: 'application/pdf');
    if (result.type == ResultType.done) return;

    // Fallback: share sheet so the student can still open/save the file when
    // no PDF viewer app is installed.
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'application/pdf', name: fileName)],
        text: fileName,
      ),
    );
  }

  Future<bool> isCached({required String url, required String fileName}) async {
    if (kIsWeb) return false;
    try {
      final path = await _cachedPath(url, fileName);
      return await pdf_io.pdfFileExists(path) &&
          await pdf_io.pdfFileLength(path) > 0;
    } catch (_) {
      return false;
    }
  }
}

final PdfCacheService pdfCacheService = PdfCacheService.instance;
