import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/data/student_onboarding.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/auth_widgets.dart';

/// First-login onboarding. Auth is unchanged; this only fills the existing
/// `students/{uid}` profile before Home.
class StudentOnboardingScreen extends StatefulWidget {
  const StudentOnboardingScreen({super.key, this.existing});

  final StudentProfile? existing;

  @override
  State<StudentOnboardingScreen> createState() => _StudentOnboardingScreenState();
}

class _StudentOnboardingScreenState extends State<StudentOnboardingScreen> {
  int _step = 0;
  bool _saving = false;
  String? _error;

  late final TextEditingController _nameController;
  late String _email;
  String? _targetExam;
  String? _hoursBucket;
  String? _studyMode;
  String? _stage;
  String? _language;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _email = authService.currentUser?.email ?? existing?.email ?? '';
    _nameController = TextEditingController(text: existing?.name ?? '');
    _targetExam = _matchOption(
      existing?.targetExam,
      kOnboardingTargetExamOptions,
    );
    if (_targetExam == null &&
        existing != null &&
        isGroupBCombinedTargetExam(existing.targetExam)) {
      _targetExam = kTargetExamGroupBCombined;
    }
    _hoursBucket = existing != null && existing.dailyStudyHours > 0
        ? dailyHoursBucketFromHours(existing.dailyStudyHours)
        : null;
    _studyMode = existing?.studyMode.isNotEmpty == true
        ? existing!.studyMode
        : null;
    _stage = _matchOption(existing?.preparationStage, kPreparationStageOptions);
    _language =
        _matchOption(existing?.preferredLanguage, kPreferredLanguageOptions);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? _matchOption(String? value, List<String> options) {
    if (value == null || value.trim().isEmpty) return null;
    if (options.contains(value)) return value;
    return null;
  }

  bool get _stepValid {
    switch (_step) {
      case 0:
        return _nameController.text.trim().isNotEmpty;
      case 1:
        return _targetExam != null;
      case 2:
        return _hoursBucket != null && _studyMode != null;
      case 3:
        return _stage != null;
      case 4:
        return _language != null;
      default:
        return false;
    }
  }

  Future<void> _next() async {
    if (!_stepValid || _saving) return;
    if (_step < 4) {
      setState(() {
        _step++;
        _error = null;
      });
      return;
    }
    await _save();
  }

  Future<void> _save() async {
    final uid = authService.currentUser?.uid;
    if (uid == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await profileRepository.saveOnboarding(
        uid: uid,
        name: _nameController.text.trim(),
        email: _email,
        targetExam: _targetExam ?? kTargetExamGroupBCombined,
        dailyStudyHours: dailyHoursFromBucket(_hoursBucket ?? '4–6 hours'),
        studyMode: _studyMode ?? kStudyModePartTime,
        preparationStage: _stage ?? 'Beginner',
        preferredLanguage: _language ?? 'Marathi + English',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save onboarding. Please retry.\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Welcome',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Step ${_step + 1} of 5',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: (_step + 1) / 5,
                    color: AppColors.orange,
                    backgroundColor: AppColors.skySoft,
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    AuthErrorBanner(message: _error!),
                    const SizedBox(height: 12),
                  ],
                  Expanded(child: SingleChildScrollView(child: _stepBody())),
                  Row(
                    children: [
                      if (_step > 0)
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() => _step--),
                          child: const Text('Back'),
                        ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _stepValid && !_saving ? _next : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.navy,
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_step < 4 ? 'Continue' : 'Save & continue'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Basic information',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: _email,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Email (from your account)',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
          ],
        );
      case 1:
        return _choiceList(
          title: 'Target exam',
          options: kOnboardingTargetExamOptions,
          selected: _targetExam,
          onSelect: (v) => setState(() => _targetExam = v),
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _choiceList(
              title: 'How many hours can you study every day?',
              options: kDailyStudyHourOptions,
              selected: _hoursBucket,
              onSelect: (v) => setState(() => _hoursBucket = v),
            ),
            const SizedBox(height: 16),
            _choiceList(
              title: 'Study mode',
              options: const ['Part Time', 'Full Time'],
              selected: _studyMode == kStudyModeFullTime
                  ? 'Full Time'
                  : _studyMode == kStudyModePartTime
                      ? 'Part Time'
                      : null,
              onSelect: (v) => setState(() {
                _studyMode = v == 'Full Time'
                    ? kStudyModeFullTime
                    : kStudyModePartTime;
              }),
            ),
          ],
        );
      case 3:
        return _choiceList(
          title: 'Preparation stage',
          options: kPreparationStageOptions,
          selected: _stage,
          onSelect: (v) => setState(() => _stage = v),
        );
      default:
        return _choiceList(
          title: 'Preferred language',
          options: kPreferredLanguageOptions,
          selected: _language,
          onSelect: (v) => setState(() => _language = v),
        );
    }
  }

  Widget _choiceList({
    required String title,
    required List<String> options,
    required String? selected,
    required ValueChanged<String> onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 12),
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              selected: selected == option,
              selectedTileColor: AppColors.skySoft,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: selected == option ? AppColors.sky : Colors.black12,
                ),
              ),
              title: Text(option),
              trailing: selected == option
                  ? const Icon(Icons.check_circle, color: AppColors.sky)
                  : const Icon(Icons.circle_outlined, color: Colors.black26),
              onTap: () => onSelect(option),
            ),
          ),
      ],
    );
  }
}
