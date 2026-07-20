import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/auth/admin_login_screen.dart';
import 'package:mpsc_combine_ai/services/admin_repository.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Gatekeeper for the Admin Panel:
/// 1. Signed out -> [AdminLoginScreen].
/// 2. Signed in -> checks `admins/{uid}` in Firestore.
///    - Not an admin -> signs the user out and shows "Not authorized".
///    - Is an admin -> shows [child] (the Admin Dashboard).
class AdminAuthGate extends StatelessWidget {
  const AdminAuthGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScaffold();
        }
        final user = snapshot.data;
        if (user == null) {
          return const AdminLoginScreen();
        }
        return FutureBuilder<bool>(
          future: adminRepository.isAdmin(user.uid),
          builder: (context, adminSnapshot) {
            if (adminSnapshot.connectionState != ConnectionState.done) {
              return const _LoadingScaffold();
            }
            if (adminSnapshot.data == true) {
              return child;
            }
            // Signed in but not on the admin allow-list: kick them out.
            authService.signOut();
            return const AdminLoginScreen(
              notAuthorizedMessage:
                  'This account is not authorized for the Admin Panel.',
            );
          },
        );
      },
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: CircularProgressIndicator(color: AppColors.orange)),
    );
  }
}
