import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// VM / mobile placeholder — web implementation uses an iframe.
class PdfWebFallback extends StatelessWidget {
  const PdfWebFallback({super.key, required this.downloadUrl, this.height = 520});

  final String downloadUrl;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: Text(
          'PDF preview is not available on this device.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
