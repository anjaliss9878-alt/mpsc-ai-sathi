import 'package:flutter/material.dart';

/// Premium blue & white tokens for AI Classroom only.
/// Does not change global [AppColors] / app theme.
abstract final class ClassroomTheme {
  static const Color navy = Color(0xFF0B2A4A);
  static const Color navyMid = Color(0xFF123A63);
  static const Color sky = Color(0xFF2F6FED);
  static const Color ice = Color(0xFFF4F8FF);
  static const Color glass = Color(0xCCFFFFFF);
  static const Color glassDark = Color(0xB30B1224);
  static const Color accent = Color(0xFFFF8A3D);
  static const Color keyword = Color(0xFF1B6EF3);

  static const LinearGradient stageGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0B2A4A), Color(0xFF123A63), Color(0xFF1A4F86), Color(0xFF245F9E)],
  );

  static const LinearGradient softCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFF0F5FF), Color(0xFFE8F0FF)],
  );

  static const LinearGradient progressGlow = LinearGradient(
    colors: [Color(0xFFFF8A3D), Color(0xFF2F6FED)],
  );

  static List<BoxShadow> softShadow = [
    BoxShadow(
      color: navy.withValues(alpha: 0.10),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];

  static BorderRadius radiusLg = BorderRadius.circular(20);
  static BorderRadius radiusMd = BorderRadius.circular(14);

  static TextStyle display(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!.copyWith(
            color: navy,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          );

  static Decoration glassCard({bool dark = false}) => BoxDecoration(
        color: dark ? glassDark : glass,
        borderRadius: radiusLg,
        border: Border.all(
          color: Colors.white.withValues(alpha: dark ? 0.12 : 0.55),
        ),
        boxShadow: softShadow,
      );
}
