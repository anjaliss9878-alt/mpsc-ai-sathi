import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/widgets/auth_widgets.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await authService.sendPasswordResetEmail(_emailController.text);
      if (!mounted) return;
      setState(() => _emailSent = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is AuthException ? e.message : e.toString();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'पासवर्ड रिसेट करा',
      subtitle: 'तुमचा नोंदणीकृत ईमेल टाका, आम्ही रिसेट लिंक पाठवू',
      icon: Icons.lock_reset_rounded,
      showBackButton: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_emailSent)
              const AuthSuccessBanner(
                message: 'रिसेट लिंक तुमच्या ईमेलवर पाठवली आहे. कृपया इनबॉक्स '
                    'तपासा.\n(A reset link has been sent to your email. '
                    'Please check your inbox.)',
              )
            else ...[
              if (_errorMessage != null) ...[
                AuthErrorBanner(message: _errorMessage!),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !_isLoading,
                decoration: const InputDecoration(
                  labelText: 'ईमेल',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: _validateEmail,
              ),
              const SizedBox(height: 20),
              AuthSubmitButton(
                label: 'रिसेट लिंक पाठवा',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'ईमेल टाका';
  final regex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
  if (!regex.hasMatch(value.trim())) return 'वैध ईमेल टाका';
  return null;
}
