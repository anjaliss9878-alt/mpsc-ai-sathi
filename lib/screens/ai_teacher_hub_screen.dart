import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/ai_teacher_classroom_screen.dart'
    deferred as ai_classroom;
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/student_copy.dart';
import 'package:mpsc_combine_ai/widgets/dhada_progress.dart';

/// Student AI Teacher entry. Classroom + doubts live on the generated lesson page.
class AiTeacherHubScreen extends StatefulWidget {
  const AiTeacherHubScreen({
    super.key,
    this.initialMode = AiTeacherMode.classroom,
    this.embeddedInTab = false,
    this.initialTopic,
  });

  final AiTeacherMode initialMode;
  final bool embeddedInTab;
  final String? initialTopic;

  @override
  State<AiTeacherHubScreen> createState() => _AiTeacherHubScreenState();
}

enum AiTeacherMode { classroom, doubts }

class _AiTeacherHubScreenState extends State<AiTeacherHubScreen> {
  bool _loading = true;
  Object? _error;
  Widget? _child;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ai_classroom.loadLibrary();
      if (!mounted) return;
      setState(() {
        _child = ai_classroom.AiTeacherClassroomScreen(
          embeddedInHub: widget.embeddedInTab,
          initialTopic: widget.initialTopic,
          autoTeachChapter: (widget.initialTopic ?? '').trim().isNotEmpty,
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = kLessonFailed;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: widget.embeddedInTab
            ? null
            : AppBar(title: const Text('AI शिक्षक')),
        body: const DhadaProgress(),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: widget.embeddedInTab
            ? null
            : AppBar(title: const Text('AI शिक्षक')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  kLessonFailed,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700, height: 1.45),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _load,
                  child: const Text('पुन्हा प्रयत्न करा'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return _child ?? const SizedBox.shrink();
  }
}
