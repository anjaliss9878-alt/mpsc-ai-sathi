import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/screens/auth/login_screen.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Reacts to Firebase auth state:
/// - signed out -> [LoginScreen]
/// - signed in  -> [loggedInChild] (the app's existing Home/main shell)
///
/// Sign-in, sign-up and logout all flow back into this single stream, so no
/// manual navigation calls are needed anywhere else in the app.
///
/// Also watches the student's own profile in real time so that an admin
/// blocking the account (Student Management -> Block) takes effect
/// immediately, even for a session that is already open. [loggedInChild] is
/// shown optimistically while that first profile snapshot is still loading,
/// so normal sign-in is exactly as instant as before this check existed.
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
        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }
        return _BlockedStudentGate(uid: user.uid, child: loggedInChild);
      },
    );
  }
}

class _BlockedStudentGate extends StatelessWidget {
  const _BlockedStudentGate({required this.uid, required this.child});

  final String uid;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StudentProfile?>(
      stream: profileRepository.watchProfile(uid),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        if (profile != null && profile.isBlocked) {
          return const _BlockedScaffold();
        }
        return child;
      },
    );
  }
}

class _BlockedScaffold extends StatelessWidget {
  const _BlockedScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block_rounded, size: 56, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'हे खाते तात्पुरते बंद केले आहे.\n'
                  '(This account has been blocked.)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                const Text(
                  'अधिक माहितीसाठी सहाय्य टीमशी संपर्क करा.\n'
                  '(Please contact support for more information.)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => authService.signOut(),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
