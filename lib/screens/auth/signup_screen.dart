import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/widgets/auth_widgets.dart';

/// Common MPSC Combine exam categories offered on Signup/Profile.
const List<String> targetExamOptions = [
  'राज्यसेवा (Rajyaseva)',
  'संयुक्त पूर्व परीक्षा गट ब (Combine Group B)',
  'संयुक्त पूर्व परीक्षा गट क (Combine Group C)',
  'PSI / STI / ASO',
  'इतर (Other)',
];

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _targetExam;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    User user;
    try {
      user = await authService.signUp(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } catch (e) {
      // Only ever reaches here for a genuine signUp failure (e.g. a real
      // FirebaseAuthException such as 'email-already-in-use') — success is
      // handled entirely below, so this can never fire right after a
      // successful signup.
      if (!mounted) return;
      setState(() {
        _errorMessage = e is AuthException ? e.message : e.toString();
        _isLoading = false;
      });
      return;
    }

    // Signup succeeded — create the Firestore profile. A failure here must
    // not block the user from reaching Home; they can complete it later
    // from the Profile screen.
    var profileSaveFailed = false;
    try {
      await profileRepository.saveProfile(
        StudentProfile(
          uid: user.uid,
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          mobile: _mobileController.text.trim(),
          targetExam: _targetExam ?? '',
        ),
      );
    } catch (_) {
      profileSaveFailed = true;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            profileSaveFailed
                ? 'खाते यशस्वीरित्या तयार झाले! प्रोफाइल कृपया नंतर पूर्ण करा.\n'
                    '(Account created successfully! Please complete your '
                    'profile later.)'
                : 'खाते यशस्वीरित्या तयार झाले! स्वागत आहे.\n'
                    '(Account created successfully! Welcome.)',
          ),
        ),
      );

    // Firebase's auth-state stream already fired the moment signUp()
    // succeeded, so AuthGate (which sits above this pushed route, in the
    // Navigator's first route) has already swapped its content to Home.
    // Pop this Signup route off so that Home becomes visible instead of
    // staying hidden underneath it.
    setState(() => _isLoading = false);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'नवीन खाते तयार करा',
      subtitle: 'MPSC COMBINE AI सह अभ्यास सुरू करा',
      icon: Icons.person_add_alt_1_rounded,
      showBackButton: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              AuthErrorBanner(message: _errorMessage!),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _nameController,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                labelText: 'पूर्ण नाव',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'नाव टाका'
                  : null,
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 14),
            TextFormField(
              controller: _mobileController,
              keyboardType: TextInputType.phone,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                labelText: 'मोबाईल नंबर',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'मोबाईल नंबर टाका';
                }
                if (!RegExp(r'^\d{10}$').hasMatch(value.trim())) {
                  return '10 अंकी मोबाईल नंबर टाका';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _targetExam,
              decoration: const InputDecoration(
                labelText: 'लक्ष्य परीक्षा (Target Exam)',
                prefixIcon: Icon(Icons.flag_outlined),
              ),
              items: targetExamOptions
                  .map((exam) => DropdownMenuItem(value: exam, child: Text(exam)))
                  .toList(),
              onChanged: _isLoading
                  ? null
                  : (value) => setState(() => _targetExam = value),
              validator: (value) =>
                  value == null ? 'लक्ष्य परीक्षा निवडा' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              enabled: !_isLoading,
              decoration: InputDecoration(
                labelText: 'पासवर्ड',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'पासवर्ड टाका';
                if (value.length < 6) {
                  return 'पासवर्ड किमान 6 अक्षरांचा असावा';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscurePassword,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                labelText: 'पासवर्ड पुन्हा टाका',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
              validator: (value) {
                if (value != _passwordController.text) {
                  return 'पासवर्ड जुळत नाहीत';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            AuthSubmitButton(
              label: 'नोंदणी करा',
              isLoading: _isLoading,
              onPressed: _submit,
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                child: const Text('आधीच खाते आहे? लॉगिन करा'),
              ),
            ),
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
