import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/admin_app.dart';

/// Separate entry point for the Admin Panel — run it with:
///   flutter run -d chrome -t lib/admin_main.dart
///
/// Kept fully independent from `lib/main.dart` (the student app) so the
/// Admin Panel is never bundled into a mobile release build, but shares
/// every Firestore-backed model/service with the student app.
void main() {
  runApp(const AdminApp());
}
