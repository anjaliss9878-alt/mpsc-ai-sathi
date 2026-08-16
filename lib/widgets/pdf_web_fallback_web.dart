import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Inline PDF via the browser's native viewer (no XHR, so no CORS
/// `Failed to fetch`). The download URL is never shown in the widget tree.
class PdfWebFallback extends StatefulWidget {
  const PdfWebFallback({super.key, required this.downloadUrl, this.height = 520});

  final String downloadUrl;
  final double height;

  @override
  State<PdfWebFallback> createState() => _PdfWebFallbackState();
}

class _PdfWebFallbackState extends State<PdfWebFallback> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'topic-pdf-${identityHashCode(this)}';
    final src = widget.downloadUrl;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = src
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true;
      iframe.setAttribute('title', 'PDF notes');
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
