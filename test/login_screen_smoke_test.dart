import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/screens/auth/login_screen.dart';
import 'package:mpsc_combine_ai/admin/auth/admin_login_screen.dart';

void main() {
  testWidgets('Student LoginScreen renders email/password form', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pump();

    expect(find.text('MPSC COMBINE AI'), findsOneWidget);
    expect(find.textContaining('लॉगिन'), findsWidgets);
    expect(find.byType(TextFormField), findsAtLeastNWidgets(2));
  });

  testWidgets('AdminLoginScreen renders restricted sign-in UI', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminLoginScreen()));
    await tester.pump();

    expect(find.textContaining('Admin'), findsWidgets);
    expect(find.textContaining('Sign In'), findsOneWidget);
    expect(find.byType(TextFormField), findsAtLeastNWidgets(2));
  });
}
