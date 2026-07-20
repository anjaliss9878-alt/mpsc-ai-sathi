import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/firebase_options.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Initializes Firebase exactly once before showing [child].
///
/// Shows a small loading screen while [Firebase.initializeApp] runs, and a
/// clear, non-crashing "setup required" screen if it fails — e.g. because
/// `lib/firebase_options.dart` still has placeholder values. This lets the
/// rest of the app's code (Login/Signup/Profile) be fully implemented and
/// analyzed even before a real Firebase project is connected.
class FirebaseInitializer extends StatefulWidget {
  const FirebaseInitializer({super.key, required this.child});

  final Widget child;

  @override
  State<FirebaseInitializer> createState() => _FirebaseInitializerState();
}

class _FirebaseInitializerState extends State<FirebaseInitializer> {
  late final Future<FirebaseApp> _initFuture = Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FirebaseApp>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StatusScaffold(
            icon: Icons.school_rounded,
            title: 'MPSC COMBINE AI',
            message: 'लोड होत आहे…',
            showSpinner: true,
          );
        }
        if (snapshot.hasError) {
          return _StatusScaffold(
            icon: Icons.cloud_off_rounded,
            title: 'Firebase सेटअप अपूर्ण आहे',
            message: 'लॉगिन/साइनअप सुरू करण्यासाठी Firebase प्रोजेक्ट कॉन्फिगर '
                'करणे आवश्यक आहे.\n\n'
                'कृपया "flutterfire configure" चालवा आणि lib/firebase_options.dart '
                'अद्ययावत करा, नंतर ॲप पुन्हा सुरू करा.\n\n'
                'Technical detail: ${snapshot.error}',
            showSpinner: false,
          );
        }
        return widget.child;
      },
    );
  }
}

class _StatusScaffold extends StatelessWidget {
  const _StatusScaffold({
    required this.icon,
    required this.title,
    required this.message,
    required this.showSpinner,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 56,
                  color: AppColors.navy.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                if (showSpinner) ...[
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(color: AppColors.orange),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
