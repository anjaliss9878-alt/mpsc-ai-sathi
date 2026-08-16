import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/media_bytes_cache.dart';
import 'package:mpsc_combine_ai/services/pdf_cache_service.dart';
import 'package:mpsc_combine_ai/services/storage_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/pdf_blob_open.dart';
import 'package:mpsc_combine_ai/utils/student_media.dart';
import 'package:pdfrx/pdfrx.dart';

/// Compact in-app PDF preview with a fullscreen reader.
///
/// Bytes are loaded via Storage `getDownloadURL` / `getData` so Flutter Web
/// never CORS-fetches the public URL. Storage URLs are never shown.
class TopicPdfViewer extends StatefulWidget {
  const TopicPdfViewer({
    super.key,
    required this.url,
    required this.fileName,
    this.title = 'PDF Notes',
    this.height = 220,
  });

  final String url;
  final String fileName;
  final String title;
  final double height;

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
    if (oldWidget.url != widget.url) _load();
  }

  Future<void> _load() async {
    final stored = widget.url.trim();
    if (stored.isEmpty) {
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
      _bytes = null;
    });
    try {
      final cached = mediaBytesCache.read(stored);
      if (cached != null && cached.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _bytes = cached;
          _resolvedUrl = null;
          _loading = false;
          _error = null;
        });
        return;
      }
      final bytes = await storageService.downloadBytes(stored);
      mediaBytesCache.write(stored, bytes);
      if (!mounted) return;
      setState(() {
        _resolvedUrl = null;
        _bytes = bytes;
        _loading = false;
        _error = bytes.isEmpty
            ? 'Could not load this file. Please try again.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = studentFacingMediaError(e);
        _bytes = null;
      });
    }
  }

  String get _heading {
    final named = friendlyAttachmentName(widget.fileName, fallback: '');
    if (named.isNotEmpty && named.toLowerCase() != 'pdf notes') return named;
    return widget.title;
  }

  Future<void> _openExternalPdf() async {
    try {
      var bytes = _bytes;
      bytes ??= await storageService.downloadBytes(widget.url);
      if (bytes.isEmpty) {
        throw StateError('empty');
      }
      if (kIsWeb) {
        await openPdfBytes(bytes, widget.fileName);
        return;
      }
      await pdfCacheService.openPdfFromBytes(
        bytes: bytes,
        fileName: widget.fileName.isNotEmpty ? widget.fileName : 'notes.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(studentFacingMediaError(e))),
      );
    }
  }

  void _openReader() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TopicPdfReaderPage(
          title: _heading,
          bytes: _bytes,
          resolvedUrl: _resolvedUrl,
          onOpenPdf: _openExternalPdf,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.trim().isEmpty) return const SizedBox.shrink();

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
                  onPressed: _loading ? null : _openReader,
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
              child: InkWell(
                onTap: _loading ? null : _openReader,
                child: _PreviewBody(
                  loading: _loading,
                  bytes: _bytes,
                  resolvedUrl: _resolvedUrl,
                  sourceName: 'notes-pdf-preview-${widget.url.hashCode}',
                  error: _error,
                  onRetry: _load,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _loading || _bytes == null ? _openExternalPdf : _openReader,
                    icon: const Icon(Icons.fullscreen_rounded, size: 20),
                    label: Text(_bytes == null ? 'Open PDF' : 'Read fullscreen'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _openExternalPdf,
                    child: const Text('Open PDF'),
                  ),
                ],
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
    this.onOpenPdf,
  });

  final String title;
  final Uint8List? bytes;
  final String? resolvedUrl;
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
          if (widget.onOpenPdf != null)
            TextButton(
              onPressed: widget.onOpenPdf,
              child: const Text('Open PDF', style: TextStyle(color: Colors.white)),
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
    required this.onRetry,
  });

  final bool loading;
  final Uint8List? bytes;
  final String? resolvedUrl;
  final String sourceName;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.orange),
      );
    }
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _PdfDocumentView(
            bytes: bytes,
            resolvedUrl: resolvedUrl,
            sourceName: sourceName,
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
    );
  }
}

class _PdfDocumentView extends StatelessWidget {
  const _PdfDocumentView({
    required this.bytes,
    required this.resolvedUrl,
    required this.sourceName,
    this.controller,
  });

  final Uint8List? bytes;
  final String? resolvedUrl;
  final String sourceName;
  final PdfViewerController? controller;

  @override
  Widget build(BuildContext context) {
    if (bytes != null && bytes!.isNotEmpty) {
      return PdfViewer.data(
        bytes!,
        sourceName: sourceName,
        controller: controller,
        params: PdfViewerParams(
          backgroundColor: const Color(0xFFF7F7F5),
          errorBannerBuilder: (context, error, stack, ref) {
            return _ErrorPane(
              message: studentFacingMediaError(error),
              onRetry: null,
            );
          },
        ),
      );
    }
    return const _ErrorPane(
      message: 'Could not load this file. Please try again.',
      onRetry: null,
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

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
          ],
        ),
      ),
    );
  }
}
