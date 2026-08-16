import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/auth/signup_screen.dart' show targetExamOptions;
import 'package:mpsc_combine_ai/screens/bookmarks/bookmarks_screen.dart';
import 'package:mpsc_combine_ai/screens/certificates/certificates_screen.dart';
import 'package:mpsc_combine_ai/screens/my_performance_screen.dart';
import 'package:mpsc_combine_ai/screens/study_planner_screen.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/auth_widgets.dart';

/// Student Profile tab: shows Name/Email/Mobile/Target-exam, backed by
/// Firestore (`students/{uid}`), plus Logout.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();

  String? _targetExam;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  String get _uid => authService.currentUser?.uid ?? '';
  String get _email => authService.currentUser?.email ?? '';

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final profile = await profileRepository.getProfile(_uid);
      if (!mounted) return;
      setState(() {
        _nameController.text = profile?.name ?? '';
        _mobileController.text = profile?.mobile ?? '';
        _targetExam = (profile != null && profile.targetExam.isNotEmpty)
            ? profile.targetExam
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'प्रोफाइल लोड करता आले नाही. कृपया पुन्हा प्रयत्न करा.\n'
            '(Could not load profile. Please retry.)';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    try {
      await profileRepository.updateSelfEditableFields(
        uid: _uid,
        name: _nameController.text.trim(),
        mobile: _mobileController.text.trim(),
        targetExam: _targetExam ?? '',
      );
      if (!mounted) return;
      setState(() => _infoMessage = 'प्रोफाइल यशस्वीरित्या जतन झाली.\n'
          '(Profile saved successfully.)');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'प्रोफाइल जतन करता आले नाही. कृपया पुन्हा प्रयत्न करा.\n'
            '(Could not save profile. Please retry.)';
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _logout() async {
    await authService.signOut();
    // AuthGate listens to authStateChanges and will switch to Login
    // automatically — no manual navigation needed.
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth > 600 ? 24.0 : 16.0;
    final maxContentWidth = screenWidth > 800 ? 800.0 : double.infinity;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'प्रोफाइल',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                16,
                horizontalPadding,
                24,
              ),
              children: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(child: CircularProgressIndicator(color: AppColors.orange)),
            )
          else
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.navy.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.person_rounded,
                                  color: AppColors.navy,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _nameController.text.isEmpty
                                          ? 'विद्यार्थी'
                                          : _nameController.text,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary,
                                          ),
                                    ),
                                    Text(
                                      _email,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_errorMessage != null) ...[
                    AuthErrorBanner(message: _errorMessage!),
                    const SizedBox(height: 12),
                  ],
                  if (_infoMessage != null) ...[
                    AuthSuccessBanner(message: _infoMessage!),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _nameController,
                    enabled: !_isSaving,
                    decoration: const InputDecoration(
                      labelText: 'पूर्ण नाव',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'नाव टाका' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    initialValue: _email,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'ईमेल',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    enabled: !_isSaving,
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
                        .map((exam) =>
                            DropdownMenuItem(value: exam, child: Text(exam)))
                        .toList(),
                    onChanged: _isSaving
                        ? null
                        : (value) => setState(() => _targetExam = value),
                    validator: (value) =>
                        value == null ? 'लक्ष्य परीक्षा निवडा' : null,
                  ),
                  const SizedBox(height: 20),
                  AuthSubmitButton(
                    label: 'प्रोफाइल जतन करा',
                    isLoading: _isSaving,
                    onPressed: _saveProfile,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.insights_rounded, color: AppColors.navy),
                          title: const Text('प्रगती (Progress)'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const MyPerformanceScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.bookmark_rounded, color: AppColors.navy),
                          title: const Text('बुकमार्क्स'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const BookmarksScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.workspace_premium_rounded, color: AppColors.navy),
                          title: const Text('प्रमाणपत्रे (Certificates)'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const CertificatesScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.download_rounded, color: AppColors.navy),
                          title: const Text('डाउनलोड्स (Downloads)'),
                          subtitle: const Text('Saved notes PDFs & bookmarks'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const BookmarksScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.settings_rounded, color: AppColors.navy),
                          title: const Text('सेटिंग्ज'),
                          subtitle: const Text('Study goals & planner'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const StudyPlannerScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('लॉगआउट करा'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
