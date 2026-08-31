import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/media_bytes_cache.dart';
import 'package:mpsc_combine_ai/services/pdf_cache_service.dart';
import 'package:mpsc_combine_ai/services/storage_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/firebase_storage_url.dart';
import 'package:mpsc_combine_ai/utils/pdf_blob_open.dart';
import 'package:mpsc_combine_ai/utils/student_media.dart';
import 'package:mpsc_combine_ai/widgets/pdf_web_fallback.dart';
import 'package:pdfrx/pdfrx.dart';

/// Compact in-app PDF preview with a fullscreen reader.
///
/// Prefers already-uploaded bytes (no second network hop). If bytes cannot be
/// fetched on Flutter Web (CORS / `getData`), the original Storage download
/// URL is shown in a browser iframe and via **Open PDF in new tab**. RAG
/// indexing is never required.
class TopicPdfViewer extends StatefulWidget {
  const TopicPdfViewer({
    super.key,
    required this.url,
    required this.fileName,
    this.title = 'PDF Notes',
    this.height = 220,
    this.storagePath = '',
    this.initialBytes,
    this.showDetailedErrors = false,
  });

  final String url;
  final String fileName;
  final String title;
  final double height;
  final String storagePath;
  final Uint8List? initialBytes;
  final bool showDetailedErrors;

  @override
  State<TopicPdfViewer> createState() => _TopicPdfViewerState();
}

class _TopicPdfViewerState extends State<TopicPdfViewer> {
  Uint8List? _bytes;
  String? _resolvedUrl;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TopicPdfViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.storagePath != widget.storagePath ||
        oldWidget.initialBytes != widget.initialBytes) {
      _load();
    }
  }

  String _formatError(Object error) {
    if (widget.showDetailedErrors) return error.toString();
    return studentFacingMediaError(error);
  }

  void _cacheBytes(Uint8List bytes) {
    if (bytes.isEmpty) return;
    final url = widget.url.trim();
    final path = widget.storagePath.trim();
    if (url.isNotEmpty) mediaBytesCache.write(url, bytes);
    if (path.isNotEmpty) mediaBytesCache.write(path, bytes);
  }

  String _bestOpenUrl() {
    final resolved = _resolvedUrl?.trim() ?? '';
    if (resolved.contains('://')) return resolved;
    final stored = widget.url.trim();
    if (stored.contains('://')) return stored;
    return stored;
  }

  Future<void> _load() async {
    final stored = widget.url.trim();
    final path = widget.storagePath.trim();
    if (stored.isEmpty && path.isEmpty) {
      setState(() {
        _loading = false;
        _bytes = null;
        _resolvedUrl = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    Uint8List? bytes = widget.initialBytes;
    if (bytes == null || bytes.isEmpty) {
      bytes = mediaBytesCache.read(stored);
    }
    if ((bytes == null || bytes.isEmpty) && path.isNotEmpty) {
      bytes = mediaBytesCache.read(path);
    }

    String openUrl = stored.contains('://') ? stored : '';
    String? loadError;

    if (bytes != null && bytes.isNotEmpty) {
      _cacheBytes(bytes);
      if (openUrl.isEmpty && path.isNotEmpty) {
        try {
          openUrl = await storageService.resolveDownloadUrl(path);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _resolvedUrl = openUrl.isNotEmpty ? openUrl : null;
        _loading = false;
        _error = null;
      });
      return;
    }

    final loc = path.isNotEmpty ? path : stored;
    try {
      final downloaded = await storageService.downloadBytes(loc);
      if (downloaded.isNotEmpty) {
        bytes = downloaded;
        _cacheBytes(downloaded);
      }
    } catch (e) {
      loadError = _formatError(e);
      debugPrint('[TopicPdfViewer] downloadBytes: $e');
    }

    if (openUrl.isEmpty) {
      try {
        openUrl = await storageService.resolveDownloadUrl(loc);
      } catch (e) {
        debugPrint('[TopicPdfViewer] resolveDownloadUrl: $e');
        loadError ??= _formatError(e);
      }
    }

    if (!mounted) return;
    final billingBlocked = (loadError ?? '').contains('HTTP 402') ||
        (loadError ?? '').toLowerCase().contains('billing');
    final canIframe = !billingBlocked &&
        kIsWeb &&
        openUrl.contains('://') &&
        isValidFirebaseDownloadUrl(openUrl);
    setState(() {
      _bytes = bytes;
      _resolvedUrl = openUrl.isNotEmpty ? openUrl : null;
      _loading = false;
      if (bytes != null && bytes.isNotEmpty) {
        _error = null;
      } else if (canIframe) {
        // Browser iframe / new tab still open the original Storage file.
        _error = widget.showDetailedErrors
            ? '${loadError ?? 'Could not fetch PDF bytes in-app.'} '
                'Showing the original file from Storage instead.'
            : null;
      } else {
        _error = loadError ??
            'Could not load this PDF. No valid Firebase Storage URL was found.';
      }
    });
  }

  String get _heading {
    final named = friendlyAttachmentName(widget.fileName, fallback: '');
    if (named.isNotEmpty && named.toLowerCase() != 'pdf notes') return named;
    return widget.title;
  }

  Future<void> _openInNewTab() async {
    try {
      if (kIsWeb && _bytes != null && _bytes!.isNotEmpty) {
        await openPdfBytes(_bytes!, widget.fileName);
        return;
      }
      var url = _bestOpenUrl();
      if (url.isEmpty || !url.contains('://')) {
        final loc =
            widget.storagePath.trim().isNotEmpty ? widget.storagePath : widget.url;
        url = await storageService.resolveDownloadUrl(loc);
      }
      if (url.isEmpty || !url.contains('://')) {
        throw StateError(
          'No valid PDF URL. Upload the file again or Save Draft first.',
        );
      }
      if (kIsWeb && _bytes != null && _bytes!.isNotEmpty) {
        await openPdfBytes(_bytes!, widget.fileName);
        return;
      }
      await pdfCacheService.openPdf(
        url: url,
        fileName: widget.fileName.isNotEmpty ? widget.fileName : 'notes.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_formatError(e))),
      );
    }
  }

  void _openReader() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TopicPdfReaderPage(
          title: _heading,
          bytes: _bytes,
          resolvedUrl: _bestOpenUrl(),
          showDetailedErrors: widget.showDetailedErrors,
          error: _error,
          onOpenPdf: _openInNewTab,
        ),
      ),
    );
  }

  bool get _canOpen {
    if (_loading) return false;
    if (_bytes != null && _bytes!.isNotEmpty) return true;
    final url = _bestOpenUrl();
    return url.contains('://');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.trim().isEmpty && widget.storagePath.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: AppColors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _heading,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: _canOpen ? _openReader : null,
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: widget.height,
            child: Material(
              color: const Color(0xFFF7F7F5),
              child: _PreviewBody(
                loading: _loading,
                bytes: _bytes,
                resolvedUrl: _bestOpenUrl(),
                sourceName: 'notes-pdf-preview-${widget.url.hashCode}',
                error: _error,
                showDetailedErrors: widget.showDetailedErrors,
                onRetry: _load,
                onOpenInNewTab: _canOpen ? _openInNewTab : null,
                onOpenReader: _canOpen ? _openReader : null,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _canOpen
                      ? () {
                          if (_bytes != null && _bytes!.isNotEmpty) {
                            _openReader();
                          } else {
                            _openInNewTab();
                          }
                        }
                      : null,
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                  label: const Text('Open PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: _canOpen ? _openInNewTab : null,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open PDF in new tab'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fullscreen in-app PDF reader with page controls. Never shows Storage URLs.
class TopicPdfReaderPage extends StatefulWidget {
  const TopicPdfReaderPage({
    super.key,
    required this.title,
    this.bytes,
    this.resolvedUrl,
    this.error,
    this.showDetailedErrors = false,
    this.onOpenPdf,
  });

  final String title;
  final Uint8List? bytes;
  final String? resolvedUrl;
  final String? error;
  final bool showDetailedErrors;
  final Future<void> Function()? onOpenPdf;

  @override
  State<TopicPdfReaderPage> createState() => _TopicPdfReaderPageState();
}

class _TopicPdfReaderPageState extends State<TopicPdfReaderPage> {
  final PdfViewerController _controller = PdfViewerController();
  int _page = 1;
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onViewer);
  }

  @override
  void dispose() {
    _controller.removeListener(_onViewer);
    super.dispose();
  }

  void _onViewer() {
    if (!mounted || !_controller.isReady) return;
    final page = _controller.pageNumber ?? 1;
    final count = _controller.pageCount;
    if (page != _page || count != _pageCount) {
      setState(() {
        _page = page;
        _pageCount = count;
      });
    }
  }

  Future<void> _goTo(int page) async {
    if (!_controller.isReady) return;
    await _controller.goToPage(pageNumber: page.clamp(1, _controller.pageCount));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navyDark,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (widget.bytes != null && widget.bytes!.isNotEmpty) ...[
            IconButton(
              tooltip: 'Zoom in',
              onPressed: () {
                if (!_controller.isReady) return;
                _controller.zoomUp();
              },
              icon: const Icon(Icons.zoom_in_rounded),
            ),
            IconButton(
              tooltip: 'Zoom out',
              onPressed: () {
                if (!_controller.isReady) return;
                _controller.zoomDown();
              },
              icon: const Icon(Icons.zoom_out_rounded),
            ),
          ],
          if (widget.onOpenPdf != null)
            TextButton(
              onPressed: widget.onOpenPdf,
              child: const Text(
                'Open PDF in new tab',
                style: TextStyle(color: Colors.white),
              ),
            ),
          if (_pageCount > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '$_page / $_pageCount',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _PdfDocumentView(
              bytes: widget.bytes,
              resolvedUrl: widget.resolvedUrl,
              sourceName: 'notes-pdf-reader-${widget.title.hashCode}',
              controller: _controller,
              error: widget.error,
              showDetailedErrors: widget.showDetailedErrors,
              onOpenInNewTab: widget.onOpenPdf,
            ),
          ),
          if (_pageCount > 1)
            Container(
              color: AppColors.navy,
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: Row(
                children: [
                  IconButton(
                    color: Colors.white,
                    onPressed: _page > 1 ? () => _goTo(_page - 1) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Slider(
                      value: _page.clamp(1, _pageCount).toDouble(),
                      min: 1,
                      max: _pageCount.toDouble(),
                      divisions: _pageCount - 1,
                      activeColor: AppColors.orange,
                      inactiveColor: Colors.white24,
                      label: '$_page',
                      onChanged: (v) => _goTo(v.round()),
                    ),
                  ),
                  IconButton(
                    color: Colors.white,
                    onPressed: _page < _pageCount ? () => _goTo(_page + 1) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({
    required this.loading,
    required this.bytes,
    required this.resolvedUrl,
    required this.sourceName,
    required this.error,
    required this.showDetailedErrors,
    required this.onRetry,
    required this.onOpenInNewTab,
    required this.onOpenReader,
  });

  final bool loading;
  final Uint8List? bytes;
  final String resolvedUrl;
  final String sourceName;
  final String? error;
  final bool showDetailedErrors;
  final VoidCallback onRetry;
  final Future<void> Function()? onOpenInNewTab;
  final VoidCallback? onOpenReader;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.orange),
      );
    }

    final hasBytes = bytes != null && bytes!.isNotEmpty;
    final hasIframe = kIsWeb &&
        resolvedUrl.contains('://') &&
        isValidFirebaseDownloadUrl(resolvedUrl);

    if (hasBytes) {
      return InkWell(
        onTap: onOpenReader,
        child: IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _PdfDocumentView(
                bytes: bytes,
                resolvedUrl: resolvedUrl,
                sourceName: sourceName,
                error: error,
                showDetailedErrors: showDetailedErrors,
                onOpenInNewTab: onOpenInNewTab,
              ),
              const Align(
                alignment: Alignment.bottomCenter,
                child: ColoredBox(
                  color: Color(0x990A1F44),
                  child: SizedBox(
                    width: double.infinity,
                    height: 36,
                    child: Center(
                      child: Text(
                        'Tap to read fullscreen',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (hasIframe) {
      return Column(
        children: [
          if (error != null && error!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                error!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),
          Expanded(
            child: PdfWebFallback(
              key: ValueKey(resolvedUrl),
              downloadUrl: resolvedUrl,
              height: 200,
            ),
          ),
        ],
      );
    }

    return _ErrorPane(
      message: error ?? 'Could not load this PDF. Please try again.',
      onRetry: onRetry,
      onOpenInNewTab: onOpenInNewTab,
    );
  }
}

class _PdfDocumentView extends StatelessWidget {
  const _PdfDocumentView({
    required this.bytes,
    required this.resolvedUrl,
    required this.sourceName,
    this.controller,
    this.error,
    this.showDetailedErrors = false,
    this.onOpenInNewTab,
  });

  final Uint8List? bytes;
  final String? resolvedUrl;
  final String sourceName;
  final PdfViewerController? controller;
  final String? error;
  final bool showDetailedErrors;
  final Future<void> Function()? onOpenInNewTab;

  @override
  Widget build(BuildContext context) {
    if (bytes != null && bytes!.isNotEmpty) {
      return PdfViewer.data(
        bytes!,
        sourceName: sourceName,
        controller: controller,
        params: PdfViewerParams(
          backgroundColor: const Color(0xFFF7F7F5),
          errorBannerBuilder: (context, err, stack, ref) {
            return _ErrorPane(
              message: showDetailedErrors
                  ? err.toString()
                  : studentFacingMediaError(err),
              onRetry: null,
              onOpenInNewTab: onOpenInNewTab,
            );
          },
        ),
      );
    }

    final url = (resolvedUrl ?? '').trim();
    if (kIsWeb && url.contains('://') && isValidFirebaseDownloadUrl(url)) {
      return PdfWebFallback(
        key: ValueKey(url),
        downloadUrl: url,
        height: 520,
      );
    }

    return _ErrorPane(
      message: error ??
          'Could not load this PDF. Use Open PDF in new tab if the file is in Storage.',
      onRetry: null,
      onOpenInNewTab: onOpenInNewTab,
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({
    required this.message,
    required this.onRetry,
    this.onOpenInNewTab,
  });

  final String message;
  final VoidCallback? onRetry;
  final Future<void> Function()? onOpenInNewTab;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_rounded, color: AppColors.navy, size: 36),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
            if (onOpenInNewTab != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onOpenInNewTab,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open PDF in new tab'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
