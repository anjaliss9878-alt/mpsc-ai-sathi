import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/chat_message.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Follow-up doubts for the current AI lesson. Uses the existing chat service
/// with the generated notes as grounding context.
class LessonAskAiPanel extends StatefulWidget {
  const LessonAskAiPanel({super.key, required this.lesson});

  final GeneratedLesson lesson;

  @override
  State<LessonAskAiPanel> createState() => _LessonAskAiPanelState();
}

class _LessonAskAiPanelState extends State<LessonAskAiPanel> {
  final _controller = TextEditingController();
  final _messages = <ChatMessage>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _messages.add(
      ChatMessage(
        role: ChatRole.assistant,
        content:
            'या धड्याबाबत शंका विचारा — ${widget.lesson.topicName}. '
            'मी ${widget.lesson.subjectName} शिक्षक आहे.',
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _context {
    final notes = widget.lesson.notes.take(12).join('\n- ');
    final summary = widget.lesson.summary.trim();
    return 'CURRENT LESSON ONLY.\n'
        'Topic: ${widget.lesson.topicName}\n'
        'Subject: ${widget.lesson.subjectName}\n'
        '${summary.isEmpty ? '' : 'Summary: $summary\n'}'
        'Notes:\n- $notes\n\n'
        'Answer in Marathi. Stay on this topic. '
        'If the student asks something unrelated to "${widget.lesson.topicName}", '
        'politely refuse and ask them to question this lesson only.';
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    _controller.clear();
    setState(() {
      _busy = true;
      _messages.add(
        ChatMessage(
          role: ChatRole.user,
          content: text,
          timestamp: DateTime.now(),
        ),
      );
    });
    try {
      final reply = await aiTeacherService.sendMessage(
        history: _messages.length > 1
            ? _messages.sublist(0, _messages.length - 1)
            : const [],
        userMessage: text,
        extraContext: _context,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            role: ChatRole.assistant,
            content: reply,
            timestamp: DateTime.now(),
          ),
        );
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            role: ChatRole.assistant,
            content: 'उत्तर मिळाले नाही. कृपया पुन्हा प्रयत्न करा.',
            timestamp: DateTime.now(),
          ),
        );
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final m = _messages[index];
              final mine = m.isUser;
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: mine ? AppColors.navy : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: mine ? null : Border.all(color: AppColors.navy.withValues(alpha: 0.08)),
                  ),
                  child: Text(
                    m.content,
                    style: TextStyle(
                      color: mine ? Colors.white : AppColors.textPrimary,
                      height: 1.45,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_busy,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'शंका लिहा…',
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _busy ? null : _send,
                style: IconButton.styleFrom(backgroundColor: AppColors.navy),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
