import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/data/diagnostic_questions.dart';
import 'package:mpsc_combine_ai/data/student_onboarding.dart';
import 'package:mpsc_combine_ai/models/daily_study_plan.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/diagnostic_service.dart';
import 'package:mpsc_combine_ai/services/personalized_study_plan_service.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/services/weakness_analysis.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Diagnostic test → result → personalized plan, then existing Home.
class DiagnosticFlowScreen extends StatefulWidget {
  const DiagnosticFlowScreen({super.key, required this.profile});

  final StudentProfile profile;

  @override
  State<DiagnosticFlowScreen> createState() => _DiagnosticFlowScreenState();
}

class _DiagnosticFlowScreenState extends State<DiagnosticFlowScreen> {
  late final List<DiagnosticQuestion> _questions;
  late List<int?> _selected;
  int _index = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  DiagnosticAttemptResult? _result;
  DiagnosticAttemptResult? _previous;
  DailyStudyPlan? _plan;

  /// Diagnostic writes must use the Firebase Auth UID (same key as
  /// `students/{uid}` in Firestore rules). Never fall back to a stale profile
  /// id if auth is missing — that yields permission-denied.
  String? get _authUid {
    final uid = (authService.currentUser?.uid ?? '').trim();
    return uid.isEmpty ? null : uid;
  }

  String get _uid => _authUid ?? widget.profile.uid;

  String _requireAuthUid() {
    final uid = _authUid;
    if (uid == null) {
      throw StateError(
        'Not signed in. Diagnostic results must be saved under the Firebase Auth UID.',
      );
    }
    final profileUid = widget.profile.uid.trim();
    if (profileUid.isNotEmpty && profileUid != uid) {
      throw StateError(
        'Profile UID does not match Firebase Auth UID.',
      );
    }
    return uid;
  }

  @override
  void initState() {
    super.initState();
    _questions = diagnosticService.questionsForExam(widget.profile.targetExam);
    _selected = List<int?>.filled(_questions.length, null);
    _resumeIfNeeded();
  }

  Future<void> _resumeIfNeeded() async {
    try {
      final stored =
          await studentProgressRepository.latestDiagnosticAttempt(_uid);
      final parsed = diagnosticService.parseStored(stored);
      if (parsed != null && parsed.totalQuestions > 0) {
        DailyStudyPlan? plan;
        DiagnosticAttemptResult? previous;
        try {
          plan = await studentProgressRepository.getDailyPlan(_uid);
          previous = diagnosticService.parseStored(
            await studentProgressRepository.previousDiagnosticAttempt(_uid),
          );
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _result = parsed;
          _previous = previous;
          _plan = plan;
          _loading = false;
        });
        if (plan == null || plan.tasks.isEmpty) {
          await _buildPlan(parsed, uid: _uid);
        }
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = diagnosticService.score(
        attemptId: DateTime.now().millisecondsSinceEpoch.toString(),
        targetExam: widget.profile.targetExam.isEmpty
            ? kTargetExamGroupBCombined
            : widget.profile.targetExam,
        questions: _questions,
        selected: _selected,
      );
      final uid = _requireAuthUid();
      await diagnosticService.persist(uid, result);
      final previousStored =
          diagnosticService.parseStored(
            await studentProgressRepository.previousDiagnosticAttempt(uid),
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _previous = previousStored;
      });
      await _buildPlan(result, uid: uid);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not save the diagnostic result.\n$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _buildPlan(DiagnosticAttemptResult result, {String? uid}) async {
    try {
      final plan = await personalizedStudyPlanService.createAndSave(
        uid: uid ?? _requireAuthUid(),
        profile: widget.profile,
        diagnostic: result,
      );
      if (!mounted) return;
      setState(() => _plan = plan);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Diagnostic saved, but the plan could not be created.\n$e');
    }
  }

  Future<void> _retake() async {
    setState(() {
      _result = null;
      _plan = null;
      _previous = null;
      _error = null;
      _index = 0;
      _selected = List<int?>.filled(_questions.length, null);
    });
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      await profileRepository.markDiagnosticCompleted(_requireAuthUid());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not finish onboarding.\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.orange),
        ),
      );
    }
    if (_result != null) {
      return _ResultScaffold(
        result: _result!,
        previous: _previous,
        plan: _plan,
        saving: _saving,
        error: _error,
        onContinue: _finish,
        onRetake: _retake,
      );
    }
    return _QuestionScaffold(
      questions: _questions,
      selected: _selected,
      index: _index,
      saving: _saving,
      error: _error,
      onSelect: (value) => setState(() => _selected[_index] = value),
      onBack: _index == 0 ? null : () => setState(() => _index--),
      onNext: () {
        if (_index >= _questions.length - 1) {
          _submit();
        } else {
          setState(() => _index++);
        }
      },
    );
  }
}

class _QuestionScaffold extends StatelessWidget {
  const _QuestionScaffold({
    required this.questions,
    required this.selected,
    required this.index,
    required this.saving,
    required this.error,
    required this.onSelect,
    required this.onBack,
    required this.onNext,
  });

  final List<DiagnosticQuestion> questions;
  final List<int?> selected;
  final int index;
  final bool saving;
  final String? error;
  final ValueChanged<int> onSelect;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final q = questions[index];
    final answered = selected[index] != null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Diagnostic Test'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Diagnostic Questions — not PYQs',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Question ${index + 1} of ${questions.length}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (index + 1) / questions.length,
                color: AppColors.orange,
                backgroundColor: AppColors.skySoft,
              ),
              const SizedBox(height: 16),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(error!, style: const TextStyle(color: Colors.red)),
                ),
              Expanded(
                child: ListView(
                  children: [
                    Text(
                      q.question,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 16),
                    for (var i = 0; i < q.options.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          selected: selected[index] == i,
                          selectedTileColor: AppColors.skySoft,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: selected[index] == i
                                  ? AppColors.sky
                                  : Colors.black12,
                            ),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: selected[index] == i
                                ? AppColors.sky
                                : Colors.black12,
                            foregroundColor: selected[index] == i
                                ? Colors.white
                                : AppColors.textPrimary,
                            child: Text(String.fromCharCode(65 + i)),
                          ),
                          title: Text(q.options[i]),
                          onTap: saving ? null : () => onSelect(i),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  if (onBack != null)
                    TextButton(onPressed: saving ? null : onBack, child: const Text('Back')),
                  const Spacer(),
                  FilledButton(
                    onPressed: answered && !saving ? onNext : null,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(index >= questions.length - 1 ? 'Submit' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultScaffold extends StatelessWidget {
  const _ResultScaffold({
    required this.result,
    required this.plan,
    required this.saving,
    required this.error,
    required this.onContinue,
    required this.onRetake,
    this.previous,
  });

  final DiagnosticAttemptResult result;
  final DiagnosticAttemptResult? previous;
  final DailyStudyPlan? plan;
  final bool saving;
  final String? error;
  final VoidCallback onContinue;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Diagnostic Result'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Score: ${result.correctAnswers}/${result.totalQuestions} '
              '(${result.scorePercentage.round()}%)',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Bands use the existing Weakness Tracker: '
              '<50% Weak · 50–69% Improving · ≥70% Strong.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (result.weakAreas.isNotEmpty) ...[
              const Text(
                'Weak areas',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              for (final area in result.weakAreas)
                Card(
                  child: ListTile(
                    title: Text('Weak: ${area.mappingLine}'),
                    trailing: Text(
                      area.band.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (result.improvingAreas.isNotEmpty) ...[
              const Text(
                'Improving',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              for (final area in result.improvingAreas)
                Card(
                  child: ListTile(
                    title: Text(area.mappingLine),
                    trailing: Text(
                      area.band.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.sky,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (result.strongAreas.isNotEmpty) ...[
              const Text(
                'Strong / maintenance',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              for (final area in result.strongAreas)
                Card(
                  child: ListTile(
                    title: Text(area.mappingLine),
                    trailing: Text(
                      area.band.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            for (final area in result.areaResults)
              if (area.band != WeaknessBand.weak &&
                  area.band != WeaknessBand.critical &&
                  area.band != WeaknessBand.improving &&
                  area.band != WeaknessBand.strong)
                Card(
                  child: ListTile(
                    title: Text(area.mappingLine),
                    subtitle: Text(
                      '${area.correct}/${area.attempted} · ${area.percent.round()}%',
                    ),
                    trailing: Text(
                      area.band.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            if (previous != null) ...[
              const SizedBox(height: 8),
              Text(
                'Re-diagnostic comparison',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              for (final line in diagnosticImprovementLines(
                previous: previous!,
                current: result,
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(line),
                ),
            ],
            const SizedBox(height: 20),
            Text(
              'Your Personalized Study Plan is Ready',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            if (plan == null || plan!.tasks.isEmpty)
              const Text(
                'Your diagnostic is saved. Open Study Planner on Home if tasks do not appear yet.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else ...[
              for (final note in plan!.adaptationNotes.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    note,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              const SizedBox(height: 8),
              for (final task in plan!.tasks)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.task_alt_rounded, color: AppColors.navy),
                    title: Text(task.topic),
                    subtitle: Text(
                      '${task.typeLabel} · ${task.subject} · ${task.durationMinutes} min',
                    ),
                  ),
                ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: saving ? null : onRetake,
              child: const Text('Retake diagnostic'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: saving ? null : onContinue,
              style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Go to Home'),
            ),
          ],
        ),
      ),
    );
  }
}
