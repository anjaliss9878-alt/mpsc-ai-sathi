import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/classroom_theme.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/ai_lesson_studio.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_chapter_debug.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/ai_learning_engine.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/full_lesson_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_generation_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/subject_teacher.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/student_copy.dart';
import 'package:mpsc_combine_ai/widgets/dhada_progress.dart';

/// Topic → subject teacher → complete AI lesson.
/// Students only see “धडा तयार होत आहे…”. No backend stages.
class AiTeacherClassroomScreen extends StatefulWidget {
  const AiTeacherClassroomScreen({
    super.key,
    this.chapter,
    this.subjectTitle,
    this.initialTopic,
    this.autoTeachChapter = false,
    this.embeddedInHub = false,
    this.initialTab = AiLessonStudioTab.video,
    this.teachingSubject,
  });

  final ChapterItem? chapter;
  final String? subjectTitle;
  final String? initialTopic;
  final bool autoTeachChapter;
  final bool embeddedInHub;
  final AiLessonStudioTab initialTab;
  final MpscTeachingSubject? teachingSubject;

  @override
  State<AiTeacherClassroomScreen> createState() =>
      _AiTeacherClassroomScreenState();
}

class _AiTeacherClassroomScreenState extends State<AiTeacherClassroomScreen> {
  late final TextEditingController _topicCtrl;
  late MpscTeachingSubject _teacher;
  bool _pickedTeacher = false;
  bool _busy = false;
  bool _bootstrapped = false;
  bool _audioFailed = false;
  GeneratedLesson? _lesson;
  LessonAudioBundle? _audio;
  String? _error;

  static const _teachers = MpscTeachingSubject.values;

  @override
  void initState() {
    super.initState();
    final seed = widget.chapter?.title ?? widget.initialTopic ?? '';
    _topicCtrl = TextEditingController(text: seed);
    _teacher = widget.teachingSubject ??
        detectMpscTeachingSubject(seed, hint: widget.subjectTitle);
    _topicCtrl.addListener(_onTopicChanged);
    if ((widget.autoTeachChapter || seed.trim().isNotEmpty) &&
        seed.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_bootstrapped) {
          _bootstrapped = true;
          unawaited(_generate());
        }
      });
    }
  }

  @override
  void dispose() {
    _topicCtrl.removeListener(_onTopicChanged);
    _topicCtrl.dispose();
    super.dispose();
  }

  void _onTopicChanged() {
    if (_pickedTeacher) return;
    final next = detectMpscTeachingSubject(
      _topicCtrl.text,
      hint: widget.subjectTitle,
    );
    if (next != _teacher) {
      setState(() => _teacher = next);
    }
  }

  Future<void> _generate({bool forceNew = false}) async {
    final topic = _topicCtrl.text.trim();
    aiChapterLog('ui_topic_input', {'topic': topic});
    if (topic.isEmpty) {
      setState(() => _error = kEnterTopic);
      return;
    }
    if (_busy) return;

    aiChapterLog('ui_generate_pressed', {
      'topic': topic,
      'selected_subject': _teacher.nameEn,
    });

    setState(() {
      _error = null;
      _lesson = null;
      _audio = null;
      _audioFailed = true;
      _busy = true;
    });

    try {
      final lesson = await aiLearningEngine.buildLesson(
        topic: topic,
        subjectContext: widget.subjectTitle ?? _teacher.displayName,
        chapterId: widget.chapter?.id ?? '',
        subjectId: widget.chapter?.subjectId ?? '',
        teachingSubject: _teacher,
        forceRegenerate: forceNew,
      );
      if (!mounted) return;
      aiChapterLog('ui_state_update', {
        'title': lesson.topicName,
        'sections': lesson.slides.length,
        'notes': lesson.notes.isNotEmpty,
        'mcqs': lesson.mcqs.length,
        'pyqs': lesson.pyqs.length,
        'revision': lesson.premium.quickRevision.trim().isNotEmpty,
        'tricks': lesson.premium.memoryTricks.isNotEmpty,
      });
      setState(() {
        _lesson = lesson;
        _busy = false;
        _audio = null;
        _audioFailed = true;
      });
      unawaited(_track(topic));
    } on LessonGenerationException catch (e) {
      aiChapterLog('ui_generate_error', {'error': e.message});
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = studentFacingError(e);
      });
    } catch (e) {
      aiChapterLog('ui_generate_error', {'error': '$e'});
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = studentFacingError(e);
      });
    }
  }

  Future<void> _narrate(GeneratedLesson lesson, String topic) async {
    try {
      final audio = await aiLearningEngine.narrate(
        lesson: lesson,
        topic: topic,
        subject: _teacher,
      );
      if (!mounted) return;
      setState(() => _audio = audio);
    } catch (_) {
      if (!mounted) return;
      setState(() => _audioFailed = true);
    }
  }

  Future<void> _track(String topic) async {
    final uid = authService.currentUser?.uid;
    if (uid == null) return;
    try {
      await studentProgressRepository.upsertContinueSession(
        uid: uid,
        id: 'classroom_${topic.hashCode}',
        type: 'classroom',
        title: topic,
        subtitle: widget.subjectTitle ?? _teacher.teacherTitleMr,
        progress: 0.2,
        payload: {
          'chapterId': widget.chapter?.id ?? '',
          'subjectId': widget.chapter?.subjectId ?? '',
        },
      );
    } catch (_) {}
  }

  Future<void> _newLessonPrompt() async {
    setState(() {
      _lesson = null;
      _audio = null;
      _audioFailed = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lesson = _lesson;
    return Scaffold(
      backgroundColor: ClassroomTheme.ice,
      appBar: widget.embeddedInHub && lesson == null
          ? null
          : AppBar(
              title: Text(lesson?.topicName ?? 'AI शिक्षक'),
              actions: [
                if (lesson != null)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            _newLessonPrompt();
                          },
                    child: const Text('नवीन विषय'),
                  ),
                if (lesson != null)
                  TextButton(
                    onPressed: _busy ? null : () => unawaited(_generate(forceNew: true)),
                    child: const Text('Generate New Lesson'),
                  ),
              ],
            ),
      body: lesson != null
          ? AiLessonStudio(
              lesson: lesson,
              audio: _audio,
              initialTab: widget.initialTab,
              audioFailed: _audioFailed,
            )
          : (_busy ? DhadaProgress(topic: _topicCtrl.text) : _buildPrompt()),
    );
  }

  Widget _buildPrompt() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
          children: [
            const Text(
              'AI शिक्षक',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'कोणताही MPSC विषय टाका. AI शिक्षक मराठीत संपूर्ण धडा शिकवेल.',
              style: TextStyle(
                color: AppColors.textSecondary,
                height: 1.5,
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'शिक्षक निवडा',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _teachers)
                  ChoiceChip(
                    label: Text(t.teacherTitleMr),
                    selected: _teacher == t,
                    selectedColor: AppColors.skySoft,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _teacher == t ? AppColors.sky : AppColors.navy,
                    ),
                    onSelected: (_) => setState(() {
                      _teacher = t;
                      _pickedTeacher = true;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _topicCtrl,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _generate(),
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText:
                    'उदा. गंगा नदी, महाराष्ट्रातील मृदा, संसद, मान्सून, भारतीय राज्यघटना',
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.menu_book_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.skySoft),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFD7E4FF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.sky, width: 1.6),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: _generate,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                child: const Text('AI Lesson तयार करा'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB42318),
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
