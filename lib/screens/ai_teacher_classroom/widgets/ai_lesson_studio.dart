import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/classroom_theme.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/ai_lesson_player.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/ai_teacher_lecture_page.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/classroom_avatar.dart';
import 'package:mpsc_combine_ai/screens/ai_teacher_classroom/widgets/lesson_ask_ai_panel.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/full_lesson_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_notes_export.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/video_classroom_engine.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/student_copy.dart';
import 'package:mpsc_combine_ai/widgets/dhada_progress.dart';
import 'package:share_plus/share_plus.dart';

enum AiLessonStudioTab { video, notes, memory, revision, mcqs, pyqs, askAi }

/// Complete AI lesson: video + notes + memory + revision + MCQ + PYQ + Ask AI.
class AiLessonStudio extends StatefulWidget {
  const AiLessonStudio({
    super.key,
    required this.lesson,
    this.audio,
    this.initialTab = AiLessonStudioTab.video,
    this.audioFailed = false,
  });

  final GeneratedLesson lesson;
  final LessonAudioBundle? audio;
  final AiLessonStudioTab initialTab;
  final bool audioFailed;

  @override
  State<AiLessonStudio> createState() => _AiLessonStudioState();
}

class _AiLessonStudioState extends State<AiLessonStudio>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  VideoClassroomEngine? _engine;
  bool _started = false;

  static const _labels = [
    'AI Video Lecture',
    'Exam Notes',
    'Memory Tricks',
    'Quick Revision',
    'MCQ Test',
    'PYQs',
    'Ask AI Doubt',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 7,
      vsync: this,
      initialIndex: widget.initialTab.index.clamp(0, 6),
    );
    _tabs.addListener(_onTab);
    if (widget.audio != null) {
      _attachEngine(widget.audio!);
    }
  }

  @override
  void didUpdateWidget(covariant AiLessonStudio oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audio == null && widget.audio != null) {
      _started = false;
      _attachEngine(widget.audio!);
    }
  }

  void _onTab() {
    if (_tabs.index != 0) {
      _engine?.pause();
    }
  }

  void _attachEngine(LessonAudioBundle audio) {
    _engine?.dispose();
    final engine = VideoClassroomEngine();
    engine.setLesson(widget.lesson);
    _engine = engine;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_start(engine, audio));
    });
    setState(() {});
  }

  Future<void> _start(
    VideoClassroomEngine engine,
    LessonAudioBundle audio,
  ) async {
    if (_started) return;
    _started = true;
    try {
      await engine.attachContinuousAudio(audio);
      if (!mounted) return;
      if (_tabs.index == 0) engine.play();
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.white,
          elevation: 1,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: ClassroomTheme.navy,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: ClassroomTheme.sky,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
            tabs: [for (final l in _labels) Tab(text: l)],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _VideoTab(
                lesson: widget.lesson,
                engine: _engine,
                audio: widget.audio,
                waiting: widget.audio == null && !widget.audioFailed,
                audioFailed: widget.audioFailed,
              ),
              _NotesTab(lesson: widget.lesson),
              _MemoryTab(lesson: widget.lesson),
              _RevisionTab(lesson: widget.lesson),
              _McqTab(lesson: widget.lesson),
              _PyqTab(lesson: widget.lesson),
              LessonAskAiPanel(lesson: widget.lesson),
            ],
          ),
        ),
      ],
    );
  }
}

class _VideoTab extends StatelessWidget {
  const _VideoTab({
    required this.lesson,
    required this.engine,
    required this.waiting,
    this.audio,
    this.audioFailed = false,
  });

  final GeneratedLesson lesson;
  final VideoClassroomEngine? engine;
  final LessonAudioBundle? audio;
  final bool waiting;
  final bool audioFailed;

  @override
  Widget build(BuildContext context) {
    if (waiting && engine == null) {
      return const DhadaProgress();
    }

    final player = engine == null
        ? _StaticSlides(lesson: lesson)
        : ListenableBuilder(
            listenable: engine!,
            builder: (context, _) {
              final e = engine!;
              return AiLessonPlayer(
                slides: e.lesson.slides,
                slideIndex: e.slideIndex,
                revealCount: e.revealCount,
                state: e.isPlaying
                    ? TeacherAvatarState.speaking
                    : TeacherAvatarState.idle,
                isPlaying: e.isPlaying,
                progress: e.progress,
                subtitle: e.caption,
                subtitleHighlight: e.speechProgress,
                keywords: e.currentKeywords,
                activeBulletIndex: e.activeBulletIndex,
                speed: e.playbackSpeed,
                muted: e.muted,
                onPlayPause: e.togglePlayPause,
                onReplay: e.replay,
                onStop: e.stop,
                onSpeedChanged: (s) => unawaited(e.setSpeed(s)),
                onMuteChanged: (m) => unawaited(e.setMuted(m)),
                onSeek: e.seekFraction,
                onNext: e.next,
                onPrevious: e.previous,
                onSkipBack: () => e.skipSeconds(-10),
                onSkipForward: () => e.skipSeconds(10),
                zoom: e.zoomPulse,
                topicName: e.lesson.topicName,
                activeKeyword: e.activeKeyword,
                memoryTrickText: e.premiumSpotlightText,
                showMemoryTrick: e.showMemoryTrick,
                conceptTransition: e.conceptTransition,
                showAvatar: false,
                embedded: false,
              );
            },
          );

    return Column(
      children: [
        if (audioFailed)
          Material(
            color: const Color(0xFFFFF4E5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                kAudioUnavailable,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ),
        Expanded(
          child: ColoredBox(color: Colors.black, child: player),
        ),
        Material(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _showTranscript(context, lesson),
                  icon: const Icon(Icons.closed_caption_rounded, size: 18),
                  label: const Text('Transcript'),
                ),
                TextButton.icon(
                  onPressed: engine == null && audio == null
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => audio == null
                                  ? Scaffold(
                                      appBar: AppBar(title: Text(lesson.topicName)),
                                      body: _StaticSlides(lesson: lesson),
                                    )
                                  : AiTeacherLecturePage(
                                      lesson: lesson,
                                      audio: audio!,
                                    ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.fullscreen_rounded, size: 18),
                  label: const Text('Fullscreen'),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(
                    SharePlus.instance.share(
                      ShareParams(
                        text: lesson.script.join('\n\n'),
                        subject: '${lesson.topicName} — व्याख्यान',
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StaticSlides extends StatelessWidget {
  const _StaticSlides({required this.lesson});

  final GeneratedLesson lesson;

  @override
  Widget build(BuildContext context) {
    if (lesson.slides.isEmpty) {
      return const Center(
        child: Text(
          'स्लाइड्स तयार झाल्या आहेत.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      );
    }
    return AiLessonPlayer(
      slides: lesson.slides,
      slideIndex: 0,
      revealCount: 99,
      state: TeacherAvatarState.idle,
      isPlaying: false,
      progress: 0,
      subtitle: lesson.slides.first.narration,
      speed: 1,
      muted: true,
      onPlayPause: () {},
      onReplay: () {},
      onStop: () {},
      onSpeedChanged: (_) {},
      onMuteChanged: (_) {},
      topicName: lesson.topicName,
      showAvatar: false,
      embedded: false,
    );
  }
}

void _showTranscript(BuildContext context, GeneratedLesson lesson) {
  final lines = lesson.script.isNotEmpty
      ? lesson.script
      : lesson.slides.map((s) => s.narration).where((s) => s.trim().isNotEmpty);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const Text(
            'व्याख्यान Transcript',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(line, style: const TextStyle(height: 1.45)),
            ),
        ],
      );
    },
  );
}

class _NotesTab extends StatelessWidget {
  const _NotesTab({required this.lesson});

  final GeneratedLesson lesson;

  @override
  Widget build(BuildContext context) {
    final p = lesson.premium;
    final facts = p.importantFacts.isNotEmpty
        ? p.importantFacts
        : lesson.notes;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                lesson.topicName,
                style: ClassroomTheme.display(context),
              ),
            ),
            FilledButton.icon(
              onPressed: () => exportVerifiedNotes(lesson),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Download PDF'),
            ),
          ],
        ),
        Text(
          lesson.subjectName,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        _CardBlock(
          title: 'परिचय',
          body: p.introduction.trim().isNotEmpty ? p.introduction : lesson.summary,
        ),
        const SizedBox(height: 12),
        _CardBlock(
          title: 'मुख्य संकल्पना',
          body: (p.mainConcepts.isNotEmpty ? p.mainConcepts : lesson.notes)
              .map((s) => '• $s')
              .join('\n'),
        ),
        const SizedBox(height: 12),
        _CardBlock(
          title: 'तथ्ये',
          body: facts.map((s) => '• $s').join('\n'),
        ),
        const SizedBox(height: 12),
        _CardBlock(
          title: 'MPSC महत्त्वाचे मुद्दे',
          body: (p.examTips.isNotEmpty ? p.examTips : lesson.notes.take(8).toList())
              .map((s) => '• $s')
              .join('\n'),
        ),
        const SizedBox(height: 12),
        _ExamBox(
          title: 'Exam-ready box',
          body: p.factBox.trim().isNotEmpty
              ? p.factBox
              : (p.examTraps.isNotEmpty
                  ? p.examTraps.map((s) => '• $s').join('\n')
                  : lesson.summary),
        ),
        const SizedBox(height: 12),
        _CardBlock(
          title: 'उदाहरणे',
          body: p.examples.map((s) => '• $s').join('\n'),
        ),
        const SizedBox(height: 12),
        _CardBlock(
          title: 'सामान्य चुका',
          body: p.commonMistakes.map((s) => '• $s').join('\n'),
        ),
        const SizedBox(height: 12),
        _CardBlock(
          title: 'जलद पुनरावृत्ती',
          body: p.quickRevision.trim().isNotEmpty
              ? p.quickRevision
              : p.onePageSummary,
        ),
      ],
    );
  }
}

class _MemoryTab extends StatelessWidget {
  const _MemoryTab({required this.lesson});

  final GeneratedLesson lesson;

  String _kind(String text) {
    final t = text.toLowerCase();
    if (t.contains('कलम') || t.contains('अनुच्छेद') || t.contains('article')) {
      return 'Constitutional article';
    }
    if (t.contains('नकाशा') || t.contains('स्थान') || t.contains('जिल्हा')) {
      return 'Location trick';
    }
    if (t.contains('क्रम') || t.contains('आधी') || t.contains('नंतर')) {
      return 'Sequence trick';
    }
    if (t.contains('चित्र') || t.contains('पाहा') || t.contains('कल्पना')) {
      return 'Visual trick';
    }
    return 'Acronym / mnemonic';
  }

  @override
  Widget build(BuildContext context) {
    final tricks = lesson.premium.memoryTricks;
    if (tricks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'या धड्यासाठी स्मरण युक्त्या तयार झाल्या आहेत — नोट्स पहा.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, height: 1.45),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      itemCount: tricks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final trick = tricks[i];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: ClassroomTheme.glassCard(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Chip(
                label: Text(_kind(trick)),
                visualDensity: VisualDensity.compact,
                backgroundColor: AppColors.skySoft,
              ),
              const SizedBox(height: 8),
              Text(trick, style: const TextStyle(height: 1.45, fontSize: 15)),
            ],
          ),
        );
      },
    );
  }
}

class _RevisionTab extends StatelessWidget {
  const _RevisionTab({required this.lesson});

  final GeneratedLesson lesson;

  @override
  Widget build(BuildContext context) {
    final p = lesson.premium;
    final onePager = p.onePageSummary.trim().isNotEmpty
        ? p.onePageSummary
        : lesson.summary;
    final keywords = p.quickRevision.trim().isNotEmpty
        ? p.quickRevision
        : lesson.slides.expand((s) => s.keywords).toSet().join(' · ');
    final years = lesson.slides
        .expand((s) => s.timeline)
        .map((e) => '${e.year}: ${e.label}')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Text('१ मिनिट Quick Revision', style: ClassroomTheme.display(context)),
        const SizedBox(height: 14),
        _CardBlock(title: 'Top facts', body: onePager),
        if (years.isNotEmpty) ...[
          const SizedBox(height: 12),
          _CardBlock(
            title: 'महत्त्वाची वर्षे',
            body: years.take(8).map((s) => '• $s').join('\n'),
          ),
        ],
        if (keywords.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _CardBlock(title: 'Keywords', body: keywords),
        ],
        if (p.pyqInsight.isNotEmpty) ...[
          const SizedBox(height: 12),
          _CardBlock(
            title: 'Frequently asked points',
            body: p.pyqInsight.map((s) => '• $s').join('\n'),
          ),
        ],
        const SizedBox(height: 12),
        _ExamBox(
          title: 'Last-minute revision box',
          body: p.factBox.trim().isNotEmpty
              ? p.factBox
              : (p.importantFacts.take(6).map((s) => '• $s').join('\n')),
        ),
      ],
    );
  }
}

class _McqTab extends StatefulWidget {
  const _McqTab({required this.lesson});

  final GeneratedLesson lesson;

  @override
  State<_McqTab> createState() => _McqTabState();
}

class _McqTabState extends State<_McqTab> {
  int _index = 0;
  int _score = 0;
  int? _selected;
  bool _revealed = false;
  bool _submitted = false;

  List<GeneratedMcq> get _mcqs => widget.lesson.mcqs;

  void _select(int i) {
    if (_revealed) return;
    setState(() {
      _selected = i;
      _revealed = true;
      if (i == _mcqs[_index].correctIndex) _score++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_mcqs.isEmpty) {
      return const Center(
        child: Text(
          'MCQs तयार होत आहेत. कृपया थोडा वेळ थांबा.',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }
    if (_submitted || _index >= _mcqs.length) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
        children: [
          Text('गुण $_score / ${_mcqs.length}', style: ClassroomTheme.display(context)),
          const SizedBox(height: 8),
          Text(
            _score >= (_mcqs.length * 0.7)
                ? 'उत्तम. हा विषय परीक्षेसाठी मजबूत आहे.'
                : 'पुनरावृत्ती करून पुन्हा सराव करा.',
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          _CardBlock(
            title: 'Reference note',
            body: widget.lesson.premium.factBox.trim().isNotEmpty
                ? widget.lesson.premium.factBox
                : widget.lesson.summary,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => setState(() {
              _index = 0;
              _score = 0;
              _selected = null;
              _revealed = false;
              _submitted = false;
            }),
            child: const Text('पुन्हा सराव'),
          ),
        ],
      );
    }
    final q = _mcqs[_index];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Text(
          'प्रश्न ${_index + 1} / ${_mcqs.length}',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            Chip(
              label: Text(q.difficultyLabelMr),
              visualDensity: VisualDensity.compact,
            ),
            Chip(
              label: Text(q.kindLabelMr),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          q.question,
          style: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < q.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: _optionColor(q, i),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => _select(i),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(q.options[i], style: const TextStyle(height: 1.35)),
                ),
              ),
            ),
          ),
        if (_revealed) ...[
          const SizedBox(height: 8),
          _CardBlock(
            title: 'स्पष्टीकरण',
            body: q.explanationFor(_selected ?? 0),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => setState(() {
                if (_index == _mcqs.length - 1) {
                  _submitted = true;
                } else {
                  _index++;
                  _selected = null;
                  _revealed = false;
                }
              }),
              child: Text(_index == _mcqs.length - 1 ? 'Submit' : 'पुढील'),
            ),
          ),
        ],
      ],
    );
  }

  Color _optionColor(GeneratedMcq q, int i) {
    if (!_revealed) return Colors.white;
    if (i == q.correctIndex) return const Color(0xFFD9F6E5);
    if (i == _selected) return const Color(0xFFFFE1E1);
    return Colors.white;
  }
}

class _PyqTab extends StatelessWidget {
  const _PyqTab({required this.lesson});

  final GeneratedLesson lesson;

  @override
  Widget build(BuildContext context) {
    final items = lesson.pyqs.isNotEmpty
        ? lesson.pyqs
        : lesson.premium.pyqInsight
            .map((s) => GeneratedPyq(question: s, analysis: s))
            .toList();
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'PYQs तयार होत आहेत. कृपया थोडा वेळ थांबा.',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final p = items[i];
        final exam = p.exam.trim().isEmpty ? 'MPSC' : p.exam.trim();
        final title = [
          exam,
          if (p.year.trim().isNotEmpty) p.year.trim(),
        ].join(' · ');
        return _CardBlock(
          title: title,
          body: [
            p.question,
            if (p.answer.trim().isNotEmpty) 'उत्तर: ${p.answer}',
            if (p.analysis.trim().isNotEmpty) 'स्पष्टीकरण: ${p.analysis}',
            if (p.whyAsked.trim().isNotEmpty) 'का विचारला: ${p.whyAsked}',
            if (p.trend.trim().isNotEmpty) 'Trend: ${p.trend}',
          ].where((s) => s.trim().isNotEmpty).join('\n\n'),
        );
      },
    );
  }
}

class _CardBlock extends StatelessWidget {
  const _CardBlock({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    if (body.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: ClassroomTheme.glassCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(height: 1.5, fontSize: 14.5)),
        ],
      ),
    );
  }
}

class _ExamBox extends StatelessWidget {
  const _ExamBox({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.skySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.sky.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(height: 1.5, fontSize: 14.5)),
        ],
      ),
    );
  }
}
