import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/admin_app.dart';

/// Separate entry point for the Admin Panel — run it with:
///   flutter run -d chrome -t lib/admin_main.dart
///
/// Kept fully independent from `lib/main.dart` (the student app) so the
/// Admin Panel is never bundled into a mobile release build, but shares
/// every Firestore-backed model/service with the student app.
void main() {
  // Same as the student entrypoint: required for Flutter web plugins /
  // Firebase before the first frame.
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details, forceReport: true);
  };
  ErrorWidget.builder = (details) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Admin failed to start:\n${details.exception}',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  };
  runApp(const AdminApp());
}
