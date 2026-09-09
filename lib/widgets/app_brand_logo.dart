import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_brand.dart';

/// High-quality product logo. Uses [FilterQuality.high] so Netlify / hosted
/// web stays sharp at 1x–3x device pixel ratios.
class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({
    super.key,
    this.size = 72,
    this.borderRadius = 16,
  });

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2;
    final px = (size * dpr).round().clamp(72, 1024);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.asset(
        kAppLogoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        gaplessPlayback: true,
        cacheWidth: px,
        cacheHeight: px,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.school_rounded,
          size: size * 0.55,
        ),
      ),
    );
  }
}
