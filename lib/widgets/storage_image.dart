import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/services/storage_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Loads a Firebase Storage image via SDK bytes so the UI never shows a URL.
class StorageImage extends StatefulWidget {
  const StorageImage({
    super.key,
    required this.storedUrl,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  final String storedUrl;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  State<StorageImage> createState() => _StorageImageState();
}

class _StorageImageState extends State<StorageImage> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storedUrl != widget.storedUrl) _load();
  }

  Future<void> _load() async {
    final url = widget.storedUrl.trim();
    if (url.isEmpty) {
      setState(() {
        _loading = false;
        _bytes = null;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final bytes = await storageService.downloadBytes(url);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_loading) {
      child = ColoredBox(
        color: AppColors.navyDark,
        child: SizedBox(
          height: widget.height ?? 160,
          child: const Center(
            child: CircularProgressIndicator(color: AppColors.orange),
          ),
        ),
      );
    } else if (_bytes == null || _bytes!.isEmpty) {
      child = ColoredBox(
        color: AppColors.navyDark,
        child: SizedBox(
          height: widget.height ?? 160,
          child: const Center(
            child: Icon(Icons.image_outlined, color: Colors.white38, size: 40),
          ),
        ),
      );
    } else {
      child = Image.memory(
        _bytes!,
        width: double.infinity,
        height: widget.height,
        fit: widget.fit,
      );
    }
    final radius = widget.borderRadius;
    if (radius == null) return child;
    return ClipRRect(borderRadius: radius, child: child);
  }
}
