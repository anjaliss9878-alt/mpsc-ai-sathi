import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/auth/login_screen.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Reacts to Firebase auth state:
/// - signed out -> [LoginScreen]
/// - signed in  -> [loggedInChild] (the app's existing Home/main shell)
///
/// Sign-in, sign-up and logout all flow back into this single stream, so no
/// manual navigation calls are needed anywhere else in the app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.loggedInChild});

  final Widget loggedInChild;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.orange),
            ),
          );
        }
        if (snapshot.hasData) {
          return loggedInChild;
        }
        return const LoginScreen();
      },
    );
  }
}
